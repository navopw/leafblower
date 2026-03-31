package api

import (
	"encoding/json"
	"net/http"

	"github.com/navopw/leafblower/internal/model"
)

func (h *handlers) deletePaths(w http.ResponseWriter, r *http.Request) {
	var req model.DeleteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	if req.ScanID == "" || len(req.NodeIDs) == 0 {
		http.Error(w, `{"error":"scanId and nodeIds are required"}`, http.StatusBadRequest)
		return
	}

	job, ok := h.scanMgr.GetScan(req.ScanID)
	if !ok {
		http.Error(w, `{"error":"scan not found"}`, http.StatusNotFound)
		return
	}
	if job.Status != model.StatusComplete {
		http.Error(w, `{"error":"scan not complete"}`, http.StatusConflict)
		return
	}

	resp := h.delSvc.Execute(job, req.NodeIDs)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}
