#!/bin/bash
# Removes Explorer for macOS: the app, the `explorermac` command and saved settings.
#   ./uninstall.sh                 ask, then remove everything
#   ./uninstall.sh --yes           don't ask
#   ./uninstall.sh --keep-settings keep preferences / pinned folders
#   ./uninstall.sh --dry-run       only list what would be removed
# (Also shipped in the .dmg as "Uninstall Explorer.command".)
set -uo pipefail

BUNDLE_ID="com.local.explorer"
YES=0; KEEP=0; DRY=0
for a in "$@"; do
  case "$a" in
    --yes|-y) YES=1 ;;
    --keep-settings) KEEP=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

# Overridable for testing: EXPLORER_APP_DIRS / EXPLORER_BIN_DIRS (colon-separated)
IFS=: read -r -a APP_DIRS <<< "${EXPLORER_APP_DIRS:-/Applications:$HOME/Applications}"
IFS=: read -r -a BIN_DIRS <<< "${EXPLORER_BIN_DIRS:-/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin}"

targets=()
for d in "${APP_DIRS[@]}"; do [ -d "$d/Explorer.app" ] && targets+=("$d/Explorer.app"); done
for d in "${BIN_DIRS[@]}"; do
  # only remove the command if it really is ours
  if [ -f "$d/explorermac" ] && grep -q "$BUNDLE_ID" "$d/explorermac" 2>/dev/null; then targets+=("$d/explorermac"); fi
done
if [ "$KEEP" -eq 0 ]; then
  for f in "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState" "$HOME/Library/Caches/$BUNDLE_ID" \
           "$HOME/Library/Preferences/$BUNDLE_ID.plist"; do
    [ -e "$f" ] && targets+=("$f")
  done
fi

if [ ${#targets[@]} -eq 0 ]; then echo "Nothing to remove — Explorer for macOS isn't installed."; exit 0; fi
echo "Will remove:"; printf '  %s\n' "${targets[@]}"
[ "$DRY" -eq 1 ] && exit 0

if [ "$YES" -eq 0 ]; then
  read -r -p "Continue? [y/N] " ans
  case "$ans" in y|Y|yes|YES) ;; *) echo "Cancelled."; exit 1 ;; esac
fi

pkill -x Explorer 2>/dev/null && sleep 1
rc=0
for t in "${targets[@]}"; do
  if rm -rf "$t" 2>/dev/null; then echo "removed $t"; else echo "couldn't remove $t (try: sudo rm -rf \"$t\")" >&2; rc=1; fi
done
[ "$KEEP" -eq 0 ] && defaults delete "$BUNDLE_ID" 2>/dev/null
echo "Done."; exit $rc
