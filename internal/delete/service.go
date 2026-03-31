package delete

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/navopw/leafblower/internal/model"
)

// Service handles safe deletion of scan nodes.
type Service struct {
	homeDir string
}

// NewService creates a deletion service. Returns an error if the home directory cannot be determined.
func NewService() (*Service, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("cannot determine home directory: %w", err)
	}
	return &Service{homeDir: home}, nil
}

// Execute deletes the requested nodes from a scan job.
func (s *Service) Execute(job *model.ScanJob, nodeIDs []string) model.DeleteResponse {
	job.Mu.Lock()
	defer job.Mu.Unlock()

	if job.Status != model.StatusComplete {
		failed := make([]model.DeleteResult, 0, len(nodeIDs))
		for _, id := range nodeIDs {
			failed = append(failed, model.DeleteResult{
				NodeID: id,
				Error:  "scan is not complete",
			})
		}
		return model.DeleteResponse{
			Deleted: []model.DeleteResult{},
			Failed:  failed,
		}
	}

	resp := model.DeleteResponse{
		Deleted: []model.DeleteResult{},
		Failed:  []model.DeleteResult{},
	}

	// Resolve nodes
	var nodes []*model.Node
	for _, id := range nodeIDs {
		node, ok := job.NodeIndex[id]
		if !ok {
			resp.Failed = append(resp.Failed, model.DeleteResult{
				NodeID: id,
				Error:  "node not found in scan",
			})
			continue
		}
		nodes = append(nodes, node)
	}

	// Normalize: remove children if parent is also selected
	nodes = normalizeSelection(nodes)

	for _, node := range nodes {
		result := model.DeleteResult{
			NodeID: node.ID,
			Path:   node.Path,
		}

		if err := s.validatePath(node.Path, job.RootPath); err != nil {
			result.Error = err.Error()
			resp.Failed = append(resp.Failed, result)
			continue
		}

		if err := os.RemoveAll(node.Path); err != nil {
			result.Error = err.Error()
			resp.Failed = append(resp.Failed, result)
			continue
		}

		pruneNode(job, node)
		resp.Deleted = append(resp.Deleted, result)
	}

	return resp
}

// criticalPaths lists directories that must never be deleted regardless of other checks.
var criticalPaths = []string{
	"/",
	"/bin", "/sbin", "/usr", "/etc", "/lib", "/lib64",
	"/boot", "/dev", "/proc", "/sys", "/run",
	"/System", "/Library", "/Applications", "/Volumes",
	"/private",
}

func (s *Service) validatePath(path, scanRoot string) error {
	cleanPath := filepath.Clean(path)
	cleanRoot := filepath.Clean(scanRoot)

	// Must be under scan root
	if !strings.HasPrefix(cleanPath, cleanRoot+string(os.PathSeparator)) && cleanPath != cleanRoot {
		return fmt.Errorf("path is outside scan root")
	}

	// Cannot delete the scan root itself
	if cleanPath == cleanRoot {
		return fmt.Errorf("cannot delete scan root")
	}

	// Must be under home directory (v1 safety)
	if s.homeDir != "" {
		cleanHome := filepath.Clean(s.homeDir)
		if !strings.HasPrefix(cleanPath, cleanHome+string(os.PathSeparator)) {
			return fmt.Errorf("deletion restricted to home directory in v1")
		}
	}

	// Defense-in-depth: never delete critical system directories.
	for _, critical := range criticalPaths {
		if cleanPath == critical || strings.HasPrefix(cleanPath, critical+string(os.PathSeparator)) {
			return fmt.Errorf("deletion of critical system path is not allowed")
		}
	}

	return nil
}

// pruneNode removes a node from the job's in-memory tree and propagates size changes upward.
func pruneNode(job *model.ScanJob, node *model.Node) {
	// Remove from direct parent's Children slice
	if node.ParentID != "" {
		if parent, ok := job.NodeIndex[node.ParentID]; ok {
			for i, child := range parent.Children {
				if child.ID == node.ID {
					parent.Children = append(parent.Children[:i], parent.Children[i+1:]...)
					parent.ChildCount = len(parent.Children)
					parent.HasChildren = len(parent.Children) > 0
					break
				}
			}
		}
	}

	// Propagate size reduction up to root
	sizeToRemove := node.SizeBytes
	parentID := node.ParentID
	for parentID != "" {
		parent, ok := job.NodeIndex[parentID]
		if !ok {
			break
		}
		parent.SizeBytes -= sizeToRemove
		parentID = parent.ParentID
	}

	// Remove node and all its descendants from the index
	removeFromIndex(job.NodeIndex, node)
}

func removeFromIndex(index map[string]*model.Node, node *model.Node) {
	delete(index, node.ID)
	for _, child := range node.Children {
		removeFromIndex(index, child)
	}
}

// normalizeSelection removes nodes whose ancestors are also in the selection.
func normalizeSelection(nodes []*model.Node) []*model.Node {
	pathSet := make(map[string]bool)
	for _, n := range nodes {
		pathSet[n.Path] = true
	}

	var result []*model.Node
	for _, n := range nodes {
		if !hasAncestor(n.Path, pathSet) {
			result = append(result, n)
		}
	}
	return result
}

func hasAncestor(path string, pathSet map[string]bool) bool {
	parent := filepath.Dir(path)
	for parent != path {
		if pathSet[parent] {
			return true
		}
		path = parent
		parent = filepath.Dir(parent)
	}
	return false
}
