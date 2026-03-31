package delete

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/navopw/leafblower/internal/model"
)

func newTestJob(rootPath string, nodes ...*model.Node) *model.ScanJob {
	index := make(map[string]*model.Node)
	for _, n := range nodes {
		index[n.ID] = n
	}
	return &model.ScanJob{
		ID:        "test_scan",
		RootPath:  rootPath,
		Status:    model.StatusComplete,
		NodeIndex: index,
	}
}

// homeTempDir creates a temp directory inside the user's home dir and registers cleanup.
// Tests that exercise real deletion must live under home due to the v1 home restriction.
func homeTempDir(t *testing.T) string {
	t.Helper()
	home, err := os.UserHomeDir()
	if err != nil {
		t.Skip("cannot determine home dir:", err)
	}
	dir, err := os.MkdirTemp(home, "leafblower-test-*")
	if err != nil {
		t.Skip("cannot create temp dir in home:", err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	return dir
}

// buildDemoTree creates this structure on disk and returns a matching model tree:
//
//	root/
//	  subdir/
//	    file_a.txt  (5 bytes)
//	    file_b.txt  (8 bytes)
//	  top_file.txt  (3 bytes)
//
// Node IDs: "root", "subdir", "file_a", "file_b", "top_file"
// Sizes propagate upward so root.SizeBytes == 16.
func buildDemoTree(t *testing.T, root string) *model.ScanJob {
	t.Helper()

	subdir := filepath.Join(root, "subdir")
	if err := os.Mkdir(subdir, 0755); err != nil {
		t.Fatal(err)
	}
	fileA := filepath.Join(subdir, "file_a.txt")
	fileB := filepath.Join(subdir, "file_b.txt")
	topFile := filepath.Join(root, "top_file.txt")

	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	must(os.WriteFile(fileA, []byte("hello"), 0644))   // 5 bytes
	must(os.WriteFile(fileB, []byte("hi there"), 0644)) // 8 bytes
	must(os.WriteFile(topFile, []byte("hey"), 0644))    // 3 bytes

	nodeRoot := &model.Node{ID: "root", Path: root, IsDir: true, SizeBytes: 16, HasChildren: true, ChildCount: 2}
	nodeSubdir := &model.Node{ID: "subdir", Path: subdir, IsDir: true, SizeBytes: 13, ParentID: "root", HasChildren: true, ChildCount: 2}
	nodeFileA := &model.Node{ID: "file_a", Path: fileA, IsDir: false, SizeBytes: 5, ParentID: "subdir"}
	nodeFileB := &model.Node{ID: "file_b", Path: fileB, IsDir: false, SizeBytes: 8, ParentID: "subdir"}
	nodeTopFile := &model.Node{ID: "top_file", Path: topFile, IsDir: false, SizeBytes: 3, ParentID: "root"}

	nodeRoot.Children = []*model.Node{nodeSubdir, nodeTopFile}
	nodeSubdir.Children = []*model.Node{nodeFileA, nodeFileB}

	return newTestJob(root, nodeRoot, nodeSubdir, nodeFileA, nodeFileB, nodeTopFile)
}

func TestRejectsScanRoot(t *testing.T) {
	svc, _ := NewService()
	root := t.TempDir()

	job := newTestJob(root, &model.Node{ID: "root", Path: root, IsDir: true})
	resp := svc.Execute(job, []string{"root"})

	if len(resp.Failed) != 1 {
		t.Fatalf("expected 1 failure, got %d", len(resp.Failed))
	}
	if resp.Failed[0].Error != "cannot delete scan root" {
		t.Errorf("expected 'cannot delete scan root', got %q", resp.Failed[0].Error)
	}
}

func TestRejectsNonexistentNode(t *testing.T) {
	svc, _ := NewService()
	job := newTestJob(t.TempDir())
	resp := svc.Execute(job, []string{"fake_node"})

	if len(resp.Failed) != 1 {
		t.Fatalf("expected 1 failure, got %d", len(resp.Failed))
	}
	if resp.Failed[0].Error != "node not found in scan" {
		t.Errorf("expected 'node not found in scan', got %q", resp.Failed[0].Error)
	}
}

func TestDeletesFileSuccessfully(t *testing.T) {
	svc, _ := NewService()
	home, _ := os.UserHomeDir()

	// Create a temp dir inside home
	dir, err := os.MkdirTemp(home, "leafblower-test-*")
	if err != nil {
		t.Skip("cannot create temp dir in home:", err)
	}
	defer os.RemoveAll(dir)

	// Create a test file
	testFile := filepath.Join(dir, "test.txt")
	if err := os.WriteFile(testFile, []byte("test"), 0644); err != nil {
		t.Fatal(err)
	}

	job := newTestJob(dir,
		&model.Node{ID: "root", Path: dir, IsDir: true},
		&model.Node{ID: "file1", Path: testFile, IsDir: false},
	)

	resp := svc.Execute(job, []string{"file1"})

	if len(resp.Deleted) != 1 {
		t.Fatalf("expected 1 deleted, got %d deleted, %d failed", len(resp.Deleted), len(resp.Failed))
	}
	if _, err := os.Stat(testFile); !os.IsNotExist(err) {
		t.Error("file should have been deleted")
	}
}

func TestNormalizesNestedSelections(t *testing.T) {
	parent := &model.Node{ID: "dir", Path: "/Users/test/parent", IsDir: true}
	child := &model.Node{ID: "file", Path: "/Users/test/parent/child.txt", IsDir: false}

	result := normalizeSelection([]*model.Node{parent, child})
	if len(result) != 1 {
		t.Fatalf("expected 1 node after normalization, got %d", len(result))
	}
	if result[0].ID != "dir" {
		t.Errorf("expected parent to survive normalization, got %s", result[0].ID)
	}
}

func TestRejectsPathOutsideHome(t *testing.T) {
	svc, _ := NewService()
	job := newTestJob("/tmp",
		&model.Node{ID: "root", Path: "/tmp", IsDir: true},
		&model.Node{ID: "file1", Path: "/tmp/somefile", IsDir: false},
	)

	resp := svc.Execute(job, []string{"file1"})
	if len(resp.Failed) != 1 {
		t.Fatalf("expected 1 failure, got %d", len(resp.Failed))
	}
	if resp.Failed[0].Error != "deletion restricted to home directory in v1" {
		t.Errorf("unexpected error: %s", resp.Failed[0].Error)
	}
}

// --- Demo folder / filesystem integration tests ---

func TestDeletesDirectoryRecursively(t *testing.T) {
	svc, _ := NewService()
	root := homeTempDir(t)
	job := buildDemoTree(t, root)

	subdir := filepath.Join(root, "subdir")
	resp := svc.Execute(job, []string{"subdir"})

	if len(resp.Deleted) != 1 || len(resp.Failed) != 0 {
		t.Fatalf("expected 1 deleted 0 failed, got %d deleted %d failed", len(resp.Deleted), len(resp.Failed))
	}
	if _, err := os.Stat(subdir); !os.IsNotExist(err) {
		t.Error("subdir should have been deleted from disk")
	}
	// subdir and its children must be gone from the index
	for _, id := range []string{"subdir", "file_a", "file_b"} {
		if _, ok := job.NodeIndex[id]; ok {
			t.Errorf("node %q should have been removed from index", id)
		}
	}
	// root and top_file must still be present
	if _, ok := job.NodeIndex["root"]; !ok {
		t.Error("root node should still be in index")
	}
}

func TestDeletesMultipleFiles(t *testing.T) {
	svc, _ := NewService()
	root := homeTempDir(t)
	job := buildDemoTree(t, root)

	fileA := filepath.Join(root, "subdir", "file_a.txt")
	topFile := filepath.Join(root, "top_file.txt")

	resp := svc.Execute(job, []string{"file_a", "top_file"})

	if len(resp.Deleted) != 2 || len(resp.Failed) != 0 {
		t.Fatalf("expected 2 deleted 0 failed, got %d deleted %d failed", len(resp.Deleted), len(resp.Failed))
	}
	if _, err := os.Stat(fileA); !os.IsNotExist(err) {
		t.Error("file_a.txt should have been deleted")
	}
	if _, err := os.Stat(topFile); !os.IsNotExist(err) {
		t.Error("top_file.txt should have been deleted")
	}
	// file_b and subdir must remain
	if _, err := os.Stat(filepath.Join(root, "subdir", "file_b.txt")); err != nil {
		t.Error("file_b.txt should still exist")
	}
}

func TestParentChildBothSelectedOnlyDeletesParentOnce(t *testing.T) {
	svc, _ := NewService()
	root := homeTempDir(t)
	job := buildDemoTree(t, root)

	subdir := filepath.Join(root, "subdir")
	// Select both subdir and one of its children — normalization should reduce to just subdir
	resp := svc.Execute(job, []string{"subdir", "file_a"})

	if len(resp.Deleted) != 1 || len(resp.Failed) != 0 {
		t.Fatalf("expected 1 deleted 0 failed, got %d deleted %d failed", len(resp.Deleted), len(resp.Failed))
	}
	if resp.Deleted[0].NodeID != "subdir" {
		t.Errorf("expected subdir to be deleted, got %s", resp.Deleted[0].NodeID)
	}
	if _, err := os.Stat(subdir); !os.IsNotExist(err) {
		t.Error("subdir should have been deleted from disk")
	}
}

func TestPruneNodePropagatesSizeToRoot(t *testing.T) {
	svc, _ := NewService()
	root := homeTempDir(t)
	job := buildDemoTree(t, root)

	// Delete file_a (5 bytes). Root should go from 16 → 11, subdir from 13 → 8.
	resp := svc.Execute(job, []string{"file_a"})
	if len(resp.Deleted) != 1 {
		t.Fatalf("expected 1 deleted, got %d", len(resp.Deleted))
	}

	rootNode := job.NodeIndex["root"]
	if rootNode.SizeBytes != 11 {
		t.Errorf("root size: expected 11, got %d", rootNode.SizeBytes)
	}
	subdirNode := job.NodeIndex["subdir"]
	if subdirNode.SizeBytes != 8 {
		t.Errorf("subdir size: expected 8, got %d", subdirNode.SizeBytes)
	}
}

func TestPruneNodeRemovesChildFromParentSlice(t *testing.T) {
	svc, _ := NewService()
	root := homeTempDir(t)
	job := buildDemoTree(t, root)

	resp := svc.Execute(job, []string{"top_file"})
	if len(resp.Deleted) != 1 {
		t.Fatalf("expected 1 deleted, got %d", len(resp.Deleted))
	}

	rootNode := job.NodeIndex["root"]
	if rootNode.ChildCount != 1 {
		t.Errorf("root ChildCount: expected 1, got %d", rootNode.ChildCount)
	}
	for _, child := range rootNode.Children {
		if child.ID == "top_file" {
			t.Error("top_file should have been removed from root.Children")
		}
	}
}

func TestRejectsIncompleteJob(t *testing.T) {
	svc, _ := NewService()
	root := homeTempDir(t)
	job := buildDemoTree(t, root)
	job.Status = model.StatusRunning

	resp := svc.Execute(job, []string{"file_a", "file_b"})
	if len(resp.Failed) != 2 {
		t.Fatalf("expected 2 failures, got %d", len(resp.Failed))
	}
	for _, f := range resp.Failed {
		if f.Error != "scan is not complete" {
			t.Errorf("unexpected error: %s", f.Error)
		}
	}
}

func TestRejectsCriticalSystemPaths(t *testing.T) {
	svc, _ := NewService()
	criticals := []string{"/bin/sh", "/etc/passwd", "/usr/bin/env", "/System/Library"}
	for _, path := range criticals {
		err := svc.validatePath(path, "/")
		if err == nil {
			t.Errorf("expected validatePath to reject %q, but it was allowed", path)
		}
	}
}

func TestRejectsPathOutsideScanRoot(t *testing.T) {
	svc, _ := NewService()
	home, _ := os.UserHomeDir()

	// Both dirs are inside home, but target is not under scanRoot
	scanRoot := filepath.Join(home, "leafblower-scanroot-test")
	otherDir := filepath.Join(home, "leafblower-other-test")

	err := svc.validatePath(otherDir, scanRoot)
	if err == nil {
		t.Error("expected rejection for path outside scan root")
	}
}
