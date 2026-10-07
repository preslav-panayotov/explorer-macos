# Explorer 1.0.0 — Full feature reference

Everything the app can do, organised the way Windows File Explorer organises it. Keyboard shortcuts use macOS notation (⌘ Command, ⌥ Option, ⇧ Shift).

- [Window layout](#window-layout)
- [Navigation](#navigation)
- [Views, sorting and grouping](#views-sorting-and-grouping)
- [Selecting items](#selecting-items)
- [Right-click menus](#right-click-menus)
- [File operations](#file-operations)
- [Archives and shortcuts](#archives-and-shortcuts)
- [Properties and the Details pane](#properties-and-the-details-pane)
- [Search](#search)
- [Windows and tabs](#windows-and-tabs)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Command-line options](#command-line-options)
- [Behaviour notes](#behaviour-notes)

## Window layout

| Area | What it does |
|---|---|
| **Navigation pane** (left) | *Home*, *Quick access* (Desktop, Downloads, Documents, Pictures, Music, Videos + folders you pin), and *This Mac* — an expandable folder tree for your user folder, the system disk and mounted volumes. Drop files onto any entry to move/copy them there. |
| **Toolbar** | Back, Forward, Up, the address bar and search. |
| **Command bar** | New ▾, Cut, Copy, Paste, Rename, Share, Delete, Sort ▾, View ▾, “…” menu, Details-pane toggle. Buttons enable/disable according to the selection. “Extract all” appears when one archive is selected. |
| **File area** | Details list or an icon/list grid, with optional group headers. |
| **Details pane** (right, optional) | Thumbnail/preview and metadata of the selected item. |
| **Status bar** | Item count, selection count and total size, plus quick Details / Large-icons toggles. |

Light and dark appearance follow macOS, using the Windows 11 palette (yellow folders, light-blue selection, blue accent).

## Navigation

- **Back / Forward / Up** — toolbar buttons, ⌘[ ⌘] ⌘↑. After *Up*, the folder you came from is selected.
- **Address bar** — click a breadcrumb to jump there; click the empty area or press ⌘L to type a path (`~` is expanded). Enter to go, Esc to cancel. Typing a path to a file opens it. Unknown paths show an error instead of navigating.
- **Refresh** — ⌘R or the button in the address bar. The list also refreshes automatically when files change on disk (even from other apps).
- **Home** — ⇧⌘H.
- **Folder tree** — expand disks and folders lazily; hidden folders and app bundles are skipped.
- **Quick access** — right-click a folder → *Pin to Quick access*; right-click a pinned entry → *Unpin*. Pins persist between launches.

## Views, sorting and grouping

**View** (command bar → View, right-click → View, ⌘1–⌘6): Extra large icons, Large icons, Medium icons, Small icons, List, Details.

**Details view**
- Columns: Name, Date modified, Type, Size. Click a header to sort, click again to reverse (arrow shows direction). Drag a column divider to resize.
- Folders are always listed before files.
- Hidden items are hidden by default; toggle with ⇧⌘. (View → Show → Hidden items). Hidden items appear dimmed.

**Sort by** (command bar → Sort, right-click → Sort by): Name (natural, case-insensitive order), Date modified, Type, Size, with Ascending / Descending.

**Group by**: (None), Name (A, B, C…), Date modified (Today, Yesterday, Earlier this week, Last week, Earlier this month, Last month, Earlier this year, A long time ago), Type, Size (Unspecified, Empty, Tiny, Small, Medium, Large, Huge, Gigantic). Group headers show item counts and work in every view.

## Selecting items

- Click to select; ⌘-click toggles; ⇧-click selects a range.
- ↑ ↓ (and ← → in icon views) move the selection; add ⇧ to extend; Home / End jump to first / last.
- Type letters to jump to the item starting with them (type-to-select).
- ⌘A select all, ⇧⌘I invert selection, Esc or clicking empty space clears it.
- Return opens the selection, Space opens Quick Look.

## Right-click menus

### On a file
Cut · Copy · Rename · Share · Delete — **Open** · **Open with ▸** (all apps that can open it, default marked, “Choose another app…”) · Extract All… (archives) · Compress to ZIP file · Copy as path · Properties — **Show more options ▸**

### On a folder
Cut · Copy · Rename · Share · Delete — Open · **Open in new tab** · **Open in new window** · **Pin / Unpin Quick access** · Compress to ZIP file · Copy as path · Properties — Show more options ▸

### On several items
Cut · Copy · Share · Delete — Open · Compress to ZIP file · Copy as path · Properties — Show more options ▸

### Show more options ▸
Quick Look · Print (files) · **Send to ▸** (Desktop, Documents, Compressed folder, Mail recipient, each mounted volume) · Copy to folder… · Move to folder… · Create shortcut · Open in Terminal · Reveal in Finder · Delete permanently… · *for images:* Set as desktop background, Rotate right, Rotate left

### On empty space
**View ▸** · **Sort by ▸** · **Group by ▸** · Refresh · **Undo** (names the last action) · Paste · Paste shortcut · Open in Terminal · Select all · Invert selection · **New ▸** · Properties

**New ▸**: Folder, Shortcut (pick a target), Text Document, Rich Text Document, Markdown Document, HTML Document, Compressed (zipped) Folder. The new item enters rename mode immediately.

## File operations

| Operation | How | Notes |
|---|---|---|
| **Cut & Paste** | ⌘X then ⌘V | Real move (Finder has none). Also works with the command bar and right-click. |
| **Copy & Paste** | ⌘C then ⌘V | Name conflicts become `name - Copy`, `name - Copy (2)`… Files copied in Finder can be pasted here and vice versa. |
| **Paste shortcut** | right-click empty space | Creates aliases to the clipboard items. |
| **Rename** | F2, command bar, right-click | Inline edit; the name is selected without its extension. Enter / click away to commit, Esc to cancel. Duplicate or invalid names are refused with a message. |
| **Delete** | ⌘⌫ or ⌫, command bar, right-click | Moves to the Trash. |
| **Delete permanently** | ⇧⌫, Show more options | Asks for confirmation; cannot be undone. |
| **Drag & drop** | drag onto a navigation entry or into the list | Same volume → move, different volume → copy, hold ⌥ to flip. Files can also be dragged out to other apps. |
| **Copy to / Move to folder** | Show more options | Folder picker. |
| **Send to** | Show more options | Copies to Desktop, Documents, a volume, zips, or composes an email. |
| **Undo** | ⌘Z or right-click → Undo | Multi-level (50 steps): rename, move, copy (removes copies), create, delete (restores from Trash). |

Safety: a folder can’t be moved or copied into itself; failures are shown in an alert and never leave half-finished state silently.

## Archives and shortcuts

- **Compress to ZIP file** — one item → `<name>.zip`; several → `Archive.zip`; the new archive is selected.
- **Extract All…** — into a folder named after the archive. Supports zip, tar, gz/tgz, bz2, xz, 7z, rar, cpio and iso.
- **Create shortcut** — creates `<name> - Shortcut`, a macOS alias that survives moving/renaming the target. **New ▸ Shortcut** lets you pick the target.

## Properties and the Details pane

**Properties** (⌥↩, right-click → Properties, “…” menu; on empty space it shows the current folder): icon and name, type, location, size and size on disk (bytes + friendly), contents (files/folders, counted recursively), created / modified / accessed dates, and editable **Read-only** and **Hidden** attributes with Apply / OK / Cancel. Multi-selection shows aggregate totals.

**Details pane** (⌥⇧P or the button at the right of the command bar): thumbnail (images, PDFs, documents), name, type, date modified, size and location for one item; item count and total size for several; folder summary when nothing is selected.

## Search

Type in the toolbar search field to search the current folder **and all sub-folders** (up to 5,000 results). Results appear in the normal list with the usual sorting, grouping and context menus; a spinner shows while searching and the status bar says “Search results in …”. Navigating clears the search.

## Windows and tabs

- ⌘N new window, ⌘T new tab (native macOS tabs, so drag tabs between windows as usual).
- Right-click a folder → *Open in new tab* / *Open in new window*.
- Every window/tab has independent navigation history, selection, view mode and sorting.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| New window / tab / folder | ⌘N / ⌘T / ⇧⌘N |
| Cut / Copy / Paste | ⌘X / ⌘C / ⌘V |
| Undo | ⌘Z |
| Rename | F2 |
| Move to Trash | ⌘⌫ or ⌫ |
| Delete permanently | ⇧⌫ |
| Select all / Invert selection | ⌘A / ⇧⌘I |
| Back / Forward / Up | ⌘[ / ⌘] / ⌘↑ |
| Refresh | ⌘R |
| Address bar | ⌘L |
| Home | ⇧⌘H |
| Open selection | Return |
| Quick Look | Space |
| Properties | ⌥↩ |
| Details pane | ⌥⇧P |
| Hidden items | ⇧⌘. |
| View modes | ⌘1 … ⌘6 |

Edit-menu shortcuts (Cut/Copy/Paste/Select all/Undo/Delete) act on text when you’re typing in the search field, address bar or a rename box, and on files otherwise.

## Command-line options

Useful for scripting and screenshots:

```bash
open -n build/Explorer.app --args --path ~/Documents --view "Large icons" \
     --group "Date modified" --details-pane --hidden --select "a.txt,b.txt" --dark
```

| Option | Meaning |
|---|---|
| `--path <dir>` | Folder to open |
| `--view <name>` | `Details`, `List`, `Small icons`, `Medium icons`, `Large icons`, `Extra large icons` |
| `--group <key>` | `Name`, `Date modified`, `Type`, `Size` |
| `--details-pane` | Show the Details pane |
| `--hidden` | Show hidden items |
| `--select a,b` | Select items by name |
| `--light` / `--dark` | Force appearance |

## Behaviour notes

- The app is **not sandboxed** so it can browse your whole disk. macOS will ask for permission to Documents, Downloads, etc.; grant *Full Disk Access* for unrestricted browsing.
- Archives are handled by the system tools `zip`, `ditto` and `tar`; printing uses `lpr`; image rotation uses `sips`.
- Shortcuts are macOS aliases, not Windows `.lnk` files.
- Not implemented in 1.0.0: Home/Gallery pages, drag-box selection, Tiles and Content views, image thumbnails in icon views, *Restore previous versions*, *Give access to*.
