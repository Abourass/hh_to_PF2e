#!/usr/bin/env fish

# batch_convert.fish - Convert PDF by chapters using config file
# Reads chapter definitions from JSON config or auto-detects from PDF bookmarks
# Usage: ./batch_convert.fish input.pdf --config pipeline_config.json

# Source progress utilities
source (dirname (status filename))/progress_utils.fish

set -g PDF_FILE ""
set -g CONFIG_FILE ""
set -g OUTPUT_ROOT ""
set -g DPI 300
set -g AUTO_DETECT false
set -g PARALLEL_JOBS 4
set -g STAGE "all"  # Can be: extract, preprocess, ocr, combine, all

# ============================================================================
# LOGGING
# ============================================================================

# IMPORTANT: All log functions output to stderr (>&2) to prevent
# being captured by command substitution in functions that return values

function log_info
    echo (set_color green)"[INFO]"(set_color normal) $argv >&2
end

function log_warn
    echo (set_color yellow)"[WARN]"(set_color normal) $argv >&2
end

function log_error
    echo (set_color red)"[ERROR]"(set_color normal) $argv >&2
end

# ============================================================================
# CHAPTER DETECTION
# ============================================================================

function detect_chapters_from_bookmarks
    set pdf $argv[1]
    set output_file $argv[2]
    
    log_info "Attempting to extract chapters from PDF bookmarks..."
    
    # Check if pdftk is available
    if not command -v pdftk &>/dev/null
        log_warn "pdftk not found, cannot extract bookmarks"
        return 1
    end
    
    # Extract bookmark data
    set bookmark_data (pdftk $pdf dump_data 2>/dev/null | grep -A2 "BookmarkTitle\|BookmarkPageNumber")
    
    if test -z "$bookmark_data"
        log_warn "No bookmarks found in PDF"
        return 1
    end
    
    # Parse bookmarks into chapter definitions
    # This creates a JSON-compatible output
    echo "[" > $output_file
    
    set prev_title ""
    set prev_page ""
    set first true
    
    pdftk $pdf dump_data 2>/dev/null | while read line
        if string match -q "BookmarkTitle:*" $line
            set prev_title (string replace "BookmarkTitle: " "" $line)
        else if string match -q "BookmarkPageNumber:*" $line
            set current_page (string replace "BookmarkPageNumber: " "" $line)
            
            if test -n "$prev_title"
                # Clean the title for use as a filename
                set clean_name (string lower $prev_title | string replace -a " " "_" | string replace -ra '[^a-z0-9_]' '')
                
                if test "$first" = "true"
                    set first false
                else
                    echo "," >> $output_file
                end
                
                echo "  {" >> $output_file
                echo "    \"name\": \"$clean_name\"," >> $output_file
                echo "    \"start_page\": $current_page," >> $output_file
                echo "    \"description\": \"$prev_title\"" >> $output_file
                echo -n "  }" >> $output_file
            end
        end
    end
    
    echo "" >> $output_file
    echo "]" >> $output_file
    
    log_info "Extracted bookmarks to $output_file"
    return 0
end

function get_chapters_from_config
    set config $argv[1]
    
    if not command -v jq &>/dev/null
        log_error "jq is required to parse JSON config"
        exit 1
    end
    
    # Extract chapter count
    set chapter_count (jq '.chapters | length' $config)
    
    if test "$chapter_count" = "0"; or test "$chapter_count" = "null"
        log_warn "No chapters defined in config"
        return 1
    end
    
    log_info "Found $chapter_count chapters in config"
    
    # Return chapter specs as "name:start-end" lines
    for i in (seq 0 (math $chapter_count - 1))
        set name (jq -r ".chapters[$i].name" $config)
        set pages (jq -r ".chapters[$i].pages" $config)
        echo "$name:$pages"
    end
end

function generate_default_chapters
    set pdf $argv[1]
    set pages_per_chapter $argv[2]
    
    if test -z "$pages_per_chapter"
        set pages_per_chapter 20
    end
    
    # Get total page count
    set total_pages (pdfinfo $pdf 2>/dev/null | grep "Pages:" | awk '{print $2}')
    
    if test -z "$total_pages"
        log_error "Could not determine page count"
        return 1
    end
    
    log_info "PDF has $total_pages pages, creating chunks of $pages_per_chapter pages"
    
    set chapter_num 0
    set start_page 1
    
    while test $start_page -le $total_pages
        set chapter_num (math $chapter_num + 1)
        set end_page (math "min($start_page + $pages_per_chapter - 1, $total_pages)")
        
        echo "chapter_$chapter_num:$start_page-$end_page"
        
        set start_page (math $end_page + 1)
    end
end

# ============================================================================
# CHECKPOINT FUNCTIONS
# ============================================================================

function chapter_checkpoint_exists
    set chapter_name $argv[1]
    test -f "$OUTPUT_ROOT/$chapter_name/.checkpoint_complete"
end

function chapter_checkpoint_mark
    set chapter_name $argv[1]
    echo (date) > "$OUTPUT_ROOT/$chapter_name/.checkpoint_complete"
end

# ============================================================================
# MAIN CONVERSION LOOP
# ============================================================================

function convert_chapters
    set chapters $argv
    
    set total_chapters (count $chapters)
    set current 0
    set skipped 0
    set failed 0
    
    # Initialize chapter progress tracking
    set conversion_start (date +%s)
    set chapter_times
    
    for chapter_spec in $chapters
        set current (math $current + 1)
        set chapter_start (date +%s)
        
        set parts (string split ":" $chapter_spec)
        set chapter_name $parts[1]
        set page_range $parts[2]
        set range_parts (string split "-" $page_range)
        set start_page $range_parts[1]
        set end_page $range_parts[2]
        
        # Calculate ETA based on previous chapter times
        set eta_str ""
        if test (count $chapter_times) -gt 0
            set avg_time 0
            for t in $chapter_times
                set avg_time (math "$avg_time + $t")
            end
            set avg_time (math --scale=0 "$avg_time / "(count $chapter_times))
            set remaining_chapters (math "$total_chapters - $current + 1")
            set eta_seconds (math "$avg_time * $remaining_chapters")
            set eta_str (format_eta $eta_seconds)
        end
        
        echo ""
        echo (set_color cyan)"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"(set_color normal)
        echo (set_color yellow)"[$current/$total_chapters] $chapter_name "(set_color normal)"(pages $start_page-$end_page)  "(set_color yellow)"$eta_str"(set_color normal)
        echo (set_color cyan)"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"(set_color normal)
        
        # Check if already complete
        if chapter_checkpoint_exists $chapter_name
            echo (set_color blue)"  [SKIP]"(set_color normal) " Already converted (use --clean to reconvert)"
            set skipped (math $skipped + 1)
            continue
        end
        
        # Create chapter output directory
        set chapter_output $OUTPUT_ROOT/$chapter_name
        mkdir -p $chapter_output
        
        # Extract chapter pages to temp PDF
        set chapter_pdf $OUTPUT_ROOT/.temp_$chapter_name.pdf
        
        if not pdftk $PDF_FILE cat $start_page-$end_page output $chapter_pdf 2>/dev/null
            log_error "Failed to extract pages $start_page-$end_page"
            set failed (math $failed + 1)
            continue
        end
        
        # Convert chapter using the improved converter
        set convert_args $chapter_pdf $chapter_output --dpi $DPI --jobs $PARALLEL_JOBS --stage $STAGE

        if test -n "$CONFIG_FILE"
            set convert_args $convert_args --config $CONFIG_FILE
        end

        if set -q DEMO_MODE
            set convert_args $convert_args --demo
        end

        if ./harbinger_convert.fish $convert_args
            # Only mark complete if running all stages or final stage (combine)
            if test "$STAGE" = "all"; or test "$STAGE" = "combine"
                chapter_checkpoint_mark $chapter_name
            end
            log_info "Chapter $chapter_name complete (stage: $STAGE)"
        else
            log_error "Chapter $chapter_name failed (stage: $STAGE)"
            set failed (math $failed + 1)
        end
        
        # Clean up temp PDF
        rm -f $chapter_pdf
        
        # Record chapter processing time for ETA calculation
        set chapter_elapsed (math (date +%s) - $chapter_start)
        set chapter_times $chapter_times $chapter_elapsed

        # In demo mode, only process first chapter
        if set -q DEMO_MODE
            log_info "DEMO MODE: Stopping after first chapter"
            break
        end
    end
    
    # Calculate total time
    set total_elapsed (math (date +%s) - $conversion_start)
    set total_time_str (format_duration $total_elapsed)
    
    # Summary
    echo ""
    echo (set_color cyan)"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"(set_color normal)
    echo (set_color green)"Batch Conversion Summary"(set_color normal)
    echo (set_color cyan)"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"(set_color normal)
    echo "  Total:     $total_chapters chapters"
    echo "  Converted: "(math $total_chapters - $skipped - $failed)
    echo "  Skipped:   $skipped (already done)"
    echo "  Failed:    $failed"
    echo "  Time:      $total_time_str"
    
    return (test $failed -eq 0)
end

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

function parse_args
    set -l i 1
    while test $i -le (count $argv)
        switch $argv[$i]
            case --config -c
                set i (math $i + 1)
                set -g CONFIG_FILE $argv[$i]
            case --output -o
                set i (math $i + 1)
                set -g OUTPUT_ROOT $argv[$i]
            case --dpi
                set i (math $i + 1)
                set -g DPI $argv[$i]
            case --jobs -j
                set i (math $i + 1)
                set -g PARALLEL_JOBS $argv[$i]
            case --stage
                set i (math $i + 1)
                set -g STAGE $argv[$i]
            case --auto
                set -g AUTO_DETECT true
            case --clean
                set -g CLEAN_MODE true
            case --list
                set -g LIST_ONLY true
            case --demo
                set -g DEMO_MODE true
            case '*.pdf'
                set -g PDF_FILE $argv[$i]
            case '*'
                if not string match -q -- '-*' $argv[$i]
                    set -g PDF_FILE $argv[$i]
                end
        end
        set i (math $i + 1)
    end
end

# ============================================================================
# MAIN
# ============================================================================

parse_args $argv

# Validate
if test -z "$PDF_FILE"
    echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
    echo (set_color cyan)"║"(set_color normal)(set_color yellow)"     BATCH CONVERT - Chapter-by-Chapter Pipeline        "(set_color normal)(set_color cyan)"║"(set_color normal)
    echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
    echo ""
    log_error "No PDF file specified"
    echo ""
    echo "Usage: ./batch_convert.fish input.pdf [options]"
    echo ""
    echo "Options:"
    echo "  --config, -c FILE   JSON config with chapter definitions"
    echo "  --output, -o DIR    Output root directory"
    echo "  --dpi NUM           DPI for extraction (default: 300)"
    echo "  --jobs, -j NUM      Parallel jobs per chapter (default: 4)"
    echo "  --stage STAGE       Run specific stage: extract, preprocess, ocr, combine, all (default: all)"
    echo "  --auto              Auto-detect chapters from PDF bookmarks"
    echo "  --clean             Clear checkpoints and reconvert all"
    echo "  --list              List chapters without converting"
    echo "  --demo              Demo mode: only process first chapter"
    echo ""
    echo "Config file should define chapters like:"
    echo '  {"chapters": [{"name": "intro", "pages": "1-5"}, ...]}'
    echo ""
    echo "Or use --auto to extract from PDF bookmarks"
    echo ""
    echo "Note: Use --stage to run specific pipeline stages. This allows you to:"
    echo "  1. Extract and preprocess images (--stage preprocess)"
    echo "  2. Run interactive preprocessing"
    echo "  3. Run OCR on cleaned images (--stage ocr)"
    exit 1
end

if not test -f "$PDF_FILE"
    log_error "PDF file not found: $PDF_FILE"
    exit 1
end

# Set output root
if test -z "$OUTPUT_ROOT"
    set -g OUTPUT_ROOT "converted_"(basename $PDF_FILE .pdf)
end

mkdir -p $OUTPUT_ROOT

# Load config settings if provided
if test -n "$CONFIG_FILE"; and test -f "$CONFIG_FILE"; and command -v jq &>/dev/null
    set config_dpi (jq -r '.dpi // empty' $CONFIG_FILE)
    set config_jobs (jq -r '.parallel_jobs // empty' $CONFIG_FILE)
    set config_output (jq -r '.output_root // empty' $CONFIG_FILE)
    
    if test -n "$config_dpi"
        set -g DPI $config_dpi
    end
    if test -n "$config_jobs"
        set -g PARALLEL_JOBS $config_jobs
    end
    if test -n "$config_output"; and test -z "$OUTPUT_ROOT"
        set -g OUTPUT_ROOT $config_output
    end
end

# Banner
echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color yellow)"     BATCH CONVERT - Chapter-by-Chapter Pipeline        "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""
echo (set_color green)"PDF:         "(set_color normal)"$PDF_FILE"
echo (set_color green)"Output:      "(set_color normal)"$OUTPUT_ROOT"
echo (set_color green)"Config:      "(set_color normal)(test -n "$CONFIG_FILE" && echo "$CONFIG_FILE" || echo "(none)")
if set -q DEMO_MODE
    echo (set_color yellow)"Mode:        "(set_color normal)(set_color yellow)"DEMO (first chapter only)"(set_color normal)
end
echo (set_color green)"DPI:         "(set_color normal)"$DPI"
echo (set_color green)"Parallel:    "(set_color normal)"$PARALLEL_JOBS jobs"
echo ""

# Determine chapter list
set chapters

if test -n "$CONFIG_FILE"; and test -f "$CONFIG_FILE"
    # Get chapters from config file
    log_info "Loading chapters from config..."
    set chapters (get_chapters_from_config $CONFIG_FILE)
else if test "$AUTO_DETECT" = "true"
    # Try to auto-detect from PDF bookmarks
    set bookmark_file $OUTPUT_ROOT/.detected_chapters.json
    
    if detect_chapters_from_bookmarks $PDF_FILE $bookmark_file
        # Parse the detected bookmarks
        log_info "Using auto-detected chapters"
        set chapter_count (jq '. | length' $bookmark_file)
        
        for i in (seq 0 (math $chapter_count - 1))
            set name (jq -r ".[$i].name" $bookmark_file)
            set start (jq -r ".[$i].start_page" $bookmark_file)
            
            # Calculate end page (next chapter's start - 1, or end of PDF)
            set next_start (jq -r ".["(math $i + 1)"].start_page // empty" $bookmark_file)
            
            if test -n "$next_start"
                set end_page (math $next_start - 1)
            else
                set end_page (pdfinfo $PDF_FILE | grep "Pages:" | awk '{print $2}')
            end
            
            set chapters $chapters "$name:$start-$end_page"
        end
    else
        # Fall back to default chunking
        log_warn "Could not detect chapters, using default 20-page chunks"
        set chapters (generate_default_chapters $PDF_FILE 20)
    end
else
    # No config, no auto-detect - use default chunking
    log_info "No chapter config provided, using default 20-page chunks"
    set chapters (generate_default_chapters $PDF_FILE 20)
end

if test -z "$chapters"
    log_error "No chapters to convert"
    exit 1
end

# List only mode
if set -q LIST_ONLY
    echo (set_color yellow)"Chapters to convert:"(set_color normal)
    for chapter in $chapters
        set parts (string split ":" $chapter)
        echo "  • $parts[1] (pages $parts[2])"
    end
    exit 0
end

# Clean mode
if set -q CLEAN_MODE
    log_info "Cleaning chapter checkpoints..."
    for checkpoint in $OUTPUT_ROOT/*/.checkpoint_complete
        if test -f $checkpoint
            rm -f $checkpoint
        end
    end
end

# Record start time
set START_TIME (date +%s)

# Run conversion
convert_chapters $chapters

# Final timing
set END_TIME (date +%s)
set ELAPSED (math $END_TIME - $START_TIME)
set MINUTES (math $ELAPSED / 60)
set SECONDS (math $ELAPSED % 60)

echo ""
echo (set_color green)"Total time: $MINUTES min $SECONDS sec"(set_color normal)
echo ""
echo (set_color green)"✨ Batch conversion complete!"(set_color normal)
echo "   Output: $OUTPUT_ROOT/"
