# Architecture

Leafblower is a single native macOS app: Swift 6 + SwiftUI, macOS 14+, no third-party packages.

```
SwiftUI
  ├── PathBarView        path input, Browse (NSOpenPanel), Scan / Stop
  ├── BreadcrumbView     zoom path
  ├── TreemapView        cached CoreGraphics bitmap + Canvas overlay
  ├── SelectionPanel     selection list, totals, Trash action
  └── StatusBarView      progress, counts, warnings
ScanManager              @Observable @MainActor state
  ├── FileWalker         concurrent directory walk (TaskGroup)
  │   └── lstat          identity, allocated size, hard-link accounting
  └── DeleteService      scan-bound Trash workflow
      └── SafetyValidator  root, home, critical-path guards
```

## Scan pipeline

1. `ScanManager.startScan` clears selection, creates a `ScanJob`, runs `FileWalker` off the main actor
2. `FileWalker` walks with a work queue and several workers; progress events update the job
3. Each entry is identified with `lstat` (`FileIdentity`): device/inode, mode, link count, allocated size (`st_blocks`)
4. Hard links count size once per device+inode pair
5. Directory sizes roll up from children after the walk
6. Incomplete or changed directories are marked `isScanComplete = false` and may emit warnings

Only one scan is kept at a time.

## Treemap

- `TreemapLayoutEngine` — squarified layout, two levels deep (current children + one nested expansion), with a header strip on expanded folders
- `TreemapRenderer` — layout → off-main-thread bitmap
- `TreemapView` — shows the bitmap; Canvas draws labels and selection; `ClickCatcher` handles click / double-click / Shift+click

## Delete pipeline

1. Build a `DeletePlan` from selected node IDs on the completed scan
2. Preflight: safety rules, full scan completeness, mount points, identities
3. At action time: re-check scan root and every verification path still matches the scanned identity
4. Move with `FileManager.trashItem` only (no permanent-delete fallback)
5. Rebuild the in-memory tree without the deleted nodes

## Source layout

```
Sources/Leafblower/
  LeafblowerApp.swift
  Models/          Node, ScanJob, FileIdentity, results, events
  Services/        ScanManager, FileWalker, DeleteService, SafetyValidator,
                   TreemapLayoutEngine, TreemapRenderer
  Views/           UI
  Utils/           paths, formatting, open panel, click catcher
Tests/LeafblowerTests/
```

Build packaging: `build.sh` runs `swift build -c release` and assembles `Leafblower.app` with `Info.plist`.
