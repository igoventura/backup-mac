#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# restore-mac.sh — restore from a backup-mac backup
# Usage: ./restore-mac.sh <backup-dir-or-zip-prefix>
# ============================================================

# ---------- helpers ----------

error()  { echo "ERROR: $*" >&2; exit 1; }
info()   { echo "→ $*"; }
ok()     { echo "✓ $*"; }
warn()   { echo "⚠ $*"; }

yes_no() {
  local prompt="$1"
  local default="${2:-no}"
  local hint
  if [[ "$default" == "yes" ]]; then
    hint="[Y/n]"
  else
    hint="[y/N]"
  fi
  echo -n "→ $prompt $hint "
  read -r -t 10 ans 2>/dev/null || ans=""
  if [[ "$default" == "yes" ]]; then
    [[ "$ans" =~ ^[Nn] ]] && return 1 || return 0
  else
    [[ "$ans" =~ ^[Yy] ]] && return 0 || return 1
  fi
}

ensure_fzf() {
  if ! command -v fzf &>/dev/null; then
    echo "fzf is required."
    echo -n "Install it now via Homebrew? [Y/n] "
    read -r ans
    if [[ "$ans" =~ ^[Nn] ]]; then
      error "fzf is required. Exiting."
    fi
    if ! command -v brew &>/dev/null; then
      error "Homebrew not found. Please install Homebrew first."
    fi
    brew install fzf
  fi
}

ensure_brew() {
  if ! command -v brew &>/dev/null; then
    error "Homebrew is required for restoring Brewfile. Install from https://brew.sh"
  fi
}

# ---------- resolve_backup ----------

# If BACKUP is a zip part pattern (contains ".zip.part-"), reassemble.
# Returns the resolved backup directory path via BACKUP_DIR global.
resolve_backup() {
  local target="$1"

  # If it's already a directory, use it directly.
  if [[ -d "$target" ]]; then
    BACKUP_DIR="$target"
    return
  fi

  # Check for zip parts (e.g. ~/Desktop/backup-2026-06-20.zip.part-aa)
  local base="${target%%.zip.part-*}"
  local first_part="${base}.zip.part-aa"

  if [[ -f "$first_part" ]]; then
    info "Found zip parts, reassembling..."
    local merged="${base}.tar.gz"
    cat "${base}.zip.part-"* > "$merged"
    info "Extracting..."
    tar -xzf "$merged" -C "$(dirname "$base")"
    rm -f "$merged"
    ok "Extracted to $base"
    BACKUP_DIR="$base"
  elif [[ -f "$target" ]] && [[ "$target" =~ \.zip\.part-aa$ ]]; then
    # User passed the first part explicitly.
    base="${target%%.zip.part-aa}"
    local merged="${base}.tar.gz"
    cat "${base}.zip.part-"* > "$merged"
    info "Extracting..."
    tar -xzf "$merged" -C "$(dirname "$base")"
    rm -f "$merged"
    ok "Extracted to $base"
    BACKUP_DIR="$base"
  else
    error "Backup not found: $target"
  fi
}

# ---------- restore_brewfile ----------

restore_brewfile() {
  if [[ ! -f "$BACKUP_DIR/Brewfile" ]]; then
    warn "No Brewfile found in backup."
    return
  fi

  if ! yes_no "Restore Brewfile? (brew bundle install)" "yes"; then
    return
  fi

  info "Brewfile: installing..."
  brew bundle install --file="$BACKUP_DIR/Brewfile"
  ok "Brewfile: installed."
}

# ---------- restore_dotfiles ----------

restore_dotfiles() {
  if [[ ! -d "$BACKUP_DIR/dotfiles" ]]; then
    warn "No dotfiles in backup."
    return
  fi

  if ! yes_no "Restore dotfiles to ~/?" "yes"; then
    return
  fi

  local count=0
  while IFS= read -r -d '' f; do
    local rel="${f#$BACKUP_DIR/dotfiles/}"
    local dest="$HOME/$rel"
    mkdir -p "$(dirname "$dest")"
    cp "$f" "$dest"
    count=$((count + 1))
  done < <(find "$BACKUP_DIR/dotfiles" -type f -print0)

  ok "Dotfiles: $count restored."
}

# ---------- restore_projects ----------

restore_projects() {
  if [[ ! -d "$BACKUP_DIR/projects" ]]; then
    warn "No projects in backup."
    return
  fi

  if ! yes_no "Restore projects?" "no"; then
    return
  fi

  echo -n "→ Restore projects to directory [~/dev]: "
  read -r target
  target="${target:-$HOME/dev}"
  mkdir -p "$target"

  local count=0
  for proj in "$BACKUP_DIR/projects"/*/; do
    [[ -d "$proj" ]] || continue
    local name
    name=$(basename "$proj")
    info "Projects: restoring $name..."
    rsync -a "$proj" "$target/$name/"
    count=$((count + 1))
  done

  ok "Projects: $count restored to $target."
}

# ---------- restore_desktop ----------

restore_desktop() {
  if [[ ! -d "$BACKUP_DIR/Desktop" ]]; then
    warn "No Desktop in backup."
    return
  fi

  if ! yes_no "Restore Desktop to ~/Desktop?" "no"; then
    return
  fi

  info "Desktop: restoring..."
  rsync -a "$BACKUP_DIR/Desktop/" "$HOME/Desktop/"
  ok "Desktop: restored."
}

# ---------- restore_documents ----------

restore_documents() {
  if [[ ! -d "$BACKUP_DIR/Documents" ]]; then
    warn "No Documents in backup."
    return
  fi

  if ! yes_no "Restore Documents to ~/Documents?" "no"; then
    return
  fi

  info "Documents: restoring..."
  rsync -a "$BACKUP_DIR/Documents/" "$HOME/Documents/"
  ok "Documents: restored."
}

# ---------- restore_claude ----------

restore_claude() {
  if [[ ! -d "$BACKUP_DIR/claude" ]]; then
    warn "No Claude config in backup."
    return
  fi

  if ! yes_no "Restore Claude config to ~/.claude?" "no"; then
    return
  fi

  local count=0
  while IFS= read -r -d '' f; do
    local rel="${f#$BACKUP_DIR/claude/}"
    local dest="$HOME/.claude/$rel"
    mkdir -p "$(dirname "$dest")"
    cp "$f" "$dest"
    count=$((count + 1))
  done < <(find "$BACKUP_DIR/claude" -type f -print0)

  ok "Claude config: $count files restored."
}

# ---------- restore_downloads ----------

restore_downloads() {
  if [[ ! -d "$BACKUP_DIR/Downloads" ]]; then
    warn "No Downloads in backup."
    return
  fi

  if ! yes_no "Restore Downloads to ~/Downloads?" "no"; then
    return
  fi

  info "Downloads: restoring..."
  rsync -a "$BACKUP_DIR/Downloads/" "$HOME/Downloads/"
  ok "Downloads: restored."
}

# ---------- print_lists ----------

print_lists() {
  local printed=0

  if [[ -f "$BACKUP_DIR/apps.txt" ]] && [[ -s "$BACKUP_DIR/apps.txt" ]]; then
    echo ""
    info "─────────────────────────────────────────────"
    info "Apps to reinstall manually (App Store / .dmg):"
    cat "$BACKUP_DIR/apps.txt"
    printed=1
  fi

  if [[ -f "$BACKUP_DIR/fonts.txt" ]] && [[ -s "$BACKUP_DIR/fonts.txt" ]]; then
    echo ""
    info "─────────────────────────────────────────────"
    info "Fonts to reinstall manually:"
    cat "$BACKUP_DIR/fonts.txt"
    printed=1
  fi

  [[ "$printed" -eq 0 ]] && return
  echo ""
}

# ---------- main ----------

main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <backup-directory-or-zip-prefix>"
    echo "Example: $0 ~/Desktop/backup-2026-06-20-143022"
    exit 1
  fi

  BACKUP="$1"
  shift

  ensure_fzf
  ensure_brew

  resolve_backup "$BACKUP"
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  restore-mac — $BACKUP_DIR"
  echo "═══════════════════════════════════════════════════════"
  echo ""

  restore_brewfile
  restore_dotfiles
  restore_claude
  restore_projects
  restore_desktop
  restore_documents
  restore_downloads
  print_lists

  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Restore complete."
  echo "═══════════════════════════════════════════════════════"
}

main "$@"
