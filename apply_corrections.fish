#!/usr/bin/env fish

# apply_corrections.fish - Apply learned corrections from corrections.json to markdown files
# Reads corrections.json and applies pattern replacements to OCR'd text
#
# Usage: ./apply_corrections.fish [converted_dir] [options]
#   --corrections FILE   Use specific corrections file (default: corrections.json)
#   --dry-run           Show what would be changed without modifying files
#   --verbose           Show each correction applied
#   --input FILE        Apply to a single file instead of all chapters

set -g OUTPUT_ROOT "converted_harbinger_house"
set -g CORRECTIONS_FILE "corrections.json"
set -g DRY_RUN false
set -g VERBOSE false
set -g SINGLE_FILE ""

# ============================================================================
# LOGGING
# ============================================================================

function log_info
    echo (set_color green)"[INFO]"(set_color normal) $argv >&2
end

function log_warn
    echo (set_color yellow)"[WARN]"(set_color normal) $argv >&2
end

function log_error
    echo (set_color red)"[ERROR]"(set_color normal) $argv >&2
end

function log_verbose
    if test $VERBOSE = "true"
        echo (set_color blue)"[VERB]"(set_color normal) $argv >&2
    end
end

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

function parse_args
    set -l i 1
    while test $i -le (count $argv)
        switch $argv[$i]
            case "--corrections"
                set i (math $i + 1)
                set -g CORRECTIONS_FILE $argv[$i]
            case "--dry-run"
                set -g DRY_RUN true
            case "--verbose"
                set -g VERBOSE true
            case "--input"
                set i (math $i + 1)
                set -g SINGLE_FILE $argv[$i]
            case "--help" "-h"
                echo "Usage: ./apply_corrections.fish [converted_dir] [options]"
                echo ""
                echo "Options:"
                echo "  --corrections FILE   Use specific corrections file (default: corrections.json)"
                echo "  --dry-run           Show what would be changed without modifying files"
                echo "  --verbose           Show each correction applied"
                echo "  --input FILE        Apply to a single file instead of all chapters"
                echo ""
                exit 0
            case "*"
                if test -d $argv[$i]
                    set -g OUTPUT_ROOT $argv[$i]
                end
        end
        set i (math $i + 1)
    end
end

# ============================================================================
# CORRECTION FUNCTIONS
# ============================================================================

function load_corrections
    # Load corrections from JSON file
    # Returns: sets global arrays CORRECTION_FROM and CORRECTION_TO
    
    if not test -f "$CORRECTIONS_FILE"
        log_error "Corrections file not found: $CORRECTIONS_FILE"
        return 1
    end
    
    if not command -v jq &>/dev/null
        log_error "jq is required for parsing corrections.json"
        return 1
    end
    
    # Extract simple corrections
    set -g CORRECTION_FROM
    set -g CORRECTION_TO
    set -g GARBAGE_PATTERNS
    set -g PRESERVE_TERMS
    
    # Load corrections as key:value pairs
    set corrections_raw (jq -r '.corrections | to_entries[] | "\(.key):\(.value)"' $CORRECTIONS_FILE 2>/dev/null)
    
    for correction in $corrections_raw
        set parts (string split ":" $correction)
        if test (count $parts) -ge 1
            set -a CORRECTION_FROM $parts[1]
            if test (count $parts) -ge 2
                set -a CORRECTION_TO $parts[2]
            else
                set -a CORRECTION_TO ""
            end
        end
    end
    
    # Load garbage patterns
    set -g GARBAGE_PATTERNS (jq -r '.garbage_patterns[]' $CORRECTIONS_FILE 2>/dev/null)
    
    # Load preserve terms
    set -g PRESERVE_TERMS (jq -r '.preserve_terms[]' $CORRECTIONS_FILE 2>/dev/null)
    
    log_info "Loaded "(count $CORRECTION_FROM)" corrections, "(count $GARBAGE_PATTERNS)" garbage patterns"
    
    return 0
end

function build_sed_script
    # Build a sed script from the corrections
    # This is more efficient than running sed multiple times
    
    set sed_script ""
    
    for i in (seq 1 (count $CORRECTION_FROM))
        set from $CORRECTION_FROM[$i]
        set to $CORRECTION_TO[$i]
        
        # Skip empty from patterns
        if test -z "$from"
            continue
        end
        
        # Escape special regex characters in the 'from' pattern
        set escaped_from (string escape --style=regex $from)
        
        # Build word-boundary aware replacement
        # Use \b for word boundaries where appropriate
        if test -n "$to"
            set sed_script "$sed_script""-e 's/\\b$escaped_from\\b/$to/g' "
        else
            # Empty replacement = delete the word
            set sed_script "$sed_script""-e 's/\\b$escaped_from\\b//g' "
        end
    end
    
    # Add garbage pattern removals
    for pattern in $GARBAGE_PATTERNS
        # For garbage at start of lines (headers)
        set sed_script "$sed_script""-e 's/$pattern//g' "
    end
    
    echo $sed_script
end

function apply_to_file
    set input_file $argv[1]
    set output_file $argv[2]
    
    if not test -f "$input_file"
        log_error "Input file not found: $input_file"
        return 1
    end
    
    # Build sed command
    set sed_script (build_sed_script)
    
    if test -z "$sed_script"
        log_warn "No corrections to apply"
        cp $input_file $output_file
        return 0
    end
    
    # Count lines before
    set lines_before (wc -l < $input_file)
    
    if test $DRY_RUN = "true"
        log_info "[DRY-RUN] Would apply corrections to: $input_file"
        
        # Show sample of what would change
        set temp_out (mktemp)
        eval "sed $sed_script $input_file" > $temp_out
        
        set diff_output (diff $input_file $temp_out 2>/dev/null | head -20)
        if test -n "$diff_output"
            echo "  Sample changes:"
            echo "$diff_output" | head -10
        else
            echo "  No changes detected"
        end
        
        rm -f $temp_out
    else
        # Apply corrections
        set temp_out (mktemp)
        eval "sed $sed_script $input_file" > $temp_out
        
        # Count changes by comparing
        set changes (diff $input_file $temp_out 2>/dev/null | grep -c "^<" || echo "0")
        
        mv $temp_out $output_file
        
        log_verbose "Applied $changes corrections to "(basename $input_file)
    end
    
    return 0
end

function apply_to_chapter
    set chapter_dir $argv[1]
    set chapter_name (basename $chapter_dir)
    
    # Find the best source file (prefer dict_cleaned, then cleaned, then converted)
    set source_file ""
    set output_file "$chapter_dir/corrected.md"
    
    if test -f "$chapter_dir/dict_cleaned.md"
        set source_file "$chapter_dir/dict_cleaned.md"
    else if test -f "$chapter_dir/cleaned.md"
        set source_file "$chapter_dir/cleaned.md"
    else if test -f "$chapter_dir/converted.md"
        set source_file "$chapter_dir/converted.md"
    else
        log_warn "No source file found in $chapter_name"
        return 1
    end
    
    log_info "Processing $chapter_name..."
    apply_to_file $source_file $output_file
    
    return $status
end

function process_all_chapters
    set -l processed 0
    set -l failed 0
    
    for chapter_dir in $OUTPUT_ROOT/*/
        set chapter_name (basename $chapter_dir)
        
        # Skip non-chapter directories
        if test "$chapter_name" = "final" -o "$chapter_name" = "statblocks" -o "$chapter_name" = "diagnostics"
            continue
        end
        
        if apply_to_chapter $chapter_dir
            set processed (math $processed + 1)
        else
            set failed (math $failed + 1)
        end
    end
    
    log_info "Processed $processed chapters, $failed failed"
end

# ============================================================================
# MAIN
# ============================================================================

parse_args $argv

echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color yellow)"       APPLY OCR CORRECTIONS FROM LEARNED PATTERNS      "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""

# Show settings
echo (set_color green)"Settings:"(set_color normal)
echo "  Corrections file: $CORRECTIONS_FILE"
echo "  Output root:      $OUTPUT_ROOT"
echo "  Dry run:          $DRY_RUN"
echo "  Verbose:          $VERBOSE"
if test -n "$SINGLE_FILE"
    echo "  Single file:      $SINGLE_FILE"
end
echo ""

# Load corrections
if not load_corrections
    exit 1
end

echo ""

# Apply corrections
if test -n "$SINGLE_FILE"
    # Single file mode
    set output_file (dirname $SINGLE_FILE)"/corrected_"(basename $SINGLE_FILE)
    apply_to_file $SINGLE_FILE $output_file
else
    # Process all chapters
    if not test -d "$OUTPUT_ROOT"
        log_error "Directory not found: $OUTPUT_ROOT"
        exit 1
    end
    
    process_all_chapters
end

echo ""
if test $DRY_RUN = "true"
    echo (set_color yellow)"✨ Dry run complete - no files modified"(set_color normal)
else
    echo (set_color green)"✨ Corrections applied!"(set_color normal)
    echo "   Output files: corrected.md in each chapter directory"
end
echo ""
