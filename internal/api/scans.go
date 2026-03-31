package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sort"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/navopw/leafblower/internal/model"
)

const maxDepth = 10

type startScanRequest struct {
	RootPath      string `json:"rootPath"`
	IncludeHidden bool   `json:"includeHidden"`
}

func (h *handlers) startScan(w http.ResponseWriter, r *http.Request) {
	var req startScanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	if req.RootPath == "" {
		http.Error(w, `{"error":"rootPath is required"}`, http.StatusBadRequest)
		return
	}

	// Expand ~ to home directory
	rootPath := req.RootPath
	if rootPath == "~" || strings.HasPrefix(rootPath, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			rootPath = home + rootPath[1:]
		}
	}

	job, err := h.scanMgr.StartScan(rootPath, req.IncludeHidden)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	json.NewEncoder(w).Encode(map[string]string{
		"scanId": job.ID,
		"status": string(job.Status),
	})
}

func (h *handlers) cancelScan(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if !h.scanMgr.CancelScan(id) {
		http.Error(w, `{"error":"scan not found"}`, http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *handlers) getScan(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	job, ok := h.scanMgr.GetScan(id)
	if !ok {
		http.Error(w, `{"error":"scan not found"}`, http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(job)
}

type treeResponse struct {
	ScanID string      `json:"scanId"`
	Root   *treeNode   `json:"root"`
}

type treeNode struct {
	ID          string      `json:"id"`
	Name        string      `json:"name"`
	Path        string      `json:"path"`
	SizeBytes   int64       `json:"sizeBytes"`
	IsDir       bool        `json:"isDir"`
	ChildCount  int         `json:"childCount"`
	HasChildren bool        `json:"hasChildren"`
	Children    []*treeNode `json:"children,omitempty"`
}

func (h *handlers) getTree(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	job, ok := h.scanMgr.GetScan(id)
	if !ok {
		http.Error(w, `{"error":"scan not found"}`, http.StatusNotFound)
		return
	}
	if job.Status != model.StatusComplete {
		http.Error(w, `{"error":"scan not complete"}`, http.StatusConflict)
		return
	}

	nodeID := r.URL.Query().Get("nodeId")
	if nodeID == "" {
		nodeID = "root"
	}
	depthStr := r.URL.Query().Get("depth")
	depth := 2
	if depthStr != "" {
		if d, err := parsePositiveInt(depthStr); err == nil {
			depth = d
			if depth > maxDepth {
				depth = maxDepth
			}
		}
	}

	node, ok := job.NodeIndex[nodeID]
	if !ok {
		http.Error(w, `{"error":"node not found"}`, http.StatusNotFound)
		return
	}

	tree := buildTreeResponse(node, depth)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(treeResponse{
		ScanID: id,
		Root:   tree,
	})
}

func buildTreeResponse(n *model.Node, depth int) *treeNode {
	tn := &treeNode{
		ID:          n.ID,
		Name:        n.Name,
		Path:        n.Path,
		SizeBytes:   n.SizeBytes,
		IsDir:       n.IsDir,
		ChildCount:  n.ChildCount,
		HasChildren: n.HasChildren,
	}

	if depth > 0 && n.Children != nil {
		// Sort children by size descending
		sorted := make([]*model.Node, len(n.Children))
		copy(sorted, n.Children)
		sort.Slice(sorted, func(i, j int) bool {
			return sorted[i].SizeBytes > sorted[j].SizeBytes
		})

		for _, child := range sorted {
			tn.Children = append(tn.Children, buildTreeResponse(child, depth-1))
		}
	}

	return tn
}

func parsePositiveInt(s string) (int, error) {
	var n int
	for _, c := range s {
		if c < '0' || c > '9' {
			return 0, fmt.Errorf("not a number")
		}
		n = n*10 + int(c-'0')
	}
	return n, nil
}
