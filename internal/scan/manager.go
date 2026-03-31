package scan

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/navopw/leafblower/internal/model"
)

const maxScans = 3

// Manager creates and tracks scan jobs.
type Manager struct {
	mu      sync.RWMutex
	scans   map[string]*scanEntry
	order   []string
	counter int
	sseHub  *SSEHub
}

type scanEntry struct {
	job    *model.ScanJob
	cancel context.CancelFunc
}

// NewManager creates a scan Manager.
func NewManager() *Manager {
	return &Manager{
		scans:  make(map[string]*scanEntry),
		sseHub: NewSSEHub(),
	}
}

// SSE returns the SSE hub.
func (m *Manager) SSE() *SSEHub {
	return m.sseHub
}

// StartScan creates a new scan job and begins scanning in the background.
func (m *Manager) StartScan(rootPath string, includeHidden bool) (*model.ScanJob, error) {
	m.mu.Lock()
	m.counter++
	id := fmt.Sprintf("scan_%d", m.counter)

	ctx, cancel := context.WithCancel(context.Background())

	job := &model.ScanJob{
		ID:            id,
		RootPath:      rootPath,
		IncludeHidden: includeHidden,
		Status:        model.StatusQueued,
		Warnings:      []model.ScanWarning{},
		NodeIndex:     make(map[string]*model.Node),
		CreatedAt:     time.Now(),
	}

	m.scans[id] = &scanEntry{job: job, cancel: cancel}
	m.order = append(m.order, id)

	// Evict old scans beyond max, cancelling running ones
	for len(m.order) > maxScans {
		oldest := m.order[0]
		if entry, ok := m.scans[oldest]; ok {
			entry.cancel()
		}
		delete(m.scans, oldest)
		m.order = m.order[1:]
		m.sseHub.Remove(oldest)
	}
	m.mu.Unlock()

	go m.runScan(ctx, job)
	return job, nil
}

// CancelScan cancels a running scan by ID. Returns true if found.
func (m *Manager) CancelScan(id string) bool {
	m.mu.RLock()
	entry, ok := m.scans[id]
	m.mu.RUnlock()
	if !ok {
		return false
	}
	entry.cancel()
	return true
}

// GetScan returns a scan job by ID.
func (m *Manager) GetScan(id string) (*model.ScanJob, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	entry, ok := m.scans[id]
	if !ok {
		return nil, false
	}
	return entry.job, true
}

func (m *Manager) runScan(ctx context.Context, job *model.ScanJob) {
	m.mu.Lock()
	job.Status = model.StatusRunning
	m.mu.Unlock()

	onProgress := func(evt model.ProgressEvent) {
		m.mu.Lock()
		job.DirectoriesVisited = evt.DirectoriesVisited
		job.FilesVisited = evt.FilesVisited
		job.BytesSeen = evt.BytesSeen
		m.mu.Unlock()
		m.sseHub.Send(job.ID, evt)
	}

	walker := NewWalker(job.IncludeHidden, onProgress)
	rootNode, index, warnings, err := walker.Walk(ctx, job.ID, job.RootPath)

	// Determine outcome and update job state under lock, then send SSE outside lock (M1).
	var evt model.ProgressEvent

	m.mu.Lock()
	if err != nil {
		// Walk returned an error. If it was due to cancellation, mark cancelled;
		// otherwise mark failed. (H4: we check err, not ctx.Err(), so a
		// post-Walk cancel does not discard successful results.)
		if ctx.Err() != nil {
			job.Status = model.StatusCancelled
			evt = model.ProgressEvent{Type: "cancelled", ScanID: job.ID}
		} else {
			job.Status = model.StatusFailed
			job.Warnings = append(job.Warnings, model.ScanWarning{
				Path: job.RootPath,
				Code: err.Error(),
			})
			evt = model.ProgressEvent{Type: "error", ScanID: job.ID}
		}
	} else {
		// Walk completed successfully — commit results regardless of ctx state. (H4)
		job.RootNode = rootNode
		job.NodeIndex = index
		job.Warnings = warnings
		job.DirectoriesVisited = walker.dirCount.Load()
		job.FilesVisited = walker.fileCount.Load()
		job.BytesSeen = walker.byteCount.Load()
		job.Status = model.StatusComplete
		evt = model.ProgressEvent{Type: "complete", ScanID: job.ID, RootNodeID: "root"}
	}
	m.mu.Unlock()

	m.sseHub.Send(job.ID, evt)
}
