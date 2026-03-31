package scan

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"

	"github.com/navopw/leafblower/internal/model"
)

// Walker traverses the filesystem and builds a tree of Nodes.
type Walker struct {
	includeHidden bool
	dirCount      atomic.Int64
	fileCount     atomic.Int64
	byteCount     atomic.Int64
	nodeCounter   atomic.Int64
	onProgress    func(model.ProgressEvent)
	itemCount     atomic.Int64
	dirQueued     atomic.Int64 // directories discovered (queued for walking)
	dirDone       atomic.Int64 // directories finished walking

	indexMu sync.Mutex
	index   map[string]*model.Node

	warnMu   sync.Mutex
	warnings []model.ScanWarning

	inodeMu    sync.Mutex
	seenInodes map[uint64]bool
}

// NewWalker creates a new Walker.
func NewWalker(includeHidden bool, onProgress func(model.ProgressEvent)) *Walker {
	return &Walker{
		includeHidden: includeHidden,
		onProgress:    onProgress,
		seenInodes:    make(map[uint64]bool),
	}
}

func (w *Walker) nextID() string {
	n := w.nodeCounter.Add(1)
	return "node_" + strconv.FormatInt(n, 10)
}

// Walk scans rootPath and returns the root Node plus a flat index.
func (w *Walker) Walk(ctx context.Context, scanID, rootPath string) (*model.Node, map[string]*model.Node, []model.ScanWarning, error) {
	absRoot, err := filepath.Abs(rootPath)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("resolve root: %w", err)
	}
	absRoot = filepath.Clean(absRoot)

	info, err := os.Lstat(absRoot)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("stat root: %w", err)
	}
	if !info.IsDir() {
		return nil, nil, nil, fmt.Errorf("root path is not a directory: %s", absRoot)
	}

	rootNode := &model.Node{
		ID:    "root",
		Name:  filepath.Base(absRoot),
		Path:  absRoot,
		IsDir: true,
	}

	w.index = map[string]*model.Node{"root": rootNode}
	w.dirQueued.Add(1) // count the root directory

	// Semaphore — use more goroutines than CPUs since work is I/O-bound
	numWorkers := runtime.NumCPU() * 4
	if numWorkers < 16 {
		numWorkers = 16
	}
	if numWorkers > 128 {
		numWorkers = 128
	}
	sem := make(chan struct{}, numWorkers)

	var wg sync.WaitGroup
	wg.Add(1)
	w.walkDir(ctx, scanID, absRoot, rootNode, sem, &wg)
	wg.Wait()

	if ctx.Err() != nil {
		return nil, nil, nil, ctx.Err()
	}

	// Calculate directory sizes bottom-up
	calcDirSize(rootNode)

	return rootNode, w.index, w.warnings, nil
}

// walkDir reads one directory and spawns goroutines for subdirectories.
func (w *Walker) walkDir(ctx context.Context, scanID, dirPath string, dirNode *model.Node, sem chan struct{}, wg *sync.WaitGroup) {
	defer wg.Done()

	// Acquire semaphore slot
	sem <- struct{}{}
	defer func() { <-sem }()

	// Count this directory as visited (includes root and all subdirectories)
	w.dirCount.Add(1)

	if ctx.Err() != nil {
		w.dirDone.Add(1)
		return
	}

	entries, err := os.ReadDir(dirPath)
	if err != nil {
		w.warnMu.Lock()
		w.warnings = append(w.warnings, model.ScanWarning{
			Path: dirPath,
			Code: "permission_denied",
		})
		w.warnMu.Unlock()
		return
	}

	children := make([]*model.Node, 0, len(entries))

	for _, entry := range entries {
		if ctx.Err() != nil {
			w.dirDone.Add(1)
			return
		}

		name := entry.Name()

		// Skip hidden files/dirs
		if !w.includeHidden && strings.HasPrefix(name, ".") {
			continue
		}

		// Skip symlinks
		if entry.Type()&os.ModeSymlink != 0 {
			continue
		}

		fullPath := filepath.Join(dirPath, name)

		node := &model.Node{
			ID:       w.nextID(),
			Name:     name,
			Path:     fullPath,
			ParentID: dirNode.ID,
			IsDir:    entry.IsDir(),
		}

		if entry.IsDir() {
			w.dirQueued.Add(1)
			children = append(children, node)

			wg.Add(1)
			go w.walkDir(ctx, scanID, fullPath, node, sem, wg)
		} else {
			info, err := entry.Info()
			if err != nil {
				w.warnMu.Lock()
				w.warnings = append(w.warnings, model.ScanWarning{
					Path: fullPath,
					Code: "stat_error",
				})
				w.warnMu.Unlock()
				continue
			}

			// Use actual disk usage (allocated blocks) instead of logical size.
			// info.Size() returns logical size, which can be enormous for sparse
			// files (VM images, Docker layers) and would wildly overcount.
			size := info.Size()
			if stat, ok := info.Sys().(*syscall.Stat_t); ok {
				size = int64(stat.Blocks) * 512 // stat.Blocks is in 512-byte units

				// Deduplicate hard links by inode
				if stat.Nlink > 1 {
					w.inodeMu.Lock()
					if w.seenInodes[uint64(stat.Ino)] {
						size = 0
					} else {
						w.seenInodes[uint64(stat.Ino)] = true
					}
					w.inodeMu.Unlock()
				}
			}

			node.SizeBytes = size
			w.fileCount.Add(1)
			w.byteCount.Add(size)
			children = append(children, node)
		}

		// Progress reporting
		count := w.itemCount.Add(1)
		if count%2000 == 0 && w.onProgress != nil {
			w.onProgress(model.ProgressEvent{
				Type:               "progress",
				ScanID:             scanID,
				Phase:              "walking",
				CurrentPath:        fullPath,
				DirectoriesVisited: w.dirCount.Load(),
				FilesVisited:       w.fileCount.Load(),
				BytesSeen:          w.byteCount.Load(),
				DirsQueued:         w.dirQueued.Load(),
				DirsDone:           w.dirDone.Load(),
			})
		}
	}

	w.dirDone.Add(1)

	// Each dirNode is only written by one goroutine — no lock needed
	dirNode.Children = children
	dirNode.ChildCount = len(children)
	dirNode.HasChildren = len(children) > 0

	// Batch insert all children into index (one lock per directory)
	w.indexMu.Lock()
	for _, child := range children {
		w.index[child.ID] = child
	}
	w.indexMu.Unlock()
}

// calcDirSize recursively sets directory sizes as the sum of children.
func calcDirSize(n *model.Node) int64 {
	if !n.IsDir {
		return n.SizeBytes
	}
	var total int64
	for _, child := range n.Children {
		total += calcDirSize(child)
	}
	n.SizeBytes = total
	return total
}
