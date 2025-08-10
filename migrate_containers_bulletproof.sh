#!/usr/bin/env bash
set -euo pipefail

# Dynamic repository detection with absolute paths
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
REPO_ROOT_ABS="$(cd "$REPO_ROOT" && pwd)"
SRC_ROOT="$REPO_ROOT/src"
SRC_ROOT_ABS="$(cd "$SRC_ROOT" && pwd)"

echo "Repository root: $REPO_ROOT_ABS"
echo "Source root: $SRC_ROOT_ABS"
echo "Migrating container types to use aliases..."

# Robust file discovery without globstar
mapfile -t files < <(find "$SRC_ROOT" -type f -name '*.zig' -print0 | \
    xargs -0 -r grep -l -E 'std\.(ArrayList|AutoHashMap|ArrayHashMap|StringHashMap|BufSet)' 2>/dev/null || true)

if [[ ${#files[@]} -eq 0 ]]; then
    echo "No files to migrate"
    exit 0
fi

echo "Found ${#files[@]} files to process"
echo ""

total_replaced=0
files_changed=0

for file in "${files[@]}"; do
    # Skip containers.zig itself
    if [[ "$file" == *"containers.zig" ]]; then
        continue
    fi
    
    echo "Processing: $file"
    
    # Check for existing containers import and detect alias name
    existing_alias=""
    if grep -qE 'const[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*@import\(".*containers\.zig"\)' "$file" 2>/dev/null; then
        # Extract the existing alias name
        existing_alias=$(grep -E 'const[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*@import\(".*containers\.zig"\)' "$file" | \
                        sed -E 's/^[[:space:]]*const[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=.*/\1/' | head -1)
        echo "  Found existing import with alias: $existing_alias"
    fi
    
    # Determine alias to use
    if [[ -n "$existing_alias" ]]; then
        alias_name="$existing_alias"
    else
        # Check if 'containers' is already used for something else
        if grep -qE '^[[:space:]]*const[[:space:]]+containers[[:space:]]*=' "$file" 2>/dev/null; then
            # Fall back to 'cont' if 'containers' is taken
            alias_name="cont"
            echo "  Using alias 'cont' (containers is taken)"
        else
            alias_name="containers"
            echo "  Using alias 'containers'"
        fi
    fi
    
    # Check if file uses any container types
    uses_containers=0
    if grep -qE "std\.(ArrayList|AutoHashMap|ArrayHashMap|StringHashMap|BufSet)" "$file"; then
        uses_containers=1
    fi
    
    if [[ $uses_containers -eq 0 ]]; then
        echo "  No containers to migrate"
        continue
    fi
    
    # Count before replacement
    before_count=$(grep -cE "std\.(ArrayList|AutoHashMap|ArrayHashMap|StringHashMap|BufSet)" "$file" 2>/dev/null || echo 0)
    before_count=${before_count%%$'\n'*}  # Remove any newlines
    
    # Create backup
    cp "$file" "$file.container_bak"
    
    # Add import if needed (only if no existing import)
    if [[ -z "$existing_alias" ]]; then
        # Calculate relative path with absolute paths
        file_dir_abs="$(cd "$(dirname "$file")" && pwd)"
        import_path=""
        
        if [[ "$file_dir_abs" == "$SRC_ROOT_ABS"* ]]; then
            # File is under src/
            current="$file_dir_abs"
            while [[ "$current" != "$SRC_ROOT_ABS" ]]; do
                import_path="../$import_path"
                current="$(dirname "$current")"
            done
            import_path="${import_path}utils/containers.zig"
        else
            # File outside src/ - use REPO_ROOT_ABS
            current="$file_dir_abs"
            while [[ "$current" != "$REPO_ROOT_ABS" ]]; do
                import_path="../$import_path"
                current="$(dirname "$current")"
            done
            import_path="${import_path}src/utils/containers.zig"
        fi
        
        echo "  Adding import: const $alias_name = @import(\"$import_path\");"
        
        # Insert import after std import with fixed AWK grouping
        awk -v import_path="$import_path" -v alias="$alias_name" '
        BEGIN { 
            added = 0
            line_count = 0
        }
        {
            lines[++line_count] = $0
            
            # Try to insert after std import
            if (!added && $0 ~ /^[[:space:]]*const[[:space:]]+std[[:space:]]*=[[:space:]]*@import\("std"\)/) {
                lines[++line_count] = "const " alias " = @import(\"" import_path "\");"
                added = 1
            }
        }
        END {
            if (!added) {
                # Prepend after header comments - FIXED grouping
                in_header = 1
                for (i = 1; i <= line_count; i++) {
                    # Correct grouping: NOT (comment OR blank)
                    if (in_header && !(lines[i] ~ /^[[:space:]]*\/\// || lines[i] ~ /^[[:space:]]*$/)) {
                        print "const " alias " = @import(\"" import_path "\");"
                        in_header = 0
                    }
                    print lines[i]
                }
            } else {
                for (i = 1; i <= line_count; i++) {
                    print lines[i]
                }
            }
        }
        ' "$file" > "$file.tmp"
        mv "$file.tmp" "$file"
    fi
    
    # Replace container types with portable sed (keep .init explicit!)
    sed -i.sed_bak \
        -e "s/std\.ArrayList/${alias_name}.List/g" \
        -e "s/std\.AutoHashMap/${alias_name}.AutoMap/g" \
        -e "s/std\.ArrayHashMap/${alias_name}.ArrayMap/g" \
        -e "s/std\.StringHashMap/${alias_name}.StrMap/g" \
        -e "s/std\.BufSet/${alias_name}.StrSet/g" \
        "$file"
    
    # Remove sed backup after success
    rm -f "$file.sed_bak"
    
    # Count after replacement
    after_count=$(grep -cE "std\.(ArrayList|AutoHashMap|ArrayHashMap|StringHashMap|BufSet)" "$file" 2>/dev/null || echo 0)
    after_count=${after_count%%$'\n'*}  # Remove any newlines
    replaced=$((before_count - after_count))
    
    if [[ $replaced -gt 0 ]]; then
        echo "  Replaced: $replaced container references"
        total_replaced=$((total_replaced + replaced))
        files_changed=$((files_changed + 1))
    else
        echo "  No changes made"
        # Restore from backup if no changes
        mv "$file.container_bak" "$file"
    fi
    
    # Check for any remaining std. container references (with -E flag)
    if [[ $after_count -gt 0 ]]; then
        echo "  WARNING: $after_count std. container references remain"
        grep -En 'std\.(ArrayList|AutoHashMap|ArrayHashMap|StringHashMap|BufSet)' "$file" | head -3
    fi
    
    echo ""
done

# Summary
echo "========================================"
echo "Migration Complete"
echo "Files processed: ${#files[@]}"
echo "Files changed: $files_changed"
echo "Total replacements: $total_replaced"

# Check for any remaining patterns globally (with -E flag)
remaining=$(find "$SRC_ROOT" -type f -name '*.zig' -print0 | \
    xargs -0 -r grep -E 'std\.(ArrayList|AutoHashMap|ArrayHashMap|StringHashMap|BufSet)' 2>/dev/null | \
    grep -v containers.zig | grep -v '.container_bak' | wc -l || echo 0)
remaining=${remaining%%$'\n'*}  # Remove any newlines

if [[ $remaining -gt 0 ]]; then
    echo ""
    echo "WARNING: $remaining container references still using std prefix"
    echo "These may be in comments, strings, or files that weren't processed"
    echo ""
    echo "To see them:"
    echo "  find src -name '*.zig' | xargs grep -En 'std\\.(ArrayList|AutoHashMap|ArrayHashMap|StringHashMap|BufSet)' | grep -v containers.zig"
fi

echo ""
echo "Next steps:"
echo "1. Build: zig build"
echo "2. Test: zig build test"
echo "3. If successful, remove backups: find . -name '*.container_bak' -delete"
echo "4. If failed, restore: for f in \$(find . -name '*.container_bak'); do mv \"\$f\" \"\${f%.container_bak}\"; done"