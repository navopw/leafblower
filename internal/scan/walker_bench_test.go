package scan

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/navopw/leafblower/internal/model"
)

func BenchmarkWalkerHome(b *testing.B) {
	home, err := os.UserHomeDir()
	if err != nil {
		b.Fatal(err)
	}

	for i := 0; i < b.N; i++ {
		w := NewWalker(false, nil)
		root, index, warnings, err := w.Walk(context.Background(), "bench", home)
		if err != nil {
			b.Fatal(err)
		}
		_ = root
		_ = index
		_ = warnings
	}
}

func TestWalkerHomeTime(t *testing.T) {
	home, err := os.UserHomeDir()
	if err != nil {
		t.Fatal(err)
	}

	w := NewWalker(false, func(evt model.ProgressEvent) {})
	start := time.Now()
	root, _, _, err := w.Walk(context.Background(), "bench", home)
	elapsed := time.Since(start)
	if err != nil {
		t.Fatal(err)
	}

	dirs := w.dirCount.Load()
	files := w.fileCount.Load()
	bytes := w.byteCount.Load()
	_ = root

	t.Logf("=== WALKER BENCHMARK ===")
	t.Logf("Time: %v", elapsed)
	t.Logf("Dirs: %d, Files: %d, Bytes: %d", dirs, files, bytes)
	t.Logf("========================")
}
