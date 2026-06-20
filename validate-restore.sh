#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# validate-restore.sh — validate what was restored vs a backup
# Usage: ./validate-restore.sh <backup-directory>
# ============================================================

# ---------- helpers ----------

error()  { echo "ERROR: $*" >&2; exit 1; }
info()   { echo "→ $*"; }
ok()     { echo "  ✓ $*"; }
warn()   { echo "  ⚠ $*"; }
missing() { echo "  ✗ $*"; }

# ---------- verify functions ----------

verify_brewfile() {
  if [[ ! -f "$BACKUP_DIR/Brewfile" ]]; then
    warn "No Brewfile in backup — skipping brew check."
    return
  fi

  echo ""
  echo "── Brewfile ──"

  local total=0 present=0 missed=0
  local tmp_missing
  tmp_missing=$(mktemp)

  # Parse Brewfile: lines like: brew "name" or cask "name"
  while IFS= read -r line; do
    local type="" name=""
    if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
      type="formula"
      name="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
      type="cask"
      name="${BASH_REMATCH[1]}"
    else
      continue
    fi
    total=$((total + 1))

    if [[ "$type" == "cask" ]]; then
      if brew list --cask 2>/dev/null | grep -qF "$name"; then
        present=$((present + 1))
      else
        echo "  $name (cask)" >> "$tmp_missing"
        missed=$((missed + 1))
      fi
    else
      if brew list --formula 2>/dev/null | grep -qF "$name"; then
        present=$((present + 1))
      else
        echo "  $name" >> "$tmp_missing"
        missed=$((missed + 1))
      fi
    fi
  done < "$BACKUP_DIR/Brewfile"

  echo "  total: $total"
  ok "installed: $present"
  if [[ "$missed" -gt 0 ]]; then
    missing "missing: $missed"
    cat "$tmp_missing"
  fi
  rm -f "$tmp_missing"
}

verify_apps() {
  if [[ ! -f "$BACKUP_DIR/apps.txt" ]] || [[ ! -s "$BACKUP_DIR/apps.txt" ]]; then
    return
  fi

  echo ""
  echo "── Mac Apps ──"
  local total=0 present=0 missed=0

  while IFS= read -r app; do
    [[ -z "$app" ]] && continue
    total=$((total + 1))
    if [[ -d "/Applications/${app}.app" ]] || [[ -d "$HOME/Applications/${app}.app" ]]; then
      present=$((present + 1))
    else
      missing "$app"
      missed=$((missed + 1))
    fi
  done < "$BACKUP_DIR/apps.txt"

  echo "  total: $total"
  ok "present: $present"
  [[ "$missed" -gt 0 ]] && missing "missing: $missed"
}

verify_fonts() {
  if [[ ! -f "$BACKUP_DIR/fonts.txt" ]] || [[ ! -s "$BACKUP_DIR/fonts.txt" ]]; then
    return
  fi

  echo ""
  echo "── Fonts ──"
  local total=0 present=0 missed=0

  while IFS= read -r font; do
    [[ -z "$font" ]] && continue
    total=$((total + 1))
    local found=0
    for ext in ttf otf ttc woff2 dfont; do
      if [[ -f "$HOME/Library/Fonts/${font}.${ext}" ]] || [[ -f "/Library/Fonts/${font}.${ext}" ]]; then
        found=1
        break
      fi
    done
    if [[ "$found" -eq 1 ]]; then
      present=$((present + 1))
    else
      missing "$font"
      missed=$((missed + 1))
    fi
  done < "$BACKUP_DIR/fonts.txt"

  echo "  total: $total"
  ok "present: $present"
  [[ "$missed" -gt 0 ]] && missing "missing: $missed"
}

verify_claude() {
  if [[ ! -d "$BACKUP_DIR/claude" ]]; then
    return
  fi

  echo ""
  echo "── Claude config ──"
  local total=0 present=0 missed=0

  while IFS= read -r -d '' f; do
    local rel="${f#$BACKUP_DIR/claude/}"
    total=$((total + 1))
    if [[ -f "$HOME/.claude/$rel" ]]; then
      present=$((present + 1))
    else
      missing ".claude/$rel"
      missed=$((missed + 1))
    fi
  done < <(find "$BACKUP_DIR/claude" -type f -print0)

  echo "  total: $total"
  ok "exists: $present"
  [[ "$missed" -gt 0 ]] && missing "missing: $missed"
}

verify_dotfiles() {
  if [[ ! -d "$BACKUP_DIR/dotfiles" ]]; then
    return
  fi

  echo ""
  echo "── Dotfiles ──"
  local total=0 present=0 missed=0

  while IFS= read -r -d '' f; do
    local rel="${f#$BACKUP_DIR/dotfiles/}"
    total=$((total + 1))
    if [[ -f "$HOME/$rel" ]]; then
      present=$((present + 1))
    else
      missing "$rel"
      missed=$((missed + 1))
    fi
  done < <(find "$BACKUP_DIR/dotfiles" -type f -print0)

  echo "  total: $total"
  ok "exists: $present"
  [[ "$missed" -gt 0 ]] && missing "missing: $missed"
}

verify_projects() {
  if [[ ! -f "$BACKUP_DIR/projects.txt" ]] || [[ ! -s "$BACKUP_DIR/projects.txt" ]]; then
    return
  fi

  echo ""
  echo "── Projects ──"
  local total=0 present=0 missed=0

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local repodir="${line%%    *}"
    [[ "$repodir" == "_LIST_ONLY_" ]] && continue
    total=$((total + 1))
    if [[ -d "$repodir" ]] && [[ -d "$repodir/.git" ]]; then
      present=$((present + 1))
    else
      missing "$repodir"
      missed=$((missed + 1))
    fi
  done < "$BACKUP_DIR/projects.txt"

  echo "  total: $total"
  ok "exists: $present"
  [[ "$missed" -gt 0 ]] && missing "missing: $missed"
}

verify_desktop_docs() {
  for dir in Desktop Documents Downloads; do
    if [[ -d "$BACKUP_DIR/$dir" ]]; then
      echo ""
      echo "── $dir ──"
      local backup_count
      backup_count=$(find "$BACKUP_DIR/$dir" -type f 2>/dev/null | wc -l | tr -d ' ')
      local current_count=0
      [[ -d "$HOME/$dir" ]] && current_count=$(find "$HOME/$dir" -type f 2>/dev/null | wc -l | tr -d ' ')
      echo "  files in backup: $backup_count"
      echo "  files currently on disk: $current_count"
    fi
  done
}

# ---------- main ----------

main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <backup-directory>"
    echo "Example: $0 ~/Desktop/backup-2026-06-20-143022"
    exit 1
  fi

  BACKUP_DIR="$1"
  shift

  if [[ ! -d "$BACKUP_DIR" ]]; then
    error "Backup directory not found: $BACKUP_DIR"
  fi

  if ! command -v brew &>/dev/null; then
    warn "Homebrew not found — skipping brew verification."
  fi

  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  validate-restore — $(basename "$BACKUP_DIR")"
  echo "═══════════════════════════════════════════════════════"

  verify_brewfile
  verify_apps
  verify_fonts
  verify_dotfiles
  verify_claude
  verify_projects
  verify_desktop_docs

  echo ""
  echo "─────────────────────────────────────────────"
  echo "  Verification complete."
  echo "═══════════════════════════════════════════════"
}

main "$@"
