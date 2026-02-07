#!/usr/bin/env bash
#
# find-duplicates.sh
# Finds potential duplicate files based on:
#   - Common duplicate suffixes (e.g., "(1)", " - Copy", "_copy")
#   - Matching file sizes
#   - Relative path distance
#
# Usage: ./find-duplicates.sh [directory] [options]
#   -d, --dir DIR          Directory to scan (default: current directory)
#   -m, --min-size N       Minimum file size in bytes (default: 1)
#   -M, --max-distance N   Only report duplicates with path distance <= N
#   -h, --hash             Also verify with MD5 hash (slower but more accurate)
#   -j, --json             Output as JSON
#   -D, --delete-distance N  Auto-delete duplicates with path distance < N
#   -f, --force            Skip confirmation prompt when deleting
#   --dry-run              Show what would be deleted without deleting
#   -v, --verbose          Show extra debug info (temp dir usage, etc.)
#   -t, --temp-dir DIR     Use custom temp directory (default: system temp)
#   -e, --exclude PATTERN  Exclude files matching glob pattern (can repeat)
#   --help                 Show this help message

set -euo pipefail

# --- Configuration ---
TARGET_DIR="."
MIN_SIZE=1
MAX_DISTANCE=-1     # -1 = no limit
USE_HASH=false
OUTPUT_JSON=false
DELETE_DISTANCE=-1  # -1 = disabled
FORCE_DELETE=false
DRY_RUN=false
VERBOSE=false
TEMP_DIR=""
IS_LINUX=false
[[ "$(uname -s)" == "Linux" ]] && IS_LINUX=true

# --- Helper Functions ---

print_usage() {
    sed -n '2,22p' "$0" | sed 's/^#\s\?//'
}

CUSTOM_TEMP=""
EXCLUDE_PATTERNS=()

log_info() {
    [[ "$OUTPUT_JSON" == false ]] && echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_verbose() {
    [[ "$VERBOSE" == true ]] && echo "[DEBUG] $*" >&2 || true
}

show_temp_usage() {
    if [[ "$VERBOSE" == true && -n "$TEMP_DIR" ]]; then
        local usage=$(du -sh "$TEMP_DIR" 2>/dev/null | cut -f1)
        local files=$(find "$TEMP_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
        log_verbose "Temp usage: $usage ($files files)"
    fi
}

# Timing functions
get_timestamp() {
    if [[ "$IS_LINUX" == true ]]; then
        date +%s.%N
    else
        # macOS doesn't support %N, use python or perl as fallback
        python3 -c 'import time; print(f"{time.time():.3f}")' 2>/dev/null || date +%s
    fi
}

format_duration() {
    local seconds="$1"
    local mins secs
    
    # Handle decimal seconds
    if [[ "$seconds" == *.* ]]; then
        local int_part="${seconds%.*}"
        local dec_part="${seconds#*.}"
        if (( int_part >= 60 )); then
            mins=$((int_part / 60))
            secs=$((int_part % 60))
            printf "%dm %d.%ss" "$mins" "$secs" "${dec_part:0:1}"
        else
            printf "%s.%ss" "$int_part" "${dec_part:0:1}"
        fi
    else
        if (( seconds >= 60 )); then
            mins=$((seconds / 60))
            secs=$((seconds % 60))
            printf "%dm %ds" "$mins" "$secs"
        else
            printf "%ds" "$seconds"
        fi
    fi
}

calc_duration() {
    local start="$1"
    local end="$2"
    awk "BEGIN { printf \"%.1f\", $end - $start }"
}

cleanup() {
    [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Check if filename has a duplicate suffix
has_dup_suffix() {
    local filename="$1"
    local name="${filename%.*}"
    
    # Check each duplicate pattern
    echo "$name" | grep -qE '(\s*\([0-9]+\)|\s*-\s*[Cc]opy|_copy|\s+copy|_[0-9]+|-[0-9]+)$'
}

# Strip duplicate suffixes from filename to get base name (used in Phase 2)
get_base_name() {
    local filename="$1"
    local name="${filename%.*}"
    local ext="${filename##*.}"
    
    [[ "$filename" == "$name" ]] && ext=""
    
    # Combined pattern removal
    name=$(printf '%s' "$name" | sed -E 's/[[:space:]]*(\([0-9]+\)|-[[:space:]]*[Cc]opy|_copy|[[:space:]]+copy|_[0-9]+|-[0-9]+)$//')
    name="${name%"${name##*[![:space:]]}"}"  # trim trailing
    name="${name#"${name%%[![:space:]]*}"}"  # trim leading
    
    [[ -n "$ext" && "$filename" != "$name" ]] && echo "${name}.${ext}" || echo "$name"
}

# Get file size (cross-platform)
get_size() {
    local file="$1"
    if [[ "$OSTYPE" == darwin* ]]; then
        stat -f%z "$file" 2>/dev/null || echo 0
    else
        stat -c%s "$file" 2>/dev/null || echo 0
    fi
}

# Calculate path distance between two paths
calc_path_distance() {
    local path1="$1"
    local path2="$2"
    
    local dir1=$(dirname "$path1")
    local dir2=$(dirname "$path2")
    
    # Same directory = distance 0
    [[ "$dir1" == "$dir2" ]] && echo 0 && return
    
    # Normalize paths
    dir1=$(cd "$dir1" 2>/dev/null && pwd) || dir1="$dir1"
    dir2=$(cd "$dir2" 2>/dev/null && pwd) || dir2="$dir2"
    
    # Split into components
    local IFS='/'
    local -a parts1=($dir1)
    local -a parts2=($dir2)
    
    # Find common prefix length
    local common=0
    local max=${#parts1[@]}
    [[ ${#parts2[@]} -lt $max ]] && max=${#parts2[@]}
    
    for ((i=0; i<max; i++)); do
        if [[ "${parts1[$i]}" == "${parts2[$i]}" ]]; then
            common=$((common + 1))
        else
            break
        fi
    done
    
    # Distance = steps up + steps down
    local up=$((${#parts1[@]} - common))
    local down=$((${#parts2[@]} - common))
    
    echo $((up + down))
}

# Get file hash (MD5)
get_hash() {
    local file="$1"
    if command -v md5sum &>/dev/null; then
        md5sum "$file" | cut -d' ' -f1
    elif command -v md5 &>/dev/null; then
        md5 -q "$file"
    else
        echo "no-hash"
    fi
}

# URL-safe encoding for keys
encode_key() {
    echo "$1" | sed 's/[^a-zA-Z0-9._-]/_/g' | head -c 200
}

# --- Main Logic ---

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--dir)
                TARGET_DIR="$2"
                shift 2
                ;;
            -m|--min-size)
                MIN_SIZE="$2"
                shift 2
                ;;
            -M|--max-distance)
                MAX_DISTANCE="$2"
                shift 2
                ;;
            -h|--hash)
                USE_HASH=true
                shift
                ;;
            -j|--json)
                OUTPUT_JSON=true
                shift
                ;;
            -D|--delete-distance)
                DELETE_DISTANCE="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -t|--temp-dir)
                CUSTOM_TEMP="$2"
                shift 2
                ;;
            -e|--exclude)
                EXCLUDE_PATTERNS+=("$2")
                shift 2
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                [[ -d "$1" ]] && TARGET_DIR="$1"
                shift
                ;;
        esac
    done
}

main() {
    parse_args "$@"
    
    if [[ ! -d "$TARGET_DIR" ]]; then
        log_error "Directory not found: $TARGET_DIR"
        exit 1
    fi
    
    # Create temp directory for file-based grouping
    if [[ -n "$CUSTOM_TEMP" ]]; then
        mkdir -p "$CUSTOM_TEMP" || { log_error "Failed to create temp directory: $CUSTOM_TEMP"; exit 1; }
        TEMP_DIR=$(mktemp -d "$CUSTOM_TEMP/find-dups.XXXXXX") || { log_error "Failed to create temp directory in $CUSTOM_TEMP"; exit 1; }
    else
        TEMP_DIR=$(mktemp -d) || { log_error "Failed to create temp directory"; exit 1; }
    fi
    local groups_dir="$TEMP_DIR/groups"
    local results_file="$TEMP_DIR/results.txt"
    mkdir -p "$groups_dir"
    
    local total_start=$(get_timestamp)
    log_info "Scanning: $TARGET_DIR"
    log_verbose "Temp dir: $TEMP_DIR"
    log_verbose "Platform: $(uname -s) (IS_LINUX=$IS_LINUX)"
    [[ ${#EXCLUDE_PATTERNS[@]} -gt 0 ]] && log_info "Excluding: ${EXCLUDE_PATTERNS[*]}" || true
    log_info "Min size: $MIN_SIZE bytes"
    [[ $MAX_DISTANCE -ge 0 ]] && log_info "Max distance filter: <= $MAX_DISTANCE"
    [[ "$USE_HASH" == true ]] && log_info "Hash verification: enabled"
    [[ $DELETE_DISTANCE -ge 0 ]] && log_info "Delete distance threshold: < $DELETE_DISTANCE"
    [[ "$DRY_RUN" == true ]] && log_info "Dry run mode: enabled"
    
    # Phase 1: Index all files by base name + size (optimized with awk)
    local phase1_start=$(get_timestamp)
    log_info "Phase 1: Indexing files..."
    
    local index_file="$TEMP_DIR/index.txt"
    local count=0
    
    # Build find exclusion arguments
    local find_excludes=()
    if [[ ${#EXCLUDE_PATTERNS[@]} -gt 0 ]]; then
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            # Support both path patterns (containing /) and name patterns
            if [[ "$pattern" == */* ]]; then
                find_excludes+=(-not -path "$pattern")
            else
                find_excludes+=(-not -name "$pattern")
            fi
        done
    fi
    
    # Use find with -printf on Linux for speed, fall back to slower method on macOS
    if [[ "$IS_LINUX" == true ]]; then
        # Linux: get size and path in one find call
        find "$TARGET_DIR" -type f ${find_excludes[@]+"${find_excludes[@]}"} -printf '%s\t%p\n' 2>/dev/null
    else
        # macOS: use stat in batches via xargs for better performance
        find "$TARGET_DIR" -type f ${find_excludes[@]+"${find_excludes[@]}"} -print0 2>/dev/null | \
            xargs -0 -P4 -n100 stat -f '%z	%N' 2>/dev/null || true
    fi | awk -v min_size="$MIN_SIZE" -v groups_dir="$groups_dir" -v progress_interval=10000 '
    BEGIN { FS="\t"; count=0 }
    {
        size = $1
        path = $2
        if (size < min_size) next
        
        # Extract filename from path
        n = split(path, parts, "/")
        filename = parts[n]
        
        # Get extension
        ext = ""
        if (match(filename, /\.[^.]+$/)) {
            ext = substr(filename, RSTART)
            name = substr(filename, 1, RSTART - 1)
        } else {
            name = filename
        }
        
        # Remove duplicate suffixes
        gsub(/[[:space:]]*\([0-9]+\)$/, "", name)
        gsub(/[[:space:]]*-[[:space:]]*[Cc]opy$/, "", name)
        gsub(/_copy$/, "", name)
        gsub(/[[:space:]]+copy$/, "", name)
        gsub(/_[0-9]+$/, "", name)
        gsub(/-[0-9]+$/, "", name)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
        
        # Build base name with extension
        base_name = (ext != "") ? name ext : name
        
        # Build key and encode it
        key = base_name "___" size
        gsub(/[^a-zA-Z0-9._-]/, "_", key)
        key = substr(key, 1, 200)
        
        # Append path to group file and close immediately (avoid too many open files)
        outfile = groups_dir "/" key
        print path >> outfile
        close(outfile)
        
        count++
        if (count % progress_interval == 0) {
            print "[INFO]   Indexed " count " files..." > "/dev/stderr"
        }
    }
    END {
        print "[INFO]   Total indexed: " count " files" > "/dev/stderr"
        print count
    }
    ' > "$index_file"
    
    count=$(cat "$index_file" 2>/dev/null || echo 0)
    local phase1_end=$(get_timestamp)
    local phase1_dur=$(calc_duration "$phase1_start" "$phase1_end")
    log_info "  Phase 1 completed in $(format_duration "$phase1_dur")"
    show_temp_usage
    
    # Phase 2: Find duplicates (files in groups with >1 entry) - optimized with awk
    local phase2_start=$(get_timestamp)
    log_info "Phase 2: Finding duplicates..."
    
    local dup_count=0
    local multi_groups="$TEMP_DIR/multi_groups.txt"
    
    # Step 2a: Find groups with >1 file (bulk wc -l via xargs)
    log_verbose "  Finding groups with multiple files..."
    find "$groups_dir" -type f -print0 2>/dev/null | \
        xargs -0 -P4 wc -l 2>/dev/null | \
        awk '$1 >= 2 && $2 != "total" { print $2 }' > "$multi_groups"
    
    local group_count=$(wc -l < "$multi_groups" | tr -d ' ')
    log_info "  Found $group_count groups with potential duplicates"
    
    [[ "$group_count" -eq 0 ]] && { log_info "  Found 0 potential duplicate pairs"; return; }
    
    # Step 2b: Process groups and generate pairs using awk
    log_verbose "  Generating pairs..."
    
    # Read all multi-file groups and output pairs
    awk -v max_dist="$MAX_DISTANCE" -v results_file="$results_file" '
    function calc_distance(p1, p2,    d1, d2, parts1, parts2, n1, n2, common, i, max) {
        # Get directory parts
        n1 = split(p1, parts1, "/")
        n2 = split(p2, parts2, "/")
        # Remove filename (last component)
        n1--; n2--
        
        # Find common prefix
        max = (n1 < n2) ? n1 : n2
        common = 0
        for (i = 1; i <= max; i++) {
            if (parts1[i] == parts2[i]) common++
            else break
        }
        
        # Distance = ups + downs
        return (n1 - common) + (n2 - common)
    }
    
    function extract_size(filename,    parts, n, base, match_pos) {
        # Extract size from group filename: basename___size
        n = split(filename, parts, "/")
        base = parts[n]
        match_pos = match(base, /___[0-9]+$/)
        if (match_pos > 0) {
            return substr(base, match_pos + 3)
        }
        return 0
    }
    
    BEGIN {
        pair_count = 0
        groups_processed = 0
    }
    
    {
        group_file = $0
        size = extract_size(group_file)
        
        # Read all paths from this group
        n = 0
        while ((getline path < group_file) > 0) {
            n++
            paths[n] = path
        }
        close(group_file)
        
        # Generate all pairs
        for (i = 1; i < n; i++) {
            for (j = i + 1; j <= n; j++) {
                dist = calc_distance(paths[i], paths[j])
                
                # Skip if beyond max distance
                if (max_dist >= 0 && dist > max_dist) continue
                
                # Output: distance|size|file1|file2|hash_match
                print dist "|" size "|" paths[i] "|" paths[j] "|skipped" >> results_file
                pair_count++
            }
        }
        
        groups_processed++
        if (groups_processed % 10000 == 0) {
            print "[INFO]   Processed " groups_processed "/" NR " groups, " pair_count " pairs so far..." > "/dev/stderr"
        }
        
        # Clear paths array
        delete paths
    }
    
    END {
        print "[INFO]   Found " pair_count " potential duplicate pairs" > "/dev/stderr"
        print pair_count
    }
    ' "$multi_groups" > "$TEMP_DIR/pair_count.txt"
    
    dup_count=$(cat "$TEMP_DIR/pair_count.txt" 2>/dev/null || echo 0)
    local phase2_end=$(get_timestamp)
    local phase2_dur=$(calc_duration "$phase2_start" "$phase2_end")
    log_info "  Phase 2 completed in $(format_duration "$phase2_dur")"
    
    # Phase 2b: Hash verification (if enabled) - parallelized
    if [[ "$USE_HASH" == true && -f "$results_file" && "$dup_count" -gt 0 ]]; then
        local phase2b_start=$(get_timestamp)
        log_info "Phase 2b: Verifying hashes (parallel)..."
        local unique_files="$TEMP_DIR/unique_files.txt"
        local hash_map="$TEMP_DIR/hash_map.txt"
        local hashed_results="$TEMP_DIR/results_hashed.txt"
        
        # Step 1: Extract unique file paths from all pairs
        log_verbose "  Extracting unique files..."
        awk -F'|' '{ print $3; print $4 }' "$results_file" | sort -u > "$unique_files"
        local unique_count=$(wc -l < "$unique_files" | tr -d ' ')
        log_info "  Computing hashes for $unique_count unique files..."
        
        # Step 2: Compute hashes in parallel batches using xargs + md5sum
        # md5sum outputs: "hash  filename" (two spaces). Handle filenames with spaces.
        < "$unique_files" tr '\n' '\0' | xargs -0 -P8 -n100 md5sum 2>/dev/null | \
            sed 's/  /|/' > "$hash_map"
        
        local hashed_count=$(wc -l < "$hash_map" | tr -d ' ')
        log_info "  Computed $hashed_count hashes, matching pairs..."
        
        # Step 3: Join hashes back to pairs, stream deletion candidates
        local delete_preview="$TEMP_DIR/delete_preview.txt"
        awk -F'|' -v del_dist="$DELETE_DISTANCE" -v del_file="$delete_preview" \
            -v show_deletes="$([[ $DELETE_DISTANCE -ge 0 ]] && echo 1 || echo 0)" '
        function count_depth(path,    n, i, count) {
            n = length(path)
            count = 0
            for (i = 1; i <= n; i++) {
                if (substr(path, i, 1) == "/") count++
            }
            return count
        }
        
        NR == FNR {
            # First file: build hash lookup (hash|path)
            hash[$2] = $1
            next
        }
        {
            # Second file: results (dist|size|f1|f2|_)
            dist = $1
            size = $2
            f1 = $3
            f2 = $4
            
            h1 = hash[f1]
            h2 = hash[f2]
            match_result = (h1 != "" && h1 == h2) ? "true" : "false"
            
            # Output updated result
            print dist "|" size "|" f1 "|" f2 "|" match_result
            
            if (match_result == "true") {
                matches++
                
                # Stream deletion candidates if enabled
                if (show_deletes == 1 && dist < del_dist) {
                    d1 = count_depth(f1)
                    d2 = count_depth(f2)
                    
                    # Delete deeper file, or longer path if same depth
                    if (d1 > d2) {
                        to_delete = f1
                    } else if (d2 > d1) {
                        to_delete = f2
                    } else if (length(f1) >= length(f2)) {
                        to_delete = f1
                    } else {
                        to_delete = f2
                    }
                    
                    # Track unique deletions and print as we find them
                    if (!(to_delete in seen_deletes)) {
                        seen_deletes[to_delete] = 1
                        delete_count++
                        print "[DELETE]  " to_delete > "/dev/stderr"
                        print to_delete >> del_file
                    }
                }
            }
            
            # Progress every 10000 pairs
            if (FNR % 10000 == 0) {
                print "[INFO]   Matched " FNR " pairs, " matches " verified, " delete_count " to delete..." > "/dev/stderr"
            }
        }
        END {
            print "[INFO]   Verified " (FNR) " pairs, " matches " confirmed matches" > "/dev/stderr"
            if (show_deletes == 1 && delete_count > 0) {
                print "[INFO]   Found " delete_count " unique files to delete" > "/dev/stderr"
            }
        }
        ' "$hash_map" "$results_file" > "$hashed_results"
        
        mv "$hashed_results" "$results_file"
        
        # Update dup_count to only count matches if filtering
        local match_count=$(grep -c '|true$' "$results_file" 2>/dev/null || echo 0)
        dup_count=$match_count
        
        local phase2b_end=$(get_timestamp)
        local phase2b_dur=$(calc_duration "$phase2b_start" "$phase2b_end")
        log_info "  Phase 2b completed in $(format_duration "$phase2b_dur")"
    fi
    
    # Phase 3: Handle deletion if requested
    local delete_file="$TEMP_DIR/to_delete.txt"
    local delete_preview="$TEMP_DIR/delete_preview.txt"
    local deleted_count=0
    
    if [[ $DELETE_DISTANCE -ge 0 && -f "$results_file" ]]; then
        local phase3_start=$(get_timestamp)
        log_info "Phase 3: Processing deletions (distance < $DELETE_DISTANCE)..."
        
        # If hash verification already built the delete list, use it
        if [[ "$USE_HASH" == true && -f "$delete_preview" ]]; then
            log_verbose "  Using pre-computed deletion list from hash verification"
            mv "$delete_preview" "$delete_file"
        else
            # Build list of files to delete (keep shortest path, delete deepest)
            log_verbose "  Building deletion list..."
            while IFS='|' read -r dist size f1 f2 hash; do
                # Skip if distance >= threshold
                (( dist >= DELETE_DISTANCE )) && continue
                
                # Skip if hash check enabled and hashes don't match
                [[ "$USE_HASH" == true && "$hash" == "false" ]] && continue
                
                # Count path depth (number of / characters)
                local depth1="${f1//[!\/]/}"; depth1=${#depth1}
                local depth2="${f2//[!\/]/}"; depth2=${#depth2}
                
                # Delete the deeper file; if same depth, delete longer path (more chars)
                local to_delete=""
                if (( depth1 > depth2 )); then
                    to_delete="$f1"
                elif (( depth2 > depth1 )); then
                    to_delete="$f2"
                elif (( ${#f1} >= ${#f2} )); then
                    to_delete="$f1"
                else
                    to_delete="$f2"
                fi
                
                # Add to delete list if not already there
                if ! grep -qxF "$to_delete" "$delete_file" 2>/dev/null; then
                    echo "$to_delete" >> "$delete_file"
                fi
            done < "$results_file"
        fi
        
        # Count and display files to delete
        if [[ -f "$delete_file" ]]; then
            local to_delete_count=$(wc -l < "$delete_file" | tr -d ' ')
            local total_size=0
            
            echo ""
            echo "Files to delete ($to_delete_count):"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            while IFS= read -r f; do
                local fsize=$(get_size "$f")
                total_size=$((total_size + fsize))
                printf "  %s (%s bytes)\n" "$f" "$fsize"
            done < "$delete_file"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            printf "Total: %s files, %s bytes\n" "$to_delete_count" "$total_size"
            echo ""
            
            if [[ "$DRY_RUN" == true ]]; then
                echo "[DRY RUN] No files were deleted."
            else
                # Confirm deletion unless --force
                local confirm="y"
                if [[ "$FORCE_DELETE" == false ]]; then
                    printf "Delete these %s files? [y/N] " "$to_delete_count"
                    read -r confirm
                fi
                
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    while IFS= read -r f; do
                        if rm "$f" 2>/dev/null; then
                            deleted_count=$((deleted_count + 1))
                            log_info "Deleted: $f"
                        else
                            log_error "Failed to delete: $f"
                        fi
                    done < "$delete_file"
                    echo ""
                    echo "Deleted $deleted_count files."
                else
                    echo "Deletion cancelled."
                fi
            fi
        else
            echo "No files match deletion criteria."
        fi
        
        local phase3_end=$(get_timestamp)
        local phase3_dur=$(calc_duration "$phase3_start" "$phase3_end")
        log_info "  Phase 3 completed in $(format_duration "$phase3_dur")"
        
        # Final timing summary for deletion path
        local total_end=$(get_timestamp)
        local total_dur=$(calc_duration "$total_start" "$total_end")
        echo ""
        log_info "Total time: $(format_duration "$total_dur")"
        return
    fi
    
    # Phase 4: Output results (sorted by distance, then size desc)
    if [[ ! -f "$results_file" || $dup_count -eq 0 ]]; then
        if [[ "$OUTPUT_JSON" == true ]]; then
            echo "[]"
        else
            echo "No potential duplicates found."
        fi
        return
    fi
    
    if [[ "$OUTPUT_JSON" == true ]]; then
        echo "["
        local first=true
        sort -t'|' -k1,1n -k2,2rn "$results_file" | while IFS='|' read -r dist size f1 f2 hash; do
            [[ "$first" == true ]] && first=false || echo ","
            printf '  {"file1": "%s", "file2": "%s", "size": %s, "path_distance": %s, "hash_match": "%s"}' \
                "$f1" "$f2" "$size" "$dist" "$hash"
        done
        echo ""
        echo "]"
    else
        local sorted_file="$TEMP_DIR/sorted.txt"
        sort -t'|' -k1,1n -k2,2rn "$results_file" > "$sorted_file"
        while IFS='|' read -r dist size f1 f2 hash; do
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            printf "File 1:        %s\n" "$f1"
            printf "File 2:        %s\n" "$f2"
            printf "Size:          %s bytes\n" "$size"
            printf "Path distance: %s\n" "$dist"
            [[ "$hash" != "skipped" ]] && printf "Hash match:    %s\n" "$hash"
        done < "$sorted_file"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Total: $dup_count potential duplicate pairs"
    fi
    
    # Final timing summary
    local total_end=$(get_timestamp)
    local total_dur=$(calc_duration "$total_start" "$total_end")
    echo ""
    log_info "Total time: $(format_duration "$total_dur")"
}

main "$@"
