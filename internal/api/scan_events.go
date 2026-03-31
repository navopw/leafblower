package api

import (
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/navopw/leafblower/internal/model"
)

func (h *handlers) scanEvents(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	job, ok := h.scanMgr.GetScan(id)
	if !ok {
		http.Error(w, `{"error":"scan not found"}`, http.StatusNotFound)
		return
	}

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming not supported", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	// No CORS header — same-origin only for security

	// If the scan already reached a terminal state before we subscribed,
	// emit the terminal event immediately and return to avoid hanging forever.
	var terminalType string
	switch job.Status {
	case model.StatusComplete:
		terminalType = "complete"
	case model.StatusFailed:
		terminalType = "error"
	case model.StatusCancelled:
		terminalType = "cancelled"
	}
	if terminalType != "" {
		evt := model.ProgressEvent{Type: terminalType, ScanID: id}
		data, _ := json.Marshal(evt)
		fmt.Fprintf(w, "data: %s\n\n", data)
		flusher.Flush()
		return
	}

	ch := h.scanMgr.SSE().Subscribe(id)
	defer h.scanMgr.SSE().Unsubscribe(id, ch)

	ctx := r.Context()
	for {
		select {
		case <-ctx.Done():
			return
		case evt, ok := <-ch:
			if !ok {
				return
			}
			data, _ := json.Marshal(evt)
			fmt.Fprintf(w, "data: %s\n\n", data)
			flusher.Flush()

			if evt.Type == "complete" || evt.Type == "error" || evt.Type == "cancelled" {
				return
			}
		}
	}
}
