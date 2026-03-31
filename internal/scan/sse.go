package scan

import (
	"sync"

	"github.com/navopw/leafblower/internal/model"
)

// SSEHub manages SSE event subscriptions per scan.
type SSEHub struct {
	mu      sync.RWMutex
	clients map[string][]chan model.ProgressEvent
}

// NewSSEHub creates an SSEHub.
func NewSSEHub() *SSEHub {
	return &SSEHub{
		clients: make(map[string][]chan model.ProgressEvent),
	}
}

// Subscribe returns a channel that receives events for the given scan.
func (h *SSEHub) Subscribe(scanID string) chan model.ProgressEvent {
	ch := make(chan model.ProgressEvent, 64)
	h.mu.Lock()
	h.clients[scanID] = append(h.clients[scanID], ch)
	h.mu.Unlock()
	return ch
}

// Unsubscribe removes a client channel.
func (h *SSEHub) Unsubscribe(scanID string, ch chan model.ProgressEvent) {
	h.mu.Lock()
	defer h.mu.Unlock()
	clients := h.clients[scanID]
	for i, c := range clients {
		if c == ch {
			h.clients[scanID] = append(clients[:i], clients[i+1:]...)
			close(ch)
			return
		}
	}
}

// Remove closes and deletes all subscriber channels for a scan.
func (h *SSEHub) Remove(scanID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, ch := range h.clients[scanID] {
		close(ch)
	}
	delete(h.clients, scanID)
}

// Send broadcasts an event to all subscribers for a scan.
func (h *SSEHub) Send(scanID string, evt model.ProgressEvent) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, ch := range h.clients[scanID] {
		select {
		case ch <- evt:
		default:
			// Drop if client is slow
		}
	}
}
