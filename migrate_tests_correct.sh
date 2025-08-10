#!/usr/bin/env bash
set -euo pipefail

# Detect repository root
REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SRC_ROOT="$REPO_ROOT/src"
TEST_UTILS="$SRC_ROOT/test_utils.zig"

# Verify test_utils.zig exists
if [[ ! -f "$TEST_UTILS" ]]; then
    echo "Error: test_utils.zig not found at $TEST_UTILS"
    exit 1
fi

# Get absolute paths for reliable comparison
REPO_ROOT_ABS="$(cd "$REPO_ROOT" && pwd)"
SRC_ROOT_ABS="$(cd "$SRC_ROOT" && pwd)"

echo "Repository root: $REPO_ROOT_ABS"
echo "Source root: $SRC_ROOT_ABS"
echo ""

# Discover files robustly - catch BOTH std.testing. AND alias patterns
declare -a files=()
while IFS= read -r -d '' f; do
    if grep -Eq 'std\.testing\.|^[[:space:]]*const[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*std\.testing[[:space:]]*;' "$f"; then
        # Skip test_utils.zig itself
        if [[ "$f" != *"test_utils.zig" ]]; then
            files+=("$f")
        fi
    fi
done < <(find "$REPO_ROOT_ABS" -type f -name '*.zig' -print0)

if [[ ${#files[@]} -eq 0 ]]; then
    echo "No test files found needing migration"
    exit 0
fi

echo "Found ${#files[@]} files with test patterns to migrate"
echo ""

total_migrated=0
files_changed=0
files_skipped=0

for file in "${files[@]}"; do
    echo "Processing: $file"
    
    # Get absolute path of file directory
    file_abs="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
    file_dir_abs="$(dirname "$file_abs")"
    
    # Compute generic import path by comparing absolute paths
    import_path=""
    if [[ "$file_dir_abs" == "$SRC_ROOT_ABS"* ]]; then
        # File is under src/ - walk up to SRC_ROOT
        current="$file_dir_abs"
        while [[ "$current" != "$SRC_ROOT_ABS" ]]; do
            import_path="../$import_path"
            current="$(dirname "$current")"
        done
        import_path="${import_path}test_utils.zig"
    else
        # File is outside src/ - walk up to REPO_ROOT then down to src/test_utils.zig
        current="$file_dir_abs"
        while [[ "$current" != "$REPO_ROOT_ABS" ]]; do
            import_path="../$import_path"
            current="$(dirname "$current")"
        done
        import_path="${import_path}src/test_utils.zig"
    fi
    
    echo "  Import path: $import_path"
    
    # Pre-compute if file already has test_utils import
    if grep -qE '@import\(["\x27].*test_utils\.zig["\x27]\)' "$file" 2>/dev/null; then
        has_import=1
        echo "  Already has test_utils import"
    else
        has_import=0
    fi
    
    # Detect if an alias is used
    alias_name=""
    if grep -qE '^[[:space:]]*const[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*std\.testing[[:space:]]*;' "$file"; then
        alias_name=$(grep -E '^[[:space:]]*const[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*std\.testing[[:space:]]*;' "$file" | sed -E 's/^[[:space:]]*const[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=.*/\1/' | head -1)
        echo "  Found alias: $alias_name"
    fi
    
    # Count before migration (include alias if present)
    if [[ -n "$alias_name" ]]; then
        before_count=$(grep -cE "(std\.testing\.|${alias_name}\.)" "$file" 2>/dev/null || echo 0)
    else
        before_count=$(grep -cE 'std\.testing\.' "$file" 2>/dev/null || echo 0)
    fi
    
    if [[ $before_count -eq 0 ]]; then
        echo "  No patterns to migrate"
        files_skipped=$((files_skipped + 1))
        continue
    fi
    
    # Create backup
    cp "$file" "$file.bak"
    
    # Step 1: Add import idempotently with pre-computed need
    awk -v import_path="$import_path" -v need_import="$((1-has_import))" '
    BEGIN { 
        needs_import = need_import
        added = 0
        in_header = 1
    }
    
    # Defensive check - should not be needed with pre-compute
    /@import\(["\x27].*test_utils\.zig["\x27]\)/ { 
        needs_import = 0 
    }
    
    # Try to insert after std import (with semicolon in regex)
    needs_import && !added && /^[[:space:]]*const[[:space:]]+std[[:space:]]*=[[:space:]]*@import\("std"\)[[:space:]]*;/ {
        print
        print "const t = @import(\"" import_path "\");"
        added = 1
        next
    }
    
    # Fixed header detection - proper grouping
    in_header && !(/^[[:space:]]*\/\/|^[[:space:]]*$/) {
        if (needs_import && !added) {
            print "const t = @import(\"" import_path "\");"
            added = 1
        }
        in_header = 0
    }
    
    { print }
    ' "$file" > "$file.tmp1"
    
    # Step 2: Detect alias, comment it out, and replace patterns (NO ALLOCATOR!)
    awk -v alias_name="$alias_name" '
    BEGIN { 
        alias = alias_name
    }
    
    # Comment out testing alias line (keep for visibility)
    /^[[:space:]]*const[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*std\.testing[[:space:]]*;/ {
        print "// Removed: " $0
        next
    }
    
    {
        line = $0
        
        # CRITICAL: Skip ALL lines with allocator - do NOT touch!
        if (index(line, "allocator") > 0) {
            print line
            next
        }
        
        # Replace std.testing.* patterns (NO allocator - we skip those lines above)
        gsub(/std\.testing\.expectEqual/, "t.expectEq", line)
        gsub(/std\.testing\.expectEqualStrings/, "t.expectStrEq", line)
        gsub(/std\.testing\.expectEqualSlices/, "t.expectSliceEq", line)
        gsub(/std\.testing\.expectError/, "t.expectErr", line)
        gsub(/std\.testing\.expectApproxEqAbs/, "t.expectApproxAbs", line)
        gsub(/std\.testing\.expectApproxEqRel/, "t.expectApproxRel", line)
        gsub(/std\.testing\.expect/, "t.expect", line)
        # NO gsub for allocator - removed completely!
        
        # If alias exists, replace those patterns too (NO allocator)
        if (alias != "") {
            gsub(alias "\\.expectEqual", "t.expectEq", line)
            gsub(alias "\\.expectEqualStrings", "t.expectStrEq", line)
            gsub(alias "\\.expectEqualSlices", "t.expectSliceEq", line)
            gsub(alias "\\.expectError", "t.expectErr", line)
            gsub(alias "\\.expectApproxEqAbs", "t.expectApproxAbs", line)
            gsub(alias "\\.expectApproxEqRel", "t.expectApproxRel", line)
            gsub(alias "\\.expect", "t.expect", line)
            # NO gsub for alias.allocator - removed completely!
        }
        
        print line
    }
    ' "$file.tmp1" > "$file.tmp2"
    
    # Step 3: Apply special pattern improvements (skip allocator lines)
    sed -i.sed_bak \
        -e '/allocator/!s/t\.expect\([[:space:]]*![[:space:]]*([^)]+)\)/t.expectFalse(\1)/g' \
        -e '/allocator/!s/t\.expect\([[:space:]]*([^)]+)[[:space:]]*==[[:space:]]*null[[:space:]]*\)/t.expectNull(\1)/g' \
        -e '/allocator/!s/t\.expect\([[:space:]]*([^)]+)[[:space:]]*!=[[:space:]]*null[[:space:]]*\)/t.expectNotNull(\1)/g' \
        "$file.tmp2"
    
    # Move result into place
    mv "$file.tmp2" "$file"
    rm -f "$file.tmp1" "$file.sed_bak"
    
    # Count after migration (dynamic with alias)
    if [[ -n "$alias_name" ]]; then
        after_count=$(grep -cE "(std\.testing\.|${alias_name}\.)" "$file" | grep -v '^//' 2>/dev/null || echo 0)
    else
        after_count=$(grep -cE 'std\.testing\.' "$file" | grep -v '^//' 2>/dev/null || echo 0)
    fi
    migrated=$((before_count - after_count))
    
    if [[ $migrated -gt 0 ]]; then
        echo "  Migrated: $migrated patterns"
        echo "  Remaining: $after_count (allocator references only)"
        total_migrated=$((total_migrated + migrated))
        files_changed=$((files_changed + 1))
        
        # Show what's left (excluding comments)
        if [[ $after_count -gt 0 ]]; then
            echo "  Sample remaining patterns:"
            if [[ -n "$alias_name" ]]; then
                grep -E "(std\.testing\.|${alias_name}\.)" "$file" | grep -v '^//' | head -2
            else
                grep -E 'std\.testing\.' "$file" | grep -v '^//' | head -2
            fi
        fi
    else
        echo "  No patterns migrated"
        # Restore from backup if no changes
        mv "$file.bak" "$file"
    fi
    
    echo ""
done

# Summary statistics
echo "========================================"
echo "Migration Complete"
echo "Files processed: ${#files[@]}"
echo "Files changed: $files_changed"
echo "Files skipped: $files_skipped"
echo "Total patterns migrated: $total_migrated"
echo ""

# Fixed remaining count calculation
remaining_total=$(
    find "$REPO_ROOT_ABS" -type f -name '*.zig' ! -name 'test_utils.zig' -print0 \
    | xargs -0 -r grep -c 'std\.testing\.' 2>/dev/null \
    | paste -sd+ - \
    | bc 2>/dev/null || echo 0
)

if [[ $remaining_total -gt 0 ]]; then
    echo "Patterns still remaining: $remaining_total"
    echo "(These are allocator references - we intentionally don't touch those)"
    echo ""
    echo "To see remaining patterns:"
    echo "  grep -r 'std\\.testing\\.' --include='*.zig' . | grep -v test_utils.zig | grep -v '.bak' | grep -v '^//'"
else
    echo "All non-allocator patterns successfully migrated!"
fi

echo ""
echo "Next steps:"
echo "1. Run tests: zig build test"
echo "2. If successful, remove backups: find . -name '*.bak' -delete"
echo "3. If failed, restore: for f in \$(find . -name '*.bak'); do mv \"\$f\" \"\${f%.bak}\"; done"