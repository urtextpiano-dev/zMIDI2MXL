#!/usr/bin/env bash
set -euo pipefail

# Detect repository root
REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SRC_ROOT="$REPO_ROOT/src"
TEST_UTILS="$SRC_ROOT/test_utils.zig"

if [[ ! -f "$TEST_UTILS" ]]; then
    echo "Error: test_utils.zig not found at $TEST_UTILS"
    exit 1
fi

echo "Repository root: $REPO_ROOT"
echo "Source root: $SRC_ROOT"
echo "Searching for test files..."

# Find all .zig files with testing patterns
mapfile -t test_files < <(find "$REPO_ROOT" -name "*.zig" -type f | xargs grep -l -E "(std\.testing\.|const.*=.*std\.testing)" 2>/dev/null || true)

if [[ ${#test_files[@]} -eq 0 ]]; then
    echo "No test files found"
    exit 0
fi

echo "Found ${#test_files[@]} files with test patterns"
echo ""

total_migrated=0
files_changed=0

for file in "${test_files[@]}"; do
    # Skip test_utils.zig itself
    if [[ "$file" == *"test_utils.zig" ]]; then
        continue
    fi
    
    # Generic relative path calculation
    file_dir="$(dirname "$file")"
    
    # Calculate relative path to test_utils.zig
    # Use realpath to get canonical paths then calculate relative
    file_canonical="$(realpath "$file_dir")"
    test_utils_canonical="$(realpath "$SRC_ROOT")"
    
    # Count directory levels from file to src
    relative_path=""
    current="$file_canonical"
    
    # Go up until we find a common ancestor with src
    while [[ "$current" != "/" && ! "$test_utils_canonical" == "$current"* ]]; do
        relative_path="../$relative_path"
        current="$(dirname "$current")"
    done
    
    # Now add the path down to test_utils.zig
    if [[ "$test_utils_canonical" == "$file_canonical"* ]]; then
        # File is inside src directory
        subpath="${test_utils_canonical#$file_canonical}"
        subpath="${subpath#/}"
        if [[ -z "$subpath" ]]; then
            import_path="test_utils.zig"
        else
            import_path="${subpath}/test_utils.zig"
        fi
    else
        # File is outside src directory
        subpath="${test_utils_canonical#$current}"
        subpath="${subpath#/}"
        import_path="${relative_path}${subpath}/test_utils.zig"
    fi
    
    echo "Processing: $file"
    echo "  Import path: $import_path"
    
    # Check if already has test_utils import
    if grep -qE '@import\(".*test_utils\.zig"\)' "$file" 2>/dev/null; then
        echo "  Already has test_utils import, skipping import addition"
        continue
    fi
    
    # Create backup
    cp "$file" "$file.migrate_bak"
    
    # Count before
    before_count=$(grep -cE "(std\.testing\.|testing\.)" "$file" 2>/dev/null || echo 0)
    
    # Step 1: Add import after std import (flexible regex)
    awk -v add="const t = @import(\"${import_path}\");" '
    BEGIN { added=0 }
    # Match: const std = @import("std"); with flexible spacing
    added==0 && /^[[:space:]]*const[[:space:]]+std[[:space:]]*=[[:space:]]*@import\("std"\);/ {
        print
        print add
        added=1
        next
    }
    { print }
    END {
        # If we never added it and file needs it, add at top after initial comments
        if (added==0) {
            # This would need more complex logic to prepend properly
            # For now, rely on the awk pattern matching
        }
    }
    ' "$file" > "$file.tmp1" && mv "$file.tmp1" "$file"
    
    # Step 2: Replace patterns and detect/remove alias
    awk '
    BEGIN { 
        alias=""
    }
    
    # Detect and remove testing alias line
    /^[[:space:]]*const[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*std\.testing[[:space:]]*;/ {
        # Extract the alias name
        match($0, /const[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=/, m)
        if (m[1] != "") {
            alias = m[1]
            next  # Skip this line (remove it)
        }
    }
    
    {
        line = $0
        
        # Replace std.testing.* patterns
        gsub(/std\.testing\.expectEqual/, "t.expectEq", line)
        gsub(/std\.testing\.expectEqualStrings/, "t.expectStrEq", line)
        gsub(/std\.testing\.expectEqualSlices/, "t.expectSliceEq", line)
        gsub(/std\.testing\.expectError/, "t.expectErr", line)
        gsub(/std\.testing\.expect/, "t.expect", line)
        gsub(/std\.testing\.allocator/, "t.allocator", line)
        
        # If we found an alias, replace those patterns too
        if (alias != "") {
            # Build the patterns dynamically
            pat_eq = alias "\\.expectEqual"
            pat_str = alias "\\.expectEqualStrings"
            pat_slice = alias "\\.expectEqualSlices"
            pat_err = alias "\\.expectError"
            pat_exp = alias "\\.expect"
            pat_alloc = alias "\\.allocator"
            
            gsub(pat_eq, "t.expectEq", line)
            gsub(pat_str, "t.expectStrEq", line)
            gsub(pat_slice, "t.expectSliceEq", line)
            gsub(pat_err, "t.expectErr", line)
            gsub(pat_exp, "t.expect", line)
            gsub(pat_alloc, "t.allocator", line)
        }
        
        print line
    }
    ' "$file" > "$file.tmp2" && mv "$file.tmp2" "$file"
    
    # Count after
    after_count=$(grep -cE "t\." "$file" 2>/dev/null || echo 0)
    remaining=$(grep -cE "(std\.testing\.|testing\.)" "$file" 2>/dev/null || echo 0)
    migrated=$((before_count - remaining))
    
    if [[ $migrated -gt 0 ]]; then
        echo "  Migrated: $migrated patterns"
        echo "  Using t.*: $after_count"
        echo "  Remaining: $remaining"
        total_migrated=$((total_migrated + migrated))
        files_changed=$((files_changed + 1))
    else
        echo "  No changes made"
        # Remove backup if no changes
        rm "$file.migrate_bak"
    fi
    echo ""
done

echo "========================================"
echo "Migration Summary"
echo "Files changed: $files_changed"
echo "Total patterns migrated: $total_migrated"
echo ""

# Show remaining patterns for manual review
remaining_files=$(find "$REPO_ROOT" -name "*.zig" -type f | xargs grep -l "std\\.testing\\." 2>/dev/null | grep -v test_utils.zig | wc -l)
if [[ $remaining_files -gt 0 ]]; then
    echo "Files still containing std.testing patterns: $remaining_files"
    echo "Run this to see them:"
    echo "  grep -r 'std\\.testing\\.' --include='*.zig' . | grep -v test_utils.zig | grep -v '.migrate_bak'"
fi

echo ""
echo "Next steps:"
echo "1. Run: zig build test"
echo "2. If tests pass, remove backups: find . -name '*.migrate_bak' -delete"
echo "3. If tests fail, revert: for f in \$(find . -name '*.migrate_bak'); do mv \"\$f\" \"\${f%.migrate_bak}\"; done"