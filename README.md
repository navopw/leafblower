# Leafblower

> A leaf blower for your filesystem. Find the big stuff, blow it away.

A fast, native disk space visualizer and cleaner for macOS. Scan any directory, explore your filesystem as an interactive treemap, and delete what you don't need — all in a native SwiftUI application.

## What it does

- **Scans** any path (`~`, `/`, a project folder) and builds a complete size map
- **Visualizes** your filesystem as a zoomable treemap — larger tiles = more disk space
- **Selects** files and folders with click or multi-select, with a running total of bytes to reclaim
- **Deletes** selected items after a confirmation step, with per-item success/failure reporting
- **Streams** scan progress in real time

## Quickstart

```bash
# Build the native app
./build-app.sh

# Run
open Leafblower.app
```

Open the app, enter a path, and click **Scan**.

### Options
- The app is unsandboxed to allow scanning any filesystem path.

## How to use it

1. Enter a path in the top bar (e.g. `~/Downloads`) and click **Scan**
2. Watch the treemap fill in when the scan completes
3. Click tiles to select them — selections add up and persist as you navigate
4. Double-click (or Shift+click) a folder to drill in; click a folder's header to select the whole folder
5. The sidebar lists your selection (relative paths) and the total size to reclaim
6. Click **Delete** and confirm

Each folder shows its immediate contents one level deep, the same way the
visualization is served in the reference implementation.

**Shortcuts**

| Shortcut | Action |
|----------|--------|
| Click | Toggle select / deselect |
| Double-click or Shift+click | Drill into a folder |
| Click a folder header | Select the whole folder |
| Click breadcrumb | Jump back to that level |
| `Esc` | Clear selection |
| `Enter` (in path field) | Start scan |
| `⌘R` | Rescan current path |

## Architecture

Leafblower is a single native macOS application written in Swift 6 and SwiftUI.

```
SwiftUI (Swift 6 native UI)
  ├── TreemapView       — squarified treemap drawn to a cached CoreGraphics
  │                       bitmap, with a Canvas overlay for labels & selection
  ├── PathBarView       — native path input + NSOpenPanel browse
  └── SelectionPanel    — sidebar with relative paths and live totals
ScanManager             — @Observable @MainActor state machine
  ├── FileWalker        — TaskGroup concurrent traversal
  │   └── Darwin.stat   — block-based size & (device, inode) deduplication
  └── DeleteService     — scan-bound, home-directory-restricted deletion
      └── SafetyValidator — scan-root & critical-path guards
```

**Stack:** Swift 6 · SwiftUI · macOS 14+ (no third-party dependencies)

## Safety

Leafblower is deliberately cautious about deletion:

- Deletion is bound to a scan job — no arbitrary path deletion
- Paths are re-validated against the scan root at delete time
- The scan root itself cannot be deleted
- In v1, deletion is restricted to paths inside your home directory
- Hardcoded blocklist of critical system paths

## Development

```bash
# Build
swift build

# Run tests
swift test

# Run locally
swift run
```

## Contributing

Pull requests welcome. Open an issue first for major changes.

## Disclaimer

Leafblower is **experimental software** provided **as-is, with no warranty of any kind**. Deletion of files is permanent and irreversible. Each user is solely responsible for any data loss that occurs through use of this tool. The authors accept no liability for accidentally deleted files, corrupted data, or any other damages arising from its use. Always verify your selection before confirming a deletion, and keep backups of anything you can't afford to lose.

## License

MIT — see [LICENSE](LICENSE)
