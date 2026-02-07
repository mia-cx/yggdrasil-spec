#!/usr/bin/env bash
#
# merge-duplicate-folders.sh
# Finds and merges neighbor folders with common duplicate suffixes.
# Uses rsync --update --remove-source-files to keep only newest versions.
#
# Usage: ./merge-duplicate-folders.sh [directory] [options]
#   -d, --dir DIR          Directory to scan (default: current directory)
#   -r, --recursive        Scan subdirectories recursively
#   -j, --json             Output as JSON
#   -m, --merge            Actually perform the merge (default: preview only)
#   -f, --force            Skip confirmation prompt when merging
#   --dry-run              Show rsync commands without executing
#   -v, --verbose          Show extra debug info
#   -e, --exclude PATTERN  Exclude folders matching glob pattern (can repeat)
#   --help                 Show this help message
#
# Detected duplicate suffixes:
#   " (1)", " (2)", etc.    Windows-style duplicate
#   " - Copy", " - copy"    Windows copy suffix
#   "_copy", " copy"        Generic copy suffix
#   "_1", "_2", etc.        Underscore numbered
#   "-1", "-2", etc.        Dash numbered (only 1-9 to avoid dates)

set -euo pipefail

# --- Configuration ---
TARGET_DIR="."
RECURSIVE=false
OUTPUT_JSON=false
DO_MERGE=false
FORCE_MERGE=false
DRY_RUN=false
VERBOSE=false
EXCLUDE_PATTERNS=()
IS_LINUX=false
[[ "$(uname -s)" == "Linux" ]] && IS_LINUX=true
PROGRESS_INTERVAL="${PROGRESS_INTERVAL:-10000}"

# --- Helper Functions ---

print_usage() {
    sed -n '2,24p' "$0" | sed 's/^#\s\?//'
}

log_info() {
    [[ "$OUTPUT_JSON" == false ]] && echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_verbose() {
    [[ "$VERBOSE" == true ]] && echo "[DEBUG] $*" >&2 || true
}

# Timing functions
get_timestamp() {
    if [[ "$IS_LINUX" == true ]]; then
        date +%s.%N
    else
        python3 -c 'import time; print(f"{time.time():.3f}")' 2>/dev/null || date +%s
    fi
}

format_duration() {
    local seconds="$1"
    local mins secs
    
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

# Check if folder name has a duplicate suffix
# Returns the suffix pattern matched (for logging) or empty if no match
get_dup_suffix() {
    local name="$1"
    
    # Match patterns in order of specificity
    if [[ "$name" =~ [[:space:]]\([0-9]+\)$ ]]; then
        echo "parenthetical_num"  # " (1)", " (2)", etc.
    elif [[ "$name" =~ [[:space:]]-[[:space:]][Cc]opy$ ]]; then
        echo "dash_copy"          # " - Copy", " - copy"
    elif [[ "$name" =~ _copy$ ]]; then
        echo "underscore_copy"    # "_copy"
    elif [[ "$name" =~ [[:space:]]copy$ ]]; then
        echo "space_copy"         # " copy"
    elif [[ "$name" =~ _[0-9]+$ ]]; then
        echo "underscore_num"     # "_1", "_2", etc.
    elif [[ "$name" =~ -[1-9]$ ]]; then
        echo "dash_num"           # "-1" to "-9" (avoiding dates like -2024)
    else
        echo ""
    fi
}

# Strip duplicate suffix from folder name to get base name
get_base_name() {
    local name="$1"
    local base="$name"
    
    # Remove suffixes in order of specificity (most specific first)
    # Parenthetical numbers: " (1)", " (2)", etc.
    base=$(printf '%s' "$base" | sed -E 's/[[:space:]]+\([0-9]+\)$//')
    
    # Dash copy: " - Copy", " - copy"
    base=$(printf '%s' "$base" | sed -E 's/[[:space:]]+-[[:space:]]+[Cc]opy$//')
    
    # Underscore copy: "_copy"
    base=$(printf '%s' "$base" | sed -E 's/_copy$//')
    
    # Space copy: " copy"
    base=$(printf '%s' "$base" | sed -E 's/[[:space:]]+copy$//')
    
    # Underscore numbers: "_1", "_2", etc.
    base=$(printf '%s' "$base" | sed -E 's/_[0-9]+$//')
    
    # Dash single digit: "-1" to "-9"
    base=$(printf '%s' "$base" | sed -E 's/-[1-9]$//')
    
    # Trim whitespace
    base="${base%"${base##*[![:space:]]}"}"
    base="${base#"${base%%[![:space:]]*}"}"
    
    echo "$base"
}

# Get folder size (cross-platform)
get_folder_size() {
    local dir="$1"
    if [[ "$OSTYPE" == darwin* ]]; then
        du -sk "$dir" 2>/dev/null | cut -f1
    else
        du -sk "$dir" 2>/dev/null | cut -f1
    fi
}

# Format bytes to human readable
format_size() {
    local kb="$1"
    if (( kb >= 1048576 )); then
        awk "BEGIN { printf \"%.1f GB\", $kb / 1048576 }"
    elif (( kb >= 1024 )); then
        awk "BEGIN { printf \"%.1f MB\", $kb / 1024 }"
    else
        echo "${kb} KB"
    fi
}

# Count files in a directory
count_files() {
    local dir="$1"
    find "$dir" -type f 2>/dev/null | wc -l | tr -d ' '
}

# --- Main Logic ---

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--dir)
                TARGET_DIR="$2"
                shift 2
                ;;
            -r|--recursive)
                RECURSIVE=true
                shift
                ;;
            -j|--json)
                OUTPUT_JSON=true
                shift
                ;;
            -m|--merge)
                DO_MERGE=true
                shift
                ;;
            -f|--force)
                FORCE_MERGE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                DO_MERGE=true  # Enable merge path for dry-run output
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
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

# Bulk index all directories using awk for speed
# Processes all directories in a single pass
bulk_index_directories() {
    local target_dir="$1"
    local base_dir="$2"
    local recursive="$3"
    local progress_file="$4"
    local progress_interval="$5"
    local total_dirs="$6"
    
    local find_depth=""
    [[ "$recursive" == "false" ]] && find_depth="-maxdepth 1"
    
    # Single find + awk pass to index all directories
    find "$target_dir" $find_depth -type d -print 2>/dev/null | awk -v base_dir="$base_dir" \
        -v progress_file="$progress_file" \
        -v progress_interval="$progress_interval" \
        -v total_dirs="$total_dirs" \
'
    function get_suffix(name) {
        # Check patterns in order of specificity
        # Use [(] and [)] for literal parentheses in awk ERE
        if (match(name, /[[:space:]][(][0-9]+[)]$/)) return "parenthetical_num"
        if (match(name, /[[:space:]]-[[:space:]][Cc]opy$/)) return "dash_copy"
        if (match(name, /_copy$/)) return "underscore_copy"
        if (match(name, /[[:space:]]copy$/)) return "space_copy"
        if (match(name, /_[0-9]+$/)) return "underscore_num"
        if (match(name, /-[1-9]$/)) return "dash_num"
        return "none"
    }
    
    function get_base_name(name) {
        base = name
        # Remove suffixes - use [(] and [)] for literal parentheses
        gsub(/[[:space:]]+[(][0-9]+[)]$/, "", base)
        gsub(/[[:space:]]+-[[:space:]]+[Cc]opy$/, "", base)
        gsub(/_copy$/, "", base)
        gsub(/[[:space:]]+copy$/, "", base)
        gsub(/_[0-9]+$/, "", base)
        gsub(/-[1-9]$/, "", base)
        # Trim whitespace
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", base)
        return base
    }
    
    function encode_name(name) {
        gsub(/[^a-zA-Z0-9._-]/, "_", name)
        return substr(name, 1, 100)
    }
    
    BEGIN {
        count = 0
        last_progress = 0
    }
    
    {
        path = $0
        count++
        
        # Extract directory name (basename)
        n = split(path, parts, "/")
        name = parts[n]
        
        # Get parent directory
        parent = ""
        for (i = 1; i < n; i++) {
            parent = parent (i > 1 ? "/" : "") parts[i]
        }
        if (parent == "") parent = "/"
        
        suffix = get_suffix(name)
        if (suffix != "none") {
            base_name = get_base_name(name)
        } else {
            base_name = name
        }
        
        # Encode for filename and include parent hash to group by parent
        # Simple hash: sum of char codes modulo a large number
        parent_hash = 0
        for (i = 1; i <= length(parent); i++) {
            c = substr(parent, i, 1)
            # Use index in a string of chars as pseudo-ord
            chars = " !\"#$%&'\''()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
            idx = index(chars, c)
            if (idx == 0) idx = 32
            parent_hash = (parent_hash * 31 + idx) % 100000000
        }
        
        encoded = encode_name(base_name) "___" parent_hash
        outfile = base_dir "/" encoded ".txt"
        
        print path "|" suffix >> outfile
        close(outfile)
        
        # Track suffix stats
        if (suffix != "none") {
            suffix_counts[suffix]++
            total_with_suffix++
        }
        
        # Progress logging (simple interval-based, no rate calc in awk)
        if (progress_interval > 0 && (count - last_progress) >= progress_interval) {
            # Count group files for progress
            cmd = "find \"" base_dir "\" -type f -name \"*.txt\" 2>/dev/null | wc -l"
            cmd | getline group_count
            close(cmd)
            gsub(/[[:space:]]/, "", group_count)
            
            pct = sprintf("%.1f", (count / total_dirs) * 100)
            print "[INFO]   Progress: " count "/" total_dirs " dirs (" pct "%), " group_count " groups, " total_with_suffix " with dup suffix" > "/dev/stderr"
            last_progress = count
        }
    }
    
    END {
        print count > progress_file
        
        # Print suffix breakdown to stderr
        if (total_with_suffix > 0) {
            print "[DEBUG]   Suffix breakdown:" > "/dev/stderr"
            for (s in suffix_counts) {
                print "[DEBUG]     " s ": " suffix_counts[s] > "/dev/stderr"
            }
        }
    }
    '
}

# Extract duplicate pairs from indexed base groups
# Optimized: first filter to files with 2+ lines, then batch process
extract_pairs_from_groups() {
    local base_dir="$1"
    local pairs_file="$2"
    local work_dir=$(dirname "$pairs_file")
    local multi_line_files="$work_dir/multi_line_files.txt"
    local total_groups=$(find "$base_dir" -type f -name "*.txt" 2>/dev/null | wc -l | tr -d ' ')
    
    log_verbose "  Step 1: Filtering $total_groups groups for duplicates..."
    
    # Step 1: Fast filter - find files with 2+ lines (potential duplicates)
    # Use wc -l on all files at once, then filter
    find "$base_dir" -type f -name "*.txt" -print0 2>/dev/null | \
        xargs -0 wc -l 2>/dev/null | \
        awk '$1 >= 2 && $2 != "total" { print $2 }' > "$multi_line_files" || true
    
    local candidate_count=0
    [[ -s "$multi_line_files" ]] && candidate_count=$(wc -l < "$multi_line_files" | tr -d ' ')
    
    local skipped=$((total_groups - candidate_count))
    log_verbose "  Step 1 complete: $candidate_count candidates, $skipped singletons skipped"
    
    [[ "$candidate_count" -eq 0 || -z "$candidate_count" ]] && return 0
    
    log_verbose "  Step 2: Extracting pairs from $candidate_count candidate groups..."
    
    # Step 2: Process only files with duplicates
    # Concatenate all candidate files with markers, process in single awk
    {
        while IFS= read -r group_file; do
            # Add file marker and contents
            echo "===GROUP==="
            cat "$group_file" 2>/dev/null || true
        done < "$multi_line_files"
    } | awk -v candidate_count="$candidate_count" '
    BEGIN { 
        FS = "|"
        count = 0
        groups_processed = 0
        pairs_found = 0
        progress_interval = 10000
        last_progress = 0
    }
    
    function process_group() {
        if (count < 2) return
        
        groups_with_dupes++
        
        # Find original (no suffix, or shortest path)
        original = ""
        original_len = 999999
        
        for (i = 1; i <= count; i++) {
            if (suffixes[i] == "none") {
                if (original == "" || length(paths[i]) < original_len) {
                    original = paths[i]
                    original_len = length(paths[i])
                }
            }
        }
        
        # If no original found, use shortest path
        if (original == "") {
            for (i = 1; i <= count; i++) {
                if (original == "" || length(paths[i]) < original_len) {
                    original = paths[i]
                    original_len = length(paths[i])
                }
            }
        }
        
        # Output pairs
        for (i = 1; i <= count; i++) {
            if (paths[i] != original) {
                suffix = (suffixes[i] == "none") ? "duplicate" : suffixes[i]
                print paths[i] "|" original "|" suffix
                pairs_found++
            }
        }
    }
    
    /^===GROUP===$/ {
        # Process previous group
        process_group()
        
        groups_processed++
        
        # Progress logging
        if (candidate_count > 0 && (groups_processed - last_progress) >= progress_interval) {
            pct = sprintf("%.1f", (groups_processed / candidate_count) * 100)
            print "[DEBUG]   Pair extraction: " groups_processed "/" candidate_count " groups (" pct "%), " pairs_found " pairs found" > "/dev/stderr"
            last_progress = groups_processed
        }
        
        # Reset for next group
        count = 0
        delete paths
        delete suffixes
        next
    }
    
    # Accumulate entries
    {
        count++
        paths[count] = $1
        suffixes[count] = $2
    }
    
    END {
        # Process last group
        process_group()
        groups_processed++
        
        print "[DEBUG]   Step 2 complete: " groups_processed " groups processed, " groups_with_dupes " had duplicates, " pairs_found " pairs found" > "/dev/stderr"
    }
    ' >> "$pairs_file"
}

main() {
    parse_args "$@"
    
    if [[ ! -d "$TARGET_DIR" ]]; then
        log_error "Directory not found: $TARGET_DIR"
        exit 1
    fi
    
    # Resolve to absolute path
    TARGET_DIR=$(cd "$TARGET_DIR" && pwd)
    
    local total_start=$(get_timestamp)
    log_info "Scanning: $TARGET_DIR"
    local mode_str="single-level"
    [[ "$RECURSIVE" == true ]] && mode_str="recursive"
    log_info "Mode: $mode_str"
    [[ ${#EXCLUDE_PATTERNS[@]} -gt 0 ]] && log_info "Excluding: ${EXCLUDE_PATTERNS[*]}" || true
    [[ "$DO_MERGE" == true && "$DRY_RUN" == false ]] && log_info "Merge: ENABLED"
    [[ "$DRY_RUN" == true ]] && log_info "Dry run: ENABLED"
    
    # Create temp directory for work files
    local work_dir=$(mktemp -d)
    local pairs_file="$work_dir/pairs.txt"
    local base_dir="$work_dir/bases"
    local counter_file="$work_dir/counter.txt"
    touch "$pairs_file"
    mkdir -p "$base_dir"
    echo "0" > "$counter_file"
    trap "rm -rf '$work_dir'" EXIT
    
    # Phase 1a: Index all directories
    local phase1_start=$(get_timestamp)
    log_info "Phase 1a: Indexing directories..."
    
    local dirs_scanned=0
    local progress_file="$work_dir/progress.txt"
    
    if [[ "$RECURSIVE" == true ]]; then
        # First, count total directories for progress estimation
        log_verbose "  Counting directories..."
        local total_dirs=$(find "$TARGET_DIR" -type d 2>/dev/null | wc -l | tr -d ' ')
        log_info "  Found $total_dirs directories to scan"
        
        # Bulk index with progress
        bulk_index_directories "$TARGET_DIR" "$base_dir" "true" "$progress_file" "$PROGRESS_INTERVAL" "$total_dirs"
        dirs_scanned=$(cat "$progress_file" 2>/dev/null || echo 0)
    else
        # Only scan immediate children of target
        bulk_index_directories "$TARGET_DIR" "$base_dir" "false" "$progress_file" "0" "1"
        dirs_scanned=$(cat "$progress_file" 2>/dev/null || echo 1)
    fi
    
    local phase1a_end=$(get_timestamp)
    local phase1a_dur=$(calc_duration "$phase1_start" "$phase1a_end")
    log_info "  Indexed $dirs_scanned directories in $(format_duration "$phase1a_dur")"
    
    # Phase 1b: Extract duplicate pairs from indexed groups
    local phase1b_start=$(get_timestamp)
    log_info "Phase 1b: Extracting duplicate pairs from index..."
    
    local group_count=$(find "$base_dir" -type f -name "*.txt" 2>/dev/null | wc -l | tr -d ' ')
    log_verbose "  Processing $group_count base name groups..."
    
    extract_pairs_from_groups "$base_dir" "$pairs_file"
    
    local pair_count=0
    [[ -f "$pairs_file" ]] && pair_count=$(wc -l < "$pairs_file" | tr -d ' ')
    
    local phase1b_end=$(get_timestamp)
    local phase1b_dur=$(calc_duration "$phase1b_start" "$phase1b_end")
    local phase1_dur=$(calc_duration "$phase1_start" "$phase1b_end")
    log_info "  Found $pair_count duplicate folder pairs in $(format_duration "$phase1b_dur")"
    log_info "  Phase 1 total: $(format_duration "$phase1_dur")"
    
    if [[ $pair_count -eq 0 ]]; then
        if [[ "$OUTPUT_JSON" == true ]]; then
            echo "[]"
        else
            echo "No duplicate folders found."
        fi
        return 0
    fi
    
    # Phase 2: Analyze and display pairs
    local phase2_start=$(get_timestamp)
    log_info "Phase 2: Analyzing folder pairs..."
    
    local -a merge_commands=()
    local total_dup_size=0
    local total_dup_files=0
    
    if [[ "$OUTPUT_JSON" == true ]]; then
        echo "["
        local first=true
    else
        echo ""
        echo "Duplicate Folder Pairs Found:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
    
    while IFS='|' read -r dup_dir orig_dir suffix_type; do
        local dup_name=$(basename "$dup_dir")
        local orig_name=$(basename "$orig_dir")
        local dup_size=$(get_folder_size "$dup_dir")
        local orig_size=$(get_folder_size "$orig_dir")
        local dup_files=$(count_files "$dup_dir")
        local orig_files=$(count_files "$orig_dir")
        
        total_dup_size=$((total_dup_size + dup_size))
        total_dup_files=$((total_dup_files + dup_files))
        
        # Build rsync command
        local rsync_cmd="rsync -avh --update --remove-source-files \"${dup_dir}/\" \"${orig_dir}/\""
        merge_commands+=("$rsync_cmd|$dup_dir")
        
        if [[ "$OUTPUT_JSON" == true ]]; then
            [[ "$first" == true ]] && first=false || echo ","
            cat <<EOF
  {
    "duplicate": "$dup_dir",
    "original": "$orig_dir",
    "suffix_type": "$suffix_type",
    "duplicate_size_kb": $dup_size,
    "duplicate_files": $dup_files,
    "original_size_kb": $orig_size,
    "original_files": $orig_files
  }
EOF
        else
            printf "Duplicate:  %s\n" "$dup_dir"
            printf "  → Merge into: %s\n" "$orig_dir"
            printf "  Suffix type: %s\n" "$suffix_type"
            printf "  Duplicate: %s (%d files) | Original: %s (%d files)\n" \
                "$(format_size "$dup_size")" "$dup_files" \
                "$(format_size "$orig_size")" "$orig_files"
            echo ""
        fi
    done < "$pairs_file"
    
    if [[ "$OUTPUT_JSON" == true ]]; then
        echo ""
        echo "]"
    else
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        printf "Total: %d duplicate folders, %s (%d files)\n" \
            "$pair_count" "$(format_size "$total_dup_size")" "$total_dup_files"
    fi
    
    local phase2_end=$(get_timestamp)
    local phase2_dur=$(calc_duration "$phase2_start" "$phase2_end")
    log_info "  Phase 2 completed in $(format_duration "$phase2_dur")"
    
    # Phase 3: Merge if requested
    if [[ "$DO_MERGE" == true && ${#merge_commands[@]} -gt 0 ]]; then
        local phase3_start=$(get_timestamp)
        echo ""
        
        if [[ "$DRY_RUN" == true ]]; then
            log_info "Phase 3: Dry run - commands that would be executed:"
            for cmd_pair in "${merge_commands[@]}"; do
                local cmd="${cmd_pair%%|*}"
                echo "  $cmd"
            done
            echo ""
            echo "# Final cleanup"
            echo "  find \"$TARGET_DIR\" -type d -empty -delete"
        else
            log_info "Phase 3: Merging folders..."
            
            # Confirm unless --force
            local confirm="y"
            if [[ "$FORCE_MERGE" == false ]]; then
                printf "\nMerge %d duplicate folders? [y/N] " "$pair_count"
                read -r confirm
            fi
            
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                local merged_count=0
                local failed_count=0
                
                for cmd_pair in "${merge_commands[@]}"; do
                    local cmd="${cmd_pair%%|*}"
                    local dup_dir="${cmd_pair##*|}"
                    
                    log_info "Merging: $(basename "$dup_dir")"
                    log_verbose "  Command: $cmd"
                    
                    # Execute rsync
                    if eval "$cmd" 2>&1 | while read -r line; do log_verbose "  $line"; done; then
                        # Remove empty directories left behind
                        if find "$dup_dir" -type d -empty -delete 2>/dev/null; then
                            # Try to remove the root duplicate dir if empty
                            rmdir "$dup_dir" 2>/dev/null || true
                        fi
                        
                        if [[ -d "$dup_dir" ]]; then
                            local remaining=$(count_files "$dup_dir")
                            if [[ "$remaining" -eq 0 ]]; then
                                rm -rf "$dup_dir" 2>/dev/null && log_info "  Removed empty: $dup_dir"
                            else
                                # Files remain = target has newer versions, these are stale
                                # Safe to delete since we kept the newer versions in target
                                log_verbose "  $remaining stale files in duplicate (target has newer versions)"
                                log_verbose "  Removing stale duplicate folder..."
                                rm -rf "$dup_dir" 2>/dev/null && log_info "  Merged and removed: $(basename "$dup_dir") ($remaining stale files deleted)"
                            fi
                        else
                            log_info "  Merged and removed: $(basename "$dup_dir")"
                        fi
                        merged_count=$((merged_count + 1))
                    else
                        log_error "  Failed to merge: $dup_dir"
                        failed_count=$((failed_count + 1))
                    fi
                done
                
                # Final cleanup: remove any remaining empty directories
                log_info "Cleaning up empty directories..."
                local empty_removed=$(find "$TARGET_DIR" -type d -empty -delete -print 2>/dev/null | wc -l | tr -d ' ')
                [[ "$empty_removed" -gt 0 ]] && log_info "  Removed $empty_removed empty directories"
                
                echo ""
                echo "Merge complete: $merged_count succeeded, $failed_count failed"
            else
                echo "Merge cancelled."
            fi
        fi
        
        local phase3_end=$(get_timestamp)
        local phase3_dur=$(calc_duration "$phase3_start" "$phase3_end")
        log_info "  Phase 3 completed in $(format_duration "$phase3_dur")"
    elif [[ "$DO_MERGE" == false && "$OUTPUT_JSON" == false ]]; then
        echo ""
        echo "To merge these folders, run with --merge (or --dry-run to preview commands)"
    fi
    
    # Final timing summary
    local total_end=$(get_timestamp)
    local total_dur=$(calc_duration "$total_start" "$total_end")
    echo ""
    log_info "Total time: $(format_duration "$total_dur")"
}

main "$@"
