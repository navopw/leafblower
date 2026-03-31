package api

import (
	"net"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/navopw/leafblower/internal/delete"
	"github.com/navopw/leafblower/internal/scan"
)

// NewRouter creates the HTTP router with all API endpoints.
func NewRouter(scanMgr *scan.Manager, delSvc *delete.Service, staticFS http.FileSystem) http.Handler {
	r := chi.NewRouter()

	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(localhostOnly)

	h := &handlers{
		scanMgr: scanMgr,
		delSvc:  delSvc,
	}

	r.Route("/api", func(r chi.Router) {
		r.Post("/scans", h.startScan)
		r.Get("/scans/{id}", h.getScan)
		r.Delete("/scans/{id}", h.cancelScan)
		r.Get("/scans/{id}/tree", h.getTree)
		r.Get("/scans/{id}/events", h.scanEvents)
		r.Post("/deletions", h.deletePaths)
		r.Get("/browse", h.browse)
	})

	// Serve frontend with SPA fallback
	r.Get("/*", spaHandler(staticFS))

	return r
}

func localhostOnly(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host, _, err := net.SplitHostPort(r.RemoteAddr)
		if err != nil {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		ip := net.ParseIP(host)
		if ip == nil || !ip.IsLoopback() {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func spaHandler(staticFS http.FileSystem) http.HandlerFunc {
	fileServer := http.FileServer(staticFS)
	return func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		// Try to open the file
		f, err := staticFS.Open(path)
		if err != nil {
			// If file not found and it's not a file with extension, serve index.html
			if !strings.Contains(path, ".") {
				r.URL.Path = "/"
			}
		} else {
			f.Close()
		}
		fileServer.ServeHTTP(w, r)
	}
}

type handlers struct {
	scanMgr *scan.Manager
	delSvc  *delete.Service
}
