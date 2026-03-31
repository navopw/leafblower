package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type browseResponse struct {
	Path    string   `json:"path"`
	Parent  string   `json:"parent"`
	Entries []string `json:"entries"`
}

func (h *handlers) browse(w http.ResponseWriter, r *http.Request) {
	home, err := os.UserHomeDir()
	if err != nil {
		http.Error(w, "cannot determine home directory", http.StatusInternalServerError)
		return
	}
	home = filepath.Clean(home)

	path := r.URL.Query().Get("path")
	if path == "" || path == "~" {
		path = home
	} else if strings.HasPrefix(path, "~/") {
		path = filepath.Join(home, path[2:])
	}
	path = filepath.Clean(path)

	// Restrict browsing to home directory to prevent arbitrary filesystem enumeration.
	if err := requireUnderHome(path, home); err != nil {
		http.Error(w, err.Error(), http.StatusForbidden)
		return
	}

	entries, err := os.ReadDir(path)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	var dirs []string
	for _, e := range entries {
		if e.IsDir() && !strings.HasPrefix(e.Name(), ".") {
			dirs = append(dirs, e.Name())
		}
	}
	sort.Strings(dirs)

	// Only expose parent if it's still within the home directory.
	parent := filepath.Dir(path)
	if parent == path || requireUnderHome(parent, home) != nil {
		parent = ""
	}

	resp := browseResponse{
		Path:    path,
		Parent:  parent,
		Entries: dirs,
	}
	if resp.Entries == nil {
		resp.Entries = []string{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// requireUnderHome returns an error if path is not the home directory or a
// subdirectory of it.
func requireUnderHome(path, home string) error {
	if path != home && !strings.HasPrefix(path, home+string(filepath.Separator)) {
		return fmt.Errorf("path is outside home directory")
	}
	return nil
}
