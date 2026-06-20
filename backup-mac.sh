#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# backup-mac.sh — interactive backup utility
# ============================================================

# ---------- helpers ----------

error()  { echo "ERROR: $*" >&2; exit 1; }
info()   { echo "→ $*"; }
ok()     { echo "✓ $*"; }
warn()   { echo "⚠ $*"; }

# Prompt with timeout, defaulting to No. Returns 0 for yes, 1 for no.
# $1: prompt text (e.g. "Copy Desktop to backup?")
# $2: default — "yes" or "no" (default: "no")
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
  read -r -t 5 ans 2>/dev/null || ans=""

  if [[ "$default" == "yes" ]]; then
    [[ "$ans" =~ ^[Nn] ]] && return 1 || return 0
  else
    [[ "$ans" =~ ^[Yy] ]] && return 0 || return 1
  fi
}

# Check that fzf is available; offer to install if missing.
ensure_fzf() {
  if ! command -v fzf &>/dev/null; then
    echo "fzf is required for interactive selection."
    echo -n "Install it now via Homebrew? [Y/n] "
    read -r ans
    if [[ "$ans" =~ ^[Nn] ]]; then
      error "fzf is required. Exiting."
    fi
    if ! command -v brew &>/dev/null; then
      error "Homebrew not found. Please install Homebrew first, then run again."
    fi
    brew install fzf
  fi
}

# ---------- fzf helpers ----------

# Pipe items (one per line) to fzf for multiselect.
# Returns selected items to stdout, one per line.
# If fzf exits with 130 (Esc), returns nothing (empty).
# Params: $1 — prompt label
fzf_select() {
  local prompt="$1"
  fzf --multi \
      --prompt="$prompt > " \
      --bind="tab:toggle+down" \
      --bind="ctrl-a:select-all" \
      --bind="ctrl-d:deselect-all" \
      --header="Tab: toggle | Ctrl-A: select all | Ctrl-D: deselect all | Enter: confirm | Esc: skip" || true
}

# stdin → fzf → stdout (filtered). Prints count info to stderr.
# $1: category name   $2: output path
run_category() {
  local name="$1"
  local outfile="$2"
  local tmpfile
  tmpfile=$(mktemp)

  # Read all lines from stdin into tmpfile so we can count them.
  cat > "$tmpfile"
  local total
  total=$(wc -l < "$tmpfile" | tr -d ' ')

  if [[ "$total" -eq 0 ]]; then
    info "$name: none found, skipping."
    rm -f "$tmpfile"
    return
  fi

  info "$name: $total items found — select which to keep."
  fzf_select "$name" < "$tmpfile" > "$outfile"
  local selected
  selected=$(wc -l < "$outfile" | tr -d ' ')

  if [[ "$selected" -eq 0 ]]; then
    ok "$name: none selected."
  else
    ok "$name: $selected kept."
  fi
  rm -f "$tmpfile"
}

DOTFILES=(
  .zshrc .zprofile .zshenv .bashrc .bash_profile .profile
  .gitconfig .gitignore_global
  .ssh/config .ssh/known_hosts
  .vimrc .gvimrc .ideavimrc
  .tmux.conf .screenrc
  .hushlogin .inputrc
  .curlrc .wgetrc
  .gemrc .npmrc
  .terraformrc .psqlrc
)

PROJECT_ROOTS=(
  "$HOME/dev"
  "$HOME/Developer/Personal"
)

# ---------- category functions ----------

brewfile() {
  if ! command -v brew &>/dev/null; then
    warn "Homebrew not found. Skipping Brewfile."
    return
  fi

  local tmp selected
  tmp=$(mktemp)

  # Gather top-level formulae.
  brew leaves 2>/dev/null | while IFS= read -r f; do
    [[ -n "$f" ]] && echo "brew: $f"
  done >> "$tmp"

  # Gather casks.
  brew list --cask 2>/dev/null | while IFS= read -r c; do
    [[ -n "$c" ]] && echo "cask: $c"
  done >> "$tmp"

  # Show both types in one fzf session.
  info "Brewfile: select formulae and casks to keep."
  selected=$(mktemp)
  run_category "Brewfile" "$selected" < "$tmp"
  rm -f "$tmp"

  # Generate Brewfile from selections.
  local kept=0
  {
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local type="${line%%: *}"
      local name="${line#*: }"
      if [[ "$type" == "cask" ]]; then
        echo "cask \"$name\""
      else
        echo "brew \"$name\""
      fi
      kept=$((kept + 1))
    done < "$selected"
  } > "$BACKUP_DIR/Brewfile"

  if [[ "$kept" -gt 0 ]]; then
    ok "Brewfile: $kept entries written to $BACKUP_DIR/Brewfile"
  else
    warn "Brewfile: none selected."
    rm -f "$BACKUP_DIR/Brewfile"
  fi
  rm -f "$selected"
}

mac_apps() {
  local apps_dir
  apps_dir=$(mktemp -d)

  # Collect .app names from both locations.
  for dir in /Applications "$HOME/Applications"; do
    if [[ -d "$dir" ]]; then
      find "$dir" -maxdepth 2 -name '*.app' -print0 2>/dev/null | while IFS= read -r -d '' app; do
        basename "$app" .app
      done >> "$apps_dir/all"
    fi
  done

  if [[ ! -f "$apps_dir/all" ]]; then
    info "Mac Apps: none found, skipping."
    rm -rf "$apps_dir"
    return
  fi

  # Deduplicate.
  sort -u "$apps_dir/all" | run_category "Mac Apps" "$BACKUP_DIR/apps.txt"
  rm -rf "$apps_dir"
}

fonts() {
  local tmp
  tmp=$(mktemp)

  for dir in "$HOME/Library/Fonts" /Library/Fonts; do
    if [[ -d "$dir" ]]; then
      find "$dir" -maxdepth 2 \( -name '*.ttf' -o -name '*.otf' -o -name '*.ttc' -o -name '*.woff2' -o -name '*.dfont' \) -print0 2>/dev/null | while IFS= read -r -d '' font; do
        basename "$font" | sed 's/\.[^.]*$//'
      done >> "$tmp"
    fi
  done

  sort -u "$tmp" | run_category "Fonts" "$BACKUP_DIR/fonts.txt"
  rm -f "$tmp"
}

dotfiles() {
  local tmp selected
  tmp=$(mktemp)

  # Predefined dotfiles that exist.
  for df in "${DOTFILES[@]}"; do
    if [[ -f "$HOME/$df" ]]; then
      echo "$df"
    fi
  done >> "$tmp"

  # Files from ~/.config/ (up to 1 level deep).
  if [[ -d "$HOME/.config" ]]; then
    find "$HOME/.config" -maxdepth 2 -type f -print0 2>/dev/null | while IFS= read -r -d '' f; do
      echo "${f#$HOME/}"
    done >> "$tmp"
  fi

  selected=$(mktemp)
  run_category "Dotfiles" "$selected" < "$tmp"
  rm -f "$tmp"

  local kept=0
  while IFS= read -r df; do
    [[ -z "$df" ]] && continue
    local dest="$BACKUP_DIR/dotfiles/$(dirname "$df")"
    mkdir -p "$dest"
    cp "$HOME/$df" "$dest/"
    kept=$((kept + 1))
  done < "$selected"

  if [[ "$kept" -gt 0 ]]; then
    ok "Dotfiles: $kept copied to $BACKUP_DIR/dotfiles/"
  else
    warn "Dotfiles: none selected."
    rmdir "$BACKUP_DIR/dotfiles" 2>/dev/null || true
  fi
  rm -f "$selected"
}

claude_config() {
  if ! yes_no "Backup Claude config (~/.claude)?" "no"; then
    return
  fi

  local tmp
  tmp=$(mktemp)

  if [[ -d "$HOME/.claude" ]]; then
    find "$HOME/.claude" -maxdepth 4 -type f -print0 2>/dev/null | while IFS= read -r -d '' f; do
      echo "${f#$HOME/}"
    done >> "$tmp"
  fi

  if [[ ! -s "$tmp" ]]; then
    warn "Claude config: no files found in ~/.claude."
    rm -f "$tmp"
    return
  fi

  local selected
  selected=$(mktemp)
  run_category "Claude config" "$selected" < "$tmp"
  rm -f "$tmp"

  local kept=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    local dest="$BACKUP_DIR/claude/$(dirname "$f")"
    mkdir -p "$dest"
    cp "$HOME/$f" "$dest/"
    kept=$((kept + 1))
  done < "$selected"

  if [[ "$kept" -gt 0 ]]; then
    ok "Claude config: $kept files copied to $BACKUP_DIR/claude/"
  else
    warn "Claude config: none selected."
    rmdir "$BACKUP_DIR/claude" 2>/dev/null || true
  fi
  rm -f "$selected"
}

projects() {
  if ! yes_no "Copy projects to backup?" "no"; then
    return
  fi

  local tmp
  tmp=$(mktemp)

  for root in "${PROJECT_ROOTS[@]}"; do
    if [[ ! -d "$root" ]]; then
      warn "Projects: $root does not exist, skipping."
      continue
    fi
    find "$root" -maxdepth 3 -name '.git' -type d -print0 2>/dev/null | while IFS= read -r -d '' gitdir; do
      local repodir
      repodir=$(dirname "$gitdir")
      local remote
      remote=$(git -C "$repodir" remote get-url origin 2>/dev/null || echo "(no remote)")
      local flag=""
      # Check for unpushed local commits.
      if git -C "$repodir" rev-parse @{u} &>/dev/null; then
        local ahead
        ahead=$(git -C "$repodir" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
        if [[ "$ahead" -gt 0 ]]; then
          flag=" [UNPUSHED: $ahead]"
        fi
      fi
      echo "$repodir    $remote$flag"
    done >> "$tmp"
  done

  # Also add a "list only (no copy)" option as first line (will appear in fzf)
  {
    echo "_LIST_ONLY_    (save list only, don't copy files)"
    cat "$tmp"
  } | run_category "Projects" "$BACKUP_DIR/projects.txt"

  # Read selections and copy them
  local kept=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local repodir="${line%%    *}"
    if [[ "$repodir" == "_LIST_ONLY_" ]]; then
      continue
    fi
    local dest="$BACKUP_DIR/projects/${repodir#$HOME/}"
    mkdir -p "$(dirname "$dest")"
    info "Projects: copying $repodir..."
    rsync -a --exclude='node_modules' --exclude='.venv' --exclude='venv' --exclude='__pycache__' --exclude='*.pyc' "$repodir/" "$dest/" 2>/dev/null || warn "Projects: $repodir had errors."
    kept=$((kept + 1))
  done < "$BACKUP_DIR/projects.txt"

  if [[ "$kept" -gt 0 ]]; then
    ok "Projects: $kept copied to $BACKUP_DIR/projects/"
  else
    warn "Projects: none copied (list saved)."
    rmdir "$BACKUP_DIR/projects" 2>/dev/null || true
  fi
  rm -f "$tmp"
}

copy_desktop() {
  if ! yes_no "Copy Desktop to backup?" "no"; then
    return
  fi

  local src="$HOME/Desktop"
  local size
  size=$(du -sh "$src" 2>/dev/null | cut -f1)

  if [[ "$size" =~ ^[0-9]+G ]] || [[ "$size" =~ ^[1-9][0-9]*G ]]; then
    if ! yes_no "Desktop is $size. Continue?" "no"; then
      return
    fi
  fi

  info "Desktop: copying to backup..."
  rsync -a --exclude='.*' "$src/" "$BACKUP_DIR/Desktop/" 2>/dev/null || warn "Desktop: some files could not be copied."
  ok "Desktop: done."
}

copy_documents() {
  if ! yes_no "Copy Documents to backup?" "no"; then
    return
  fi

  local src="$HOME/Documents"
  local size
  size=$(du -sh "$src" 2>/dev/null | cut -f1)

  if [[ "$size" =~ ^[0-9]+G ]] || [[ "$size" =~ ^[1-9][0-9]*G ]]; then
    if ! yes_no "Documents is $size. Continue?" "no"; then
      return
    fi
  fi

  info "Documents: copying to backup..."
  rsync -a --exclude='.*' "$src/" "$BACKUP_DIR/Documents/" 2>/dev/null || warn "Documents: some files could not be copied."
  ok "Documents: done."
}

copy_downloads() {
  if ! yes_no "Copy Downloads to backup?" "no"; then
    return
  fi

  local src="$HOME/Downloads"
  local size
  size=$(du -sh "$src" 2>/dev/null | cut -f1)

  if [[ "$size" =~ ^[0-9]+G ]] || [[ "$size" =~ ^[1-9][0-9]*G ]]; then
    if ! yes_no "Downloads is $size. Continue?" "no"; then
      return
    fi
  fi

  info "Downloads: copying to backup..."
  rsync -a --exclude='.*' "$src/" "$BACKUP_DIR/Downloads/" 2>/dev/null || warn "Downloads: some files could not be copied."
  ok "Downloads: done."
}

zip_backup() {
  if ! yes_no "Zip backup for upload (1GB parts)?" "no"; then
    return
  fi

  local dirname
  dirname=$(basename "$BACKUP_DIR")
  local parent
  parent=$(dirname "$BACKUP_DIR")

  info "Zip: compressing and splitting into 1GB parts..."
  (
    cd "$parent" || exit 1
    tar -cf - "$dirname" | gzip | split -b 1G - "${dirname}.zip.part-"
  )

  if [[ $? -eq 0 ]]; then
    ok "Zip: parts written to ${parent}/${dirname}.zip.part-*"
    info "Zip: removing original directory $BACKUP_DIR..."
    rm -rf "$BACKUP_DIR"
    ok "Zip: done. Upload ${dirname}.zip.part-* to Google Drive."
  else
    warn "Zip: failed. Original directory preserved at $BACKUP_DIR."
  fi
}

# Create a timestamped output directory.
BACKUP_DIR="$HOME/Desktop/backup-$(date +%Y-%m-%d-%H%M%S)"

# Avoid overwriting an existing directory by incrementing a suffix.
suffix=""
n=2
while [[ -d "${BACKUP_DIR}${suffix}" ]]; do
  suffix="-$n"
  ((n++))
done
BACKUP_DIR="${BACKUP_DIR}${suffix}"
mkdir -p "$BACKUP_DIR"
info "Backup directory: $BACKUP_DIR"

# ============================================================
# Main
# ============================================================
ensure_fzf

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  backup-mac — interactive backup"
echo "═══════════════════════════════════════════════════════"
echo ""

brewfile
mac_apps
fonts
mkdir -p "$BACKUP_DIR/dotfiles"
dotfiles
mkdir -p "$BACKUP_DIR/claude"
claude_config
copy_desktop
copy_documents
copy_downloads
projects
zip_backup

echo ""
echo "═══════════════════════════════════════════════════════"
if [[ -d "$BACKUP_DIR" ]]; then
  echo "  Backup complete — $BACKUP_DIR"
  echo "═══════════════════════════════════════════════════════"
  ls -lh "$BACKUP_DIR"
else
  echo "  Backup complete — zipped"
  echo "═══════════════════════════════════════════════════════"
  ls -lh "${BACKUP_DIR}".zip.part-* 2>/dev/null || true
fi
echo ""
info "Restore: run ./restore-mac.sh with the backup directory or zip parts"
