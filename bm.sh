#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# bm.sh — backup-mac main menu
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP="$SCRIPT_DIR/backup-mac.sh"
RESTORE="$SCRIPT_DIR/restore-mac.sh"
VALIDATE="$SCRIPT_DIR/validate-restore.sh"
VALZIP="$SCRIPT_DIR/validate-backup.sh"

# Check that scripts are present before offering them.
check() { [[ -f "$1" ]] && return 0 || return 1; }

info()  { echo "→ $*"; }
warn()  { echo "⚠ $*"; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  backup-mac"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  1. Backup        (backup-mac.sh)"
echo "  2. Restore       (restore-mac.sh)"
echo "  3. Validate zip  (validate-backup.sh)"
echo "  4. Validate restore (validate-restore.sh)"
echo "  q. Quit"
echo ""

read -r -p "→ Choose [1-4/q]: " choice

case "$choice" in
  1)
    check "$BACKUP" || { warn "$BACKUP not found."; exit 1; }
    exec bash "$BACKUP"
    ;;
  2)
    check "$RESTORE" || { warn "$RESTORE not found."; exit 1; }
    read -r -p "→ Backup path or zip part: " path
    exec bash "$RESTORE" "$path"
    ;;
  3)
    check "$VALZIP" || { warn "$VALZIP not found."; exit 1; }
    read -r -p "→ Zip .part-aa file: " path
    exec bash "$VALZIP" "$path"
    ;;
  4)
    check "$VALIDATE" || { warn "$VALIDATE not found."; exit 1; }
    read -r -p "→ Backup directory: " path
    exec bash "$VALIDATE" "$path"
    ;;
  q|Q)
    echo "Bye."
    exit 0
    ;;
  *)
    warn "Invalid choice."
    exit 1
    ;;
esac
