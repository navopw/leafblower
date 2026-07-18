# Safety

Leafblower only moves items to the macOS Trash. There is no permanent-delete path.

## Rules

- **Scan-bound** — only nodes from the current completed scan can be removed; arbitrary paths cannot
- **Fresh selection** — every new scan clears selection so IDs never carry across scans
- **Re-validated at action time** — path containment, symlink resolution, and filesystem identity are checked again before Trash
- **Incomplete or changed items** — refused until you rescan
- **Scan root** — cannot be moved
- **Home directory** — cannot be moved as a whole
- **Home Trash** (`~/.Trash`) — already-trashed items are left alone
- **Critical system paths** — blocked (e.g. `/`, `/System`, `/Library`, `/Applications`, `/usr`, …)
- **Mounted volume roots** — cannot be moved as ordinary folders
- **v1 home restriction** — removal is limited to paths inside your home directory
- **Trash API only** — `FileManager.trashItem`; if Trash fails, the item is reported failed, not force-deleted

## What this does not guarantee

- Emptying Trash (or some filesystem edge cases) can make recovery impossible
- Permissions, locked files, or other processes can still cause failures
- Always read the selection list before confirming

See also the [disclaimer in the README](../README.md#disclaimer).
