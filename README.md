# Leafblower

> A leaf blower for your filesystem. Find the big stuff, blow it away.

A fast, native disk space visualizer and cleaner for macOS. Scan any directory, explore your filesystem as an interactive treemap, and move what you don't need to Trash — all in a native SwiftUI application.

<img width="1810" height="1162" alt="CleanShot 2026-07-18 at 15 45 02" src="https://github.com/user-attachments/assets/aa34ab28-d2b4-49f6-836c-90e37d6f4236" />

## What it does

- **Scans** any path (`~`, `/`, a project folder) and builds a complete size map
- **Visualizes** your filesystem as a zoomable treemap — larger tiles = more disk space
- **Selects** files and folders with click or multi-select, with a running total of allocated size
- **Moves to Trash** after a confirmation step, with per-item success/failure reporting
- **Streams** scan progress in real time

## Quickstart

```bash
# Build the native app
./build.sh

# Build and open
./build-and-start.sh
```

Open the app, enter a path, and click **Scan**.

### Options
- The app is unsandboxed to allow scanning any filesystem path.
- Hidden items are included so folder sizes and deletion checks are complete.

## How to use it

1. Enter a path in the top bar (e.g. `~/Downloads`) and click **Scan**
2. Watch the treemap fill in when the scan completes
3. Click tiles to select them — selections add up and persist as you navigate
4. Double-click (or Shift+click) a folder to drill in; click a folder's header to select the whole folder
5. The sidebar lists your selection (relative paths) and its total allocated size
6. Click **Move to Trash** and confirm

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
  │   └── Darwin.lstat  — identity snapshots, block size & hard-link accounting
  └── DeleteService     — scan-bound, home-directory-restricted Trash workflow
      └── SafetyValidator — scan-root & critical-path guards
```

**Stack:** Swift 6 · SwiftUI · macOS 14+ (no third-party dependencies)

## Safety

Leafblower is deliberately cautious about removing items:

- Removal is bound to the current completed scan — no arbitrary path deletion
- Selection is cleared for every new scan, so node IDs cannot carry across scans
- Paths, symlink boundaries, and filesystem identities are re-validated at action time
- Changed items and folders that were not fully scanned are refused until rescanned
- The scan root itself cannot be deleted
- Your home directory, its Trash folder, and critical system paths are protected
- Mounted volume roots cannot be moved as ordinary folders
- In v1, removal is restricted to paths inside your home directory
- Items are moved with the native macOS Trash API; there is no permanent-delete fallback

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

Leafblower is **experimental software** provided **as-is, with no warranty of any kind**. Items are moved to Trash, but they can become unrecoverable after Trash is emptied or because of filesystem behavior outside Leafblower's control. Each user is solely responsible for any data loss that occurs through use of this tool. Always verify your selection before confirming, and keep backups of anything you cannot afford to lose.

## License

MIT — see [LICENSE](LICENSE)
