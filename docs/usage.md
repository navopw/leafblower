# Usage

## Scan

1. Enter a path in the top bar (e.g. `~/Downloads`) or click **Browse**
2. Click **Scan** (or press Enter in the path field)
3. Watch the status bar for progress; the treemap appears when the scan finishes
4. Use **Stop** to cancel a running scan; **⌘R** to rescan the same path

Hidden items are always included so folder sizes and delete checks stay complete.

The app is not sandboxed, so it can read paths outside the app container.

## Navigate the treemap

Each view shows the current folder’s children, and expands each subfolder one level further when there is room. Drill in to go deeper.

| Action | Result |
|--------|--------|
| Click a tile | Toggle select / deselect |
| Double-click or Shift+click | Drill into a folder |
| Click a folder header | Select that whole folder |
| Click a breadcrumb | Jump back to that level |

Selections stay selected while you drill in and out. Selecting a folder replaces any selected children (and the reverse), so the selection stays non-overlapping.

## Selection and Trash

The sidebar lists selected items (paths relative to the scan root) and a running total of **allocated** size.

1. Select one or more tiles
2. Click **Move to Trash**
3. Confirm in the dialog

Results are reported per item. Failed items stay selected when possible.

Folders that were not fully scanned (or changed during the scan) must be rescanned before they can be moved. Mounted volume roots cannot be moved.

See [Safety](safety.md) for the full guard list.

## Shortcuts

| Shortcut | Action |
|----------|--------|
| Click | Toggle select / deselect |
| Double-click or Shift+click | Drill into a folder |
| Click folder header | Select the whole folder |
| Click breadcrumb | Jump to that level |
| `Esc` | Clear selection |
| `Enter` (path field) | Start scan |
| `⌘R` | Rescan current path |

## Status bar

While scanning: progress, current path, directory/file counts, bytes seen, **Stop**.

When done: total size, counts, and a warnings button if anything was unreadable or changed during the scan.
