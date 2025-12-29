#!/usr/bin/env fish

# harbinger_convert.fish - Improved PDF to Markdown converter
# Now with: parallel processing, advanced preprocessing, checkpoints, OCR confidence
# Usage: ./harbinger_convert.fish input.pdf output_dir [--config config.json]

set -g PDF_FILE ""
set -g OUTPUT_DIR ""
set -g CONFIG_FILE ""
set -g TEMP_DIR ""

# Defaults (can be overridden by config)
set -g DPI 300
set -g PARALLEL_JOBS 4
set -g CONTRAST_LEVEL 50
set -g DO_DESKEW true
set -g DESKEW_THRESHOLD 40
set -g DO_DESPECKLE true
set -g CONTRAST_STRETCH "5%x5%"
set -g LEVEL_ADJUST "15%,85%,1.3"
set -g DO_MORPHOLOGY true
set -g MORPHOLOGY_OP "close diamond:1"
set -g OCR_CONFIDENCE_THRESHOLD 60
set -g OUTPUT_CONFIDENCE_REPORT true

# Detect ImageMagick version and set command
if command -v magick &>/dev/null
    set -g MAGICK_CMD magick
else if command -v convert &>/dev/null
    set -g MAGICK_CMD convert
else
    echo (set_color red)"[ERROR]"(set_color normal) "ImageMagick not found. Please install it." >&2
    exit 1
end

# ============================================================================
# LOGGING FUNCTIONS
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

function log_step
    echo "" >&2
    echo (set_color cyan)"┌─["(set_color yellow)" $argv[1] "(set_color cyan)"]"(set_color normal) >&2
end

function log_substep
    echo (set_color cyan)"│ "(set_color normal)"$argv" >&2
end

function log_complete
    echo (set_color cyan)"└─"(set_color green)" ✓ Complete"(set_color normal) >&2
end

# ============================================================================
# CHECKPOINT FUNCTIONS
# ============================================================================

function checkpoint_exists
    set step_name $argv[1]
    set checkpoint_file "$OUTPUT_DIR/.checkpoint_$step_name"
    test -f $checkpoint_file
end

function checkpoint_mark
    set step_name $argv[1]
    set checkpoint_file "$OUTPUT_DIR/.checkpoint_$step_name"
    echo (date) > $checkpoint_file
    log_substep "Checkpoint saved: $step_name"
end

function checkpoint_clear
    rm -f $OUTPUT_DIR/.checkpoint_* 2>/dev/null
    log_info "Checkpoints cleared"
end

function checkpoint_status
    echo (set_color yellow)"Checkpoint Status:"(set_color normal) >&2
    for step in extract preprocess ocr cleanup
        if checkpoint_exists $step
            echo "  ✓ $step" >&2
        else
            echo "  ○ $step" >&2
        end
    end
end

# ============================================================================
# CONFIG LOADING
# ============================================================================

function load_config
    if test -z "$CONFIG_FILE"; or not test -f "$CONFIG_FILE"
        log_warn "No config file, using defaults"
        return
    end
    
    log_info "Loading config from $CONFIG_FILE"
    
    # Check if jq is available
    if not command -v jq &>/dev/null
        log_warn "jq not found, cannot parse JSON config. Using defaults."
        return
    end
    
    # Load preprocessing settings
    set -g DPI (jq -r '.dpi // 300' $CONFIG_FILE)
    set -g PARALLEL_JOBS (jq -r '.parallel_jobs // 4' $CONFIG_FILE)
    
    set -g DO_DESKEW (jq -r '.preprocessing.deskew // true' $CONFIG_FILE)
    set -g DESKEW_THRESHOLD (jq -r '.preprocessing.deskew_threshold // 40' $CONFIG_FILE)
    set -g DO_DESPECKLE (jq -r '.preprocessing.despeckle // true' $CONFIG_FILE)
    set -g CONTRAST_STRETCH (jq -r '.preprocessing.contrast_stretch // "5%x5%"' $CONFIG_FILE)
    set -g LEVEL_ADJUST (jq -r '.preprocessing.level // "15%,85%,1.3"' $CONFIG_FILE)
    set -g DO_MORPHOLOGY (jq -r '.preprocessing.morphology != null' $CONFIG_FILE)
    set -g MORPHOLOGY_OP (jq -r '.preprocessing.morphology // "close diamond:1"' $CONFIG_FILE)
    
    # Load OCR settings
    set -g OCR_CONFIDENCE_THRESHOLD (jq -r '.ocr.confidence_threshold // 60' $CONFIG_FILE)
    set -g OUTPUT_CONFIDENCE_REPORT (jq -r '.ocr.output_confidence_report // true' $CONFIG_FILE)
    
    log_info "Config loaded: DPI=$DPI, parallel=$PARALLEL_JOBS jobs"
end

# ============================================================================
# PREPROCESSING FUNCTION (Advanced)
# ============================================================================

function preprocess_image
    set input_img $argv[1]
    set output_img $argv[2]
    
    # Build ImageMagick command dynamically based on config
    set cmd $MAGICK_CMD $input_img
    
    # Always convert to grayscale
    set cmd $cmd -colorspace Gray
    
    # Deskew if enabled
    if test "$DO_DESKEW" = "true"
        set cmd $cmd -deskew "$DESKEW_THRESHOLD%"
    end
    
    # Despeckle if enabled
    if test "$DO_DESPECKLE" = "true"
        set cmd $cmd -despeckle
    end
    
    # Contrast stretch
    if test -n "$CONTRAST_STRETCH"
        set cmd $cmd -contrast-stretch $CONTRAST_STRETCH
    end
    
    # Level adjustment
    if test -n "$LEVEL_ADJUST"
        set cmd $cmd -level $LEVEL_ADJUST
    end
    
    # Morphology for cleaning up broken characters
    if test "$DO_MORPHOLOGY" = "true"
        set cmd $cmd -morphology $MORPHOLOGY_OP
    end
    
    # Finalize: remove alpha, set white background
    set cmd $cmd -background white -alpha remove -alpha off $output_img
    
    # Execute
    eval $cmd
end

# ============================================================================
# PARALLEL PAGE PROCESSOR
# ============================================================================

function process_single_page
    set img $argv[1]
    set temp_dir $argv[2]
    set basename (basename $img .png)
    
    # Preprocess
    preprocess_image $img $temp_dir/$basename-processed.png
    
    # OCR with confidence output (TSV format)
    tesseract $temp_dir/$basename-processed.png $temp_dir/$basename \
        -l eng \
        --psm 1 \
        --oem 3 \
        tsv 2>/dev/null
    
    # Also get plain text
    tesseract $temp_dir/$basename-processed.png $temp_dir/$basename-text \
        -l eng \
        --psm 1 \
        --oem 3 \
        txt 2>/dev/null
    
    # Extract low-confidence words for review
    if test -f $temp_dir/$basename.tsv
        awk -F'\t' -v threshold=$OCR_CONFIDENCE_THRESHOLD \
            'NR > 1 && $11 != "" && $11 < threshold && $12 != "" {
                print $12 " (conf: " $11 ")"
            }' $temp_dir/$basename.tsv > $temp_dir/$basename-lowconf.txt
    end
    
    echo "done" > $temp_dir/$basename.complete
end

function process_pages_parallel
    set temp_dir $argv[1]
    set page_files $temp_dir/page-*.png
    set total_pages (count $page_files)
    set processed 0
    
    log_substep "Processing $total_pages pages with $PARALLEL_JOBS parallel jobs..."
    
    for img in $page_files
        set basename (basename $img .png)
        
        # Skip if already processed (for resume capability)
        if test -f $temp_dir/$basename.complete
            set processed (math $processed + 1)
            continue
        end
        
        # Launch background job
        process_single_page $img $temp_dir &
        
        # Limit concurrent jobs
        while test (jobs -p | wc -l) -ge $PARALLEL_JOBS
            sleep 0.2
        end
        
        set processed (math $processed + 1)
        
        # Progress indicator every 10 pages
        if test (math "$processed % 10") -eq 0
            log_substep "Progress: $processed / $total_pages pages"
        end
    end
    
    # Wait for all jobs to complete
    wait
    
    log_substep "All $total_pages pages processed"
end

# ============================================================================
# MAIN CONVERSION PIPELINE
# ============================================================================

function run_conversion
    # Step 1: Extract PDF pages as images
    if checkpoint_exists "extract"
        log_step "STEP 1: PDF Extraction [CACHED]"
        log_substep "Using cached extraction from previous run"
    else
        log_step "STEP 1: PDF Extraction"

        if set -q DEMO_MODE
            log_substep "DEMO MODE: Extracting first page only at $DPI DPI..."
            pdftoppm -png -r $DPI -f 1 -l 1 $PDF_FILE $TEMP_DIR/page
        else
            log_substep "Extracting pages at $DPI DPI..."
            pdftoppm -png -r $DPI $PDF_FILE $TEMP_DIR/page
        end

        set page_files $TEMP_DIR/page-*.png
        log_substep "Extracted "(count $page_files)" pages"

        checkpoint_mark "extract"
    end
    
    log_complete
    
    # Step 2: Preprocess and OCR (parallel)
    if checkpoint_exists "ocr"
        log_step "STEP 2: Preprocessing & OCR [CACHED]"
        log_substep "Using cached OCR results from previous run"
    else
        log_step "STEP 2: Preprocessing & OCR (Parallel)"
        
        process_pages_parallel $TEMP_DIR
        
        checkpoint_mark "ocr"
    end
    
    log_complete
    
    # Step 3: Combine OCR output
    log_step "STEP 3: Combining Output"
    
    set combined_text $TEMP_DIR/combined.txt
    set confidence_report $OUTPUT_DIR/ocr_confidence_report.txt
    
    echo "" > $combined_text
    
    if test "$OUTPUT_CONFIDENCE_REPORT" = "true"
        echo "# OCR Confidence Report" > $confidence_report
        echo "Generated: "(date) >> $confidence_report
        echo "Threshold: $OCR_CONFIDENCE_THRESHOLD%" >> $confidence_report
        echo "" >> $confidence_report
    end
    
    # Sort pages numerically and combine
    for txt_file in (ls $TEMP_DIR/page-*-text.txt 2>/dev/null | sort -V)
        set basename (basename $txt_file -text.txt)
        
        # Add page break marker
        echo "" >> $combined_text
        echo "<!-- PAGE BREAK: $basename -->" >> $combined_text
        echo "" >> $combined_text
        
        cat $txt_file >> $combined_text
        
        # Add low-confidence words to report
        if test "$OUTPUT_CONFIDENCE_REPORT" = "true"
            set lowconf_file $TEMP_DIR/$basename-lowconf.txt
            if test -f $lowconf_file; and test -s $lowconf_file
                echo "## $basename" >> $confidence_report
                cat $lowconf_file >> $confidence_report
                echo "" >> $confidence_report
            end
        end
    end
    
    log_substep "Combined OCR output created"
    
    if test "$OUTPUT_CONFIDENCE_REPORT" = "true"
        set low_conf_count (wc -l < $confidence_report)
        log_substep "Confidence report: $low_conf_count low-confidence items flagged"
    end
    
    log_complete
    
    # Step 4: Basic text cleanup and markdown creation
    log_step "STEP 4: Creating Markdown"
    
    set final_md $OUTPUT_DIR/converted.md
    
    # Add frontmatter
    echo "# "(basename $PDF_FILE .pdf)" - Converted Content" > $final_md
    echo "" >> $final_md
    echo "> Auto-converted on "(date) >> $final_md
    echo "> DPI: $DPI | Parallel Jobs: $PARALLEL_JOBS" >> $final_md
    echo "" >> $final_md
    echo "---" >> $final_md
    echo "" >> $final_md
    
    # Basic encoding cleanup and append
    cat $combined_text | \
        sed -e 's/â€™/'\''/g' \
            -e 's/â€œ/"/g' \
            -e 's/â€/"/g' \
            -e 's/â€"/—/g' \
            -e 's/â€˜/'\''/g' \
            -e 's/â€"/–/g' \
            -e 's/Â//g' \
            -e 's/â€¢/•/g' \
            -e 's/  */ /g' >> $final_md
    
    log_substep "Markdown output: $final_md"
    
    checkpoint_mark "cleanup"
    log_complete
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
            case --dpi
                set i (math $i + 1)
                set -g DPI $argv[$i]
            case --jobs -j
                set i (math $i + 1)
                set -g PARALLEL_JOBS $argv[$i]
            case --resume
                # Don't clear checkpoints
                set -g RESUME_MODE true
            case --clean
                # Clear checkpoints before running
                set -g CLEAN_MODE true
            case --status
                set -g STATUS_ONLY true
            case --demo
                # Demo mode: only process first page
                set -g DEMO_MODE true
            case '*.pdf'
                set -g PDF_FILE $argv[$i]
            case '*'
                # Assume it's the output directory if not a flag
                if not string match -q -- '-*' $argv[$i]
                    if test -z "$PDF_FILE"
                        set -g PDF_FILE $argv[$i]
                    else
                        set -g OUTPUT_DIR $argv[$i]
                    end
                end
        end
        set i (math $i + 1)
    end
end

# ============================================================================
# MAIN
# ============================================================================

parse_args $argv

# Validate inputs
if test -z "$PDF_FILE"
    echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
    echo (set_color cyan)"║"(set_color normal)(set_color yellow)"     HARBINGER CONVERT - PDF to Markdown Pipeline       "(set_color normal)(set_color cyan)"║"(set_color normal)
    echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
    echo ""
    log_error "No PDF file specified"
    echo ""
    echo "Usage: ./harbinger_convert.fish input.pdf output_dir [options]"
    echo ""
    echo "Options:"
    echo "  --config, -c FILE    Use JSON config file"
    echo "  --dpi NUM            DPI for extraction (default: 300)"
    echo "  --jobs, -j NUM       Parallel jobs (default: 4)"
    echo "  --resume             Resume from last checkpoint"
    echo "  --clean              Clear checkpoints and start fresh"
    echo "  --status             Show checkpoint status only"
    echo "  --demo               Demo mode: only process first page"
    echo ""
    echo "Example:"
    echo "  ./harbinger_convert.fish book.pdf output/ --config pipeline_config.json"
    exit 1
end

if not test -f "$PDF_FILE"
    log_error "PDF file not found: $PDF_FILE"
    exit 1
end

if test -z "$OUTPUT_DIR"
    set -g OUTPUT_DIR "converted_"(basename $PDF_FILE .pdf)
end

mkdir -p $OUTPUT_DIR

# Load config if specified
load_config

# Status only mode
if set -q STATUS_ONLY
    checkpoint_status
    exit 0
end

# Clean mode - clear checkpoints
if set -q CLEAN_MODE
    checkpoint_clear
end

# Create temp directory
set -g TEMP_DIR $OUTPUT_DIR/.temp
mkdir -p $TEMP_DIR

# Banner
echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color yellow)"     HARBINGER CONVERT - PDF to Markdown Pipeline       "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""
echo (set_color green)"PDF:         "(set_color normal)"$PDF_FILE"
echo (set_color green)"Output:      "(set_color normal)"$OUTPUT_DIR"
echo (set_color green)"Config:      "(set_color normal)(test -n "$CONFIG_FILE" && echo "$CONFIG_FILE" || echo "(defaults)")
if set -q DEMO_MODE
    echo (set_color yellow)"Mode:        "(set_color normal)(set_color yellow)"DEMO (first page only)"(set_color normal)
end
echo (set_color green)"DPI:         "(set_color normal)"$DPI"
echo (set_color green)"Parallel:    "(set_color normal)"$PARALLEL_JOBS jobs"
echo (set_color green)"Deskew:      "(set_color normal)"$DO_DESKEW (threshold: $DESKEW_THRESHOLD%)"
echo (set_color green)"OCR Conf:    "(set_color normal)"Threshold $OCR_CONFIDENCE_THRESHOLD%"
echo ""

# Show checkpoint status if resuming
if set -q RESUME_MODE
    checkpoint_status
    echo ""
end

# Record start time
set START_TIME (date +%s)

# Run the conversion
run_conversion

# Cleanup temp files (but keep checkpoints)
log_step "Cleanup"
rm -f $TEMP_DIR/page-*.png $TEMP_DIR/*-processed.png 2>/dev/null
log_substep "Temporary images removed (checkpoints preserved)"
log_complete

# Final report
set END_TIME (date +%s)
set ELAPSED (math $END_TIME - $START_TIME)
set MINUTES (math $ELAPSED / 60)
set SECONDS (math $ELAPSED % 60)

echo ""
echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color green)"                CONVERSION COMPLETE!                       "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""
echo (set_color yellow)"📊 Statistics:"(set_color normal)
echo "   Time:        $MINUTES min $SECONDS sec"
echo "   Output:      $OUTPUT_DIR/converted.md"
if test "$OUTPUT_CONFIDENCE_REPORT" = "true"
    echo "   Confidence:  $OUTPUT_DIR/ocr_confidence_report.txt"
end
echo ""
echo (set_color green)"✨ Done!"(set_color normal)
