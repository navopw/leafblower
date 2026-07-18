# Development

## Prerequisites

- macOS 14+
- Swift 6 toolchain (`swift --version`)

## Commands

```bash
swift build          # debug build
swift test           # unit tests
swift run            # run executable (windowed app)

./build.sh           # release → Leafblower.app
./build-and-start.sh # release build and open the app
```

## Tests

| Suite | Focus |
|-------|--------|
| `FileWalkerTests` | traversal, sizes, hidden, hard links |
| `SafetyValidatorTests` | path guards |
| `DeleteServiceTests` | plan, perform, tree rebuild |
| `TreemapLayoutEngineTests` | layout |

## Notes

- SPM package: executable target `Leafblower`, test target `LeafblowerTests`
- `Leafblower.app` is a build artifact (gitignored); produced by `build.sh`
- App is intentionally unsandboxed so scans can target arbitrary paths
- Hidden files are always included from the UI (`includeHidden: true`)

## Project map

See [Architecture](architecture.md) for runtime structure and `Sources/` layout.
