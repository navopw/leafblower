# Leafblower

> A leaf blower for your filesystem. Find the big stuff, blow it away.

A fast, local disk space visualizer and cleaner for macOS. Scan any directory, explore your filesystem as an interactive treemap, and delete what you don't need — all from a browser tab that never leaves your machine.

<img width="1707" height="1289" alt="image" src="https://github.com/user-attachments/assets/65ae0b03-af59-4442-ae96-6596ddaf0ca6" />

---

## What it does

- **Scans** any path (`~`, `/`, a project folder) and builds a complete size map
- **Visualizes** your filesystem as a zoomable treemap — larger tiles = more disk space
- **Selects** files and folders with click or multi-select, with a running total of bytes to reclaim
- **Deletes** selected items after a confirmation step, with per-item success/failure reporting
- **Streams** scan progress in real time via SSE so you're never staring at a spinner

---

## Quickstart

```bash
# Build and run (serves on http://127.0.0.1:8000)
./start.sh

# Or build manually
cd web && npm run build && cd ..
go build -o leafblower ./cmd/leafblower
./leafblower
```

Open [http://127.0.0.1:8000](http://127.0.0.1:8000) in your browser.

### Options

```
-port   Port to listen on (default: 8000)
```

---

## How to use it

1. Enter a path in the top bar (e.g. `~/Downloads`) and click **Scan**
2. Watch the treemap fill in as the scan progresses
3. Click a tile to select it; Shift+click a folder to zoom in
4. The sidebar shows your selection and total size
5. Click **Delete** and confirm — done

**Shortcuts**

| Shortcut | Action |
|-----|--------|
| Click | Toggle select/deselect |
| Shift+click (folder) | Drill down into folder |
| Click breadcrumb | Navigate back up to that level |
| `Esc` | Clear selection |
| `Backspace` | Navigate up one level |
| `Enter` (in path input) | Start scan |

---

## Architecture

Leafblower is a single Go binary with an embedded React frontend. Nothing is installed globally and nothing persists between sessions.

```
Browser (React + d3-hierarchy)
  ↕ HTTP + SSE
Go server (chi)
  ├── scan manager   — async scan jobs, SSE progress stream
  ├── walker         — concurrent filesystem traversal
  └── delete service — scan-bound, home-directory-restricted deletion
```

**Stack:** Go · chi · React 19 · TypeScript · Vite · Tailwind CSS v4 · shadcn/ui · d3-hierarchy

---

## Safety

Leafblower is deliberately cautious about deletion:

- Binds to `127.0.0.1` only — not reachable from other machines
- Deletion is bound to a scan job — no arbitrary path deletion via the API
- Paths are re-validated against the scan root at delete time
- The scan root itself cannot be deleted
- In v1, deletion is restricted to paths inside your home directory

---

## Development

```bash
# Run backend with live frontend dev server
cd web && npm run dev &   # Vite on :5173, proxies API to :8000
go run ./cmd/leafblower   # Go server on :8000
```

```bash
# Run tests
go test ./...
```

```bash
# Restart the running instance
./restart.sh
```

---

## Contributing

Pull requests welcome. Open an issue first for major changes.

---

## Disclaimer

Leafblower is **experimental software** provided **as-is, with no warranty of any kind**. Deletion of files is permanent and irreversible. Each user is solely responsible for any data loss that occurs through use of this tool. The authors accept no liability for accidentally deleted files, corrupted data, or any other damages arising from its use. Always verify your selection before confirming a deletion, and keep backups of anything you can't afford to lose.

---

## License

MIT — see [LICENSE](LICENSE)
