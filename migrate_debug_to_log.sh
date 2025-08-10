#!/usr/bin/env bash
set -euo pipefail

# Detect src root (arg > git > script-dir/src)
SRC_ROOT="${1:-}"
if [[ -z "$SRC_ROOT" ]]; then
  SRC_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -z "$SRC_ROOT" ]] && SRC_ROOT="$(cd "$(dirname "$0")/src" && pwd)" || SRC_ROOT="$SRC_ROOT/src"
fi
[[ -d "$SRC_ROOT" ]] || { echo "src not found: $SRC_ROOT"; exit 1; }

# Find .zig files containing std.debug.print
mapfile -t files < <(grep -RIl --include='*.zig' 'std\.debug\.print' "$SRC_ROOT" || true)
(( ${#files[@]} )) || { echo "No files with std.debug.print found"; exit 0; }

echo "Found ${#files[@]} files:"
printf '  - %s\n' "${files[@]}"
echo

for file in "${files[@]}"; do
  dir="$(dirname "$file")"

  # Compute relative import path to utils/log.zig from $dir
  rel=""
  up="$dir"
  while [[ "$up" != "$SRC_ROOT" && "$up" == "$SRC_ROOT"* ]]; do
    rel+="../"
    up="${up%/*}"
  done
  import_path="${rel}utils/log.zig"

  echo "Processing: $file"
  # Insert import once, right after std import (backup via .bak, portable on BSD/macOS)
  if ! grep -qE '@import\("(\.\./)*utils/log\.zig"\)' "$file"; then
    awk -v add="const log = @import(\"${import_path}\");" '
      BEGIN { done=0 }
      done==0 && /^const[[:space:]]+std[[:space:]]*=[[:space:]]*@import\("std"\);[[:space:]]*$/ {
        print; print add; done=1; next
      }
      { print }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  fi

  before=$(grep -c 'std\.debug\.print' "$file" || true)

  # Rewrites (with .bak backups). Keep them focused and stable:
  # 1) FIX-002 -> tag
  sed -i.bak -E \
    's/std\.debug\.print\("DEBUG FIX-002: \[([^]]+)\] - ([^"]*)\\n",[[:space:]]*(\.[^)]*)\);/log.tag("FIX-002:\1", "\2", \3);/g' "$file"

  # 2) "Module: message\n", args -> debug
  sed -i.bak -E \
    's/std\.debug\.print\("([^":]+): ([^"]*)\\n",[[:space:]]*(\.[^)]*)\);/log.debug("\1: \2", \3);/g' "$file"

  # 3) Generic: "msg\n", args -> debug
  sed -i.bak -E \
    's/std\.debug\.print\("([^"]*)\\n",[[:space:]]*(\.[^)]*)\);/log.debug("\1", \2);/g' "$file"

  # 4) Optional: simple no-args form "msg\n", .{} -> debug
  sed -i.bak -E \
    's/std\.debug\.print\("([^"]*)\\n",[[:space:]]*\.\{\}\);/log.debug("\1", .{});/g' "$file"

  after=$(grep -c 'std\.debug\.print' "$file" || true)
  echo "  Replaced $((before - after)) calls; remaining: $after"
  (( after > 0 )) && grep -n 'std\.debug\.print' "$file" | head -3
  echo
done

# Summary
remaining=$(grep -RIch --include='*.zig' 'std\.debug\.print' "$SRC_ROOT" | paste -sd+ - | bc)
echo "========================================"
echo "Migration complete"
echo "Files processed: ${#files[@]}"
echo "Remaining std.debug.print calls: ${remaining}"
echo "Backups: '*.bak' next to each file; remove with:"
echo "  find \"$SRC_ROOT\" -name '*.bak' -delete"