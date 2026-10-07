# Contributing

Thanks for helping make a better file manager for the Mac! This is a small, friendly project.

## Setup

Requires macOS 15+ and Xcode (Swift 6 toolchain).

```bash
git clone https://github.com/preslav-panayotov/explorer-macos.git
cd explorer-macos
swift build            # compile
swift test             # run the tests
./build_app.sh         # build build/Explorer.app
open build/Explorer.app
```

Handy launch options for trying a specific state: `open -n build/Explorer.app --args --path ~/Documents --view "Large icons" --dark` (see [docs/FEATURES.md](docs/FEATURES.md#command-line-options)).

## Where things live

| Area | File |
|---|---|
| State, navigation, selection, undo | `Sources/Explorer/ExplorerState.swift` |
| File operations, archives, shortcuts, network | `Sources/Explorer/FileActions.swift` |
| Copy/move engine with progress | `Sources/Explorer/TransferEngine.swift` |
| Right-click menus | `Sources/Explorer/ContextMenus.swift` |
| Lists, grids, drag-box, rename | `Sources/Explorer/ListViews.swift` |
| Window, sidebar, address bar, command bar | `Sources/Explorer/Views.swift` |

## Guidelines

- **Test file operations.** Anything that touches files should have a test in `Tests/ExplorerTests` (use the temp-directory helpers there).
- **Never lose data.** Prefer the Trash and Undo over permanent deletes; confirm anything irreversible.
- **Match Windows 11 behaviour** where it makes sense, and macOS conventions where Windows' don't apply (e.g. ⌘ instead of Ctrl).
- Keep the code in the surrounding style; no new dependencies without a good reason.
- Update `CHANGELOG.md` (under *Unreleased*) and `docs/FEATURES.md` for user-visible changes.

## Pull requests

1. Fork, branch, commit.
2. Make sure `swift test` passes — CI runs it on every push and PR.
3. Describe what changed and how you tested it.

## Releasing (maintainers)

See the *Releases and versioning* section of the [README](README.md).
