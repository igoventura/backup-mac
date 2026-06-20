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

  rm -f "$merged"

  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Validation complete."
  echo "═══════════════════════════════════════════════════════"
}

main "$@"
