#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# validate-backup.sh — validate a backup-mac zip file
# Usage: ./validate-backup.sh <backup.zip.part-aa>
# ============================================================

error()  { echo "ERROR: $*" >&2; exit 1; }
info()   { echo "→ $*"; }
ok()     { echo "✓ $*"; }
warn()   { echo "⚠ $*"; }

# Offer to install tree if not present (needed for tree views).
ensure_tree() {
  if ! command -v tree &>/dev/null; then
    echo "tree is not installed (needed for tree views)."
    echo -n "Install it now via Homebrew? [Y/n] "
    read -r ans
    if [[ "$ans" =~ ^[Nn] ]]; then
      warn "tree not installed — tree views will use a simpler format."
      return 1
    fi
    if ! command -v brew &>/dev/null; then
      warn "Homebrew not found. Tree views will use a simpler format."
      return 1
    fi
    brew install tree
  fi
  return 0
}

# Display a tree view for a category by extracting it to a temp dir.
# Falls back to flat listing if `tree` is not installed.
# $1: merged tar.gz path
# $2: top-level prefix (e.g. "backup-2026-06-20-153325/")
# $3: category name (e.g. "claude", "dotfiles")
tree_view() {
  local merged="$1"
  local prefix="$2"
  local category="$3"

  # Extract just this category
  local tmpdir
  tmpdir=$(mktemp -d)
  tar -xzf "$merged" -C "$tmpdir" "${prefix}${category}/" 2>/dev/null || true

  local target="$tmpdir/${prefix}${category}"
  if [[ ! -d "$target" ]] || [[ -z "$(ls -A "$target" 2>/dev/null)" ]]; then
    echo "    (empty)"
    rm -rf "$tmpdir"
    return
  fi

  if command -v tree &>/dev/null; then
    tree -a "$target" 2>/dev/null | tail -n +2 | sed 's/^/    /'
  else
    # Fallback: show paths with depth-based indentation
    (cd "$tmpdir/${prefix}" && find "$category" \( -type f -o -type d \) 2>/dev/null | sort | while IFS= read -r path; do
      # Skip the category root dir itself
      [[ "$path" == "$category" ]] && continue
      # Count depth: slashes in the relative path from category
      local rel="${path#$category/}"
      local depth=$(($(echo "$rel" | tr -cd '/' | wc -c) + 1))
      local indent=""
      for ((i=0; i<depth; i++)); do indent="${indent}  "; done
      if [[ -d "$tmpdir/${prefix}$path" ]]; then
        echo "    ${indent}$(basename "$path")/"
      else
        echo "    ${indent}$(basename "$path")"
      fi
    done)
  fi

  rm -rf "$tmpdir"
}

# Show content of a flat text file from the archive.
# $1: merged tar.gz path
# $2: top-level prefix (e.g. "backup-2026-06-20-153325/")
# $3: filename within archive (e.g. "Brewfile")
show_text_file() {
  local merged="$1"
  local prefix="$2"
  local file="$3"

  local content
  content=$(tar -xzf "$merged" -O "${prefix}${file}" 2>/dev/null || true)

  if [[ -z "$content" ]]; then
    echo "    (empty)"
    return
  fi

  local count
  count=$(echo "$content" | wc -l | tr -d ' ')

  if [[ "$count" -le 20 ]]; then
    echo "$content" | while IFS= read -r line; do
      echo "    $line"
    done
  else
    echo "$content" | head -20 | while IFS= read -r line; do
      echo "    $line"
    done
    echo "    ... ($((count - 20)) more lines)"
  fi
}

main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <backup.zip.part-aa>"
    echo "Example: $0 ~/Desktop/backup-2026-06-20-153325.zip.part-aa"
    exit 1
  fi

  local target="$1"

  if [[ ! -f "$target" ]]; then
    error "File not found: $target"
  fi

  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  validate-backup — $(basename "$target")"
  echo "═══════════════════════════════════════════════════════"
  echo ""

  # Detect all parts
  local base="${target%%.zip.part-*}"
  local parts=()
  for p in "${base}.zip.part-"*; do
    [[ -f "$p" ]] || continue
    parts+=("$p")
  done

  if [[ ${#parts[@]} -eq 0 ]]; then
    error "No .zip.part-* files found for base: $base"
  fi

  info "Parts found: ${#parts[@]}"
  for p in "${parts[@]}"; do
    local sz
    sz=$(du -h "$p" 2>/dev/null | cut -f1)
    echo "    $(basename "$p")  ($sz)"
  done

  # Total size
  local total_size=0
  for p in "${parts[@]}"; do
    total_size=$((total_size + $(stat -f%z "$p" 2>/dev/null || echo 0)))
  done
  info "Total size: $(echo "scale=1; $total_size / 1048576" | bc -l) MB"

  # Reassemble and validate
  info "Reassembling parts..."
  local merged
  merged=$(mktemp -t validate-backup-merged-XXXXXX.tar.gz)
  cat "${parts[@]}" > "$merged"

  # Gzip integrity
  info "Checking gzip integrity..."
  if gzip -t "$merged" 2>/dev/null; then
    ok "gzip: valid"
  else
    error "gzip: CORRUPT — the archive is damaged"
  fi

  # Tar listing
  info "Reading archive contents..."
  local entries
  entries=$(tar -tzf "$merged" 2>/dev/null)
  local count
  count=$(echo "$entries" | wc -l | tr -d ' ')

  ok "tar: $count entries readable"

  # Ensure tree is available for the tree views below
  ensure_tree || true

  # Category summary
  echo ""
  echo "── Contents ──"
  for cat in Brewfile apps.txt fonts.txt projects.txt dotfiles/ claude/ Desktop/ Documents/ Downloads/ projects/; do
    if echo "$entries" | grep -qF "$cat"; then
      ok "$cat"
    else
      echo "  - $cat"
    fi
  done

  # Check for common issues
  echo ""
  echo "── Checks ──"
  if [[ "$count" -lt 5 ]]; then
    warn "Low entry count ($count) — backup may be incomplete"
  else
    ok "Entry count looks normal ($count)"
  fi

  if echo "$entries" | grep -q '^backup-'; then
    ok "Top-level directory present"
  else
    warn "No backup-* top-level directory — structure may be wrong"
  fi

  # Extract top-level prefix (e.g. "backup-2026-06-20-153325/")
  local prefix
  prefix=$(echo "$entries" | head -1 | cut -d/ -f1)"/"

  # ── Tree views ──
  echo ""
  echo "── Claude config ──"
  if echo "$entries" | grep -qF "${prefix}claude/"; then
    tree_view "$merged" "$prefix" "claude"
  else
    echo "    (not included)"
  fi

  echo ""
  echo "── Dotfiles ──"
  if echo "$entries" | grep -qF "${prefix}dotfiles/"; then
    tree_view "$merged" "$prefix" "dotfiles"
  else
    echo "    (not included)"
  fi

  echo ""
  echo "── Applications (apps.txt) ──"
  if echo "$entries" | grep -qF "apps.txt"; then
    show_text_file "$merged" "$prefix" "apps.txt"
  else
    echo "    (not included)"
  fi

  echo ""
  echo "── Brew apps (Brewfile) ──"
  if echo "$entries" | grep -qF "Brewfile"; then
    show_text_file "$merged" "$prefix" "Brewfile"
  else
    echo "    (not included)"
  fi

  rm -f "$merged"

  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Validation complete."
  echo "═══════════════════════════════════════════════════════"
}

main "$@"
