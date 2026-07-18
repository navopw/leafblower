# Leafblower

> A leaf blower for your filesystem. Find the big stuff, blow it away.

A fast, native disk space visualizer and cleaner for macOS. Scan any directory, explore it as an interactive treemap, and move what you don’t need to Trash.

<img width="1810" height="1162" alt="Leafblower screenshot" src="https://github.com/user-attachments/assets/aa34ab28-d2b4-49f6-836c-90e37d6f4236" />

## Features

- **Scan** any path (`~`, `/`, a project folder) into a full size map
- **Explore** a zoomable squarified treemap (larger tiles = more disk)
- **Select** files and folders; sidebar shows relative paths and allocated size
- **Trash** with confirmation and per-item success/failure reporting
- **Live progress** in the status bar while scanning

## Quickstart

```bash
./build.sh              # release build → Leafblower.app
./build-and-start.sh    # build and open
```

Open the app, enter a path (or Browse), click **Scan**.

Requirements: macOS 14+, Swift 6 toolchain. No third-party dependencies.

## Docs

| Page | What it covers |
|------|----------------|
| [Usage](docs/usage.md) | Scanning, navigation, selection, shortcuts |
| [Architecture](docs/architecture.md) | App layout, scan pipeline, treemap |
| [Safety](docs/safety.md) | What can and cannot be moved to Trash |
| [Development](docs/development.md) | Build, test, project layout |

## Contributing

Pull requests welcome. Open an issue first for major changes.

## Disclaimer

Leafblower is **experimental software** provided **as-is, with no warranty**. Items go to Trash, but can become unrecoverable after Trash is emptied or due to filesystem behavior outside Leafblower’s control. You are solely responsible for any data loss. Verify selections and keep backups.

## License

MIT — see [LICENSE](LICENSE)
