# Changelog

All notable changes are documented here. The project follows [Semantic Versioning](https://semver.org/).

## [1.1.0] — 2026-10-07

### Added
- Image, video and PDF **thumbnails** in the Medium / Large / Extra large icon views (cached, aspect-ratio preserving)
- **`explorermac <dir>`** terminal command: opens a folder (or reveals a file) in a new Explorer window; fixes path letter-case; installable from the app menu; `explorermac://` URL scheme and `open -a Explorer <folder>` support
- 5 new tests (24 total)

### Fixed
- Cold-starting the app with a folder no longer leaves an extra home-folder window

## [1.0.0] — 2026-10-07

First public release.

### Added
- Windows 11 File Explorer look and feel: navigation pane, address bar with breadcrumbs, command bar, Details list, status bar, light and dark themes
- Navigation: Back / Forward / Up, editable address bar (⌘L), recursive search, folder tree for disk and volumes, pinnable Quick access
- Views: Details, List, Small / Medium / Large / Extra large icons; Group by Name / Date modified / Type / Size; sortable, resizable columns
- Details pane with thumbnail and file info; Properties dialog (size, size on disk, contents, dates, Read-only / Hidden attributes)
- Windows 11-style right-click menus for files, folders, multi-selection and empty space, plus "Show more options"
- File operations: real Cut & Paste, Copy, Paste shortcut, inline Rename, Trash, Delete permanently, drag & drop (move/copy by volume, ⌥ flips), multi-level Undo
- Compress to ZIP, Extract All (zip, tar, gz, bz2, xz, 7z, rar, iso), Create shortcut (macOS alias), Open with, Share, Send to, Copy to / Move to folder
- New menu: Folder, Shortcut, Text, Rich text, Markdown, HTML and ZIP documents
- Image actions: set as desktop background, rotate left / right
- Native macOS tabs and windows, live folder refresh, Quick Look
- Keyboard: F2 rename, ⌘X/⌘C/⌘V, arrow-key and type-to-select navigation, shift/⌘ multi-select
- Command-line options for demos: `--path --view --group --details-pane --hidden --select --light --dark`
- 19 unit tests covering navigation, file operations, undo, archives, grouping, selection and properties

### Known limitations
- No Home / Gallery pages, drag-box selection, or Tiles or Content views
- Right-clicking an item doesn't highlight it first (the menu still targets it)
- App is ad-hoc signed, not notarized (see README for first-launch instructions)
