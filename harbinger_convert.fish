#!/usr/bin/env fish

# harbinger_convert.fish - Improved PDF to Markdown converter
# Now with: parallel processing, advanced preprocessing, checkpoints, OCR confidence
# Usage: ./harbinger_convert.fish input.pdf output_dir [--config config.json]

# Source progress utilities
source (dirname (status filename))/progress_utils.fish

set -g PDF_FILE ""
set -g OUTPUT_DIR ""
set -g CONFIG_FILE ""
set -g TEMP_DIR ""
set -g STAGE "all"  # Can be: extract, preprocess, ocr, combine, all

# Defaults (can be overridden by config)
# v2.0: Gentler preprocessing to reduce OCR artifacts
set -g DPI 300
set -g PARALLEL_JOBS 4
set -g CONTRAST_LEVEL 50
set -g DO_DESKEW true
set -g DESKEW_THRESHOLD 40
set -g DO_DESPECKLE false
set -g CONTRAST_STRETCH "2%x2%"
set -g LEVEL_ADJUST "10%,90%,1.0"
set -g DO_MORPHOLOGY false
set -g MORPHOLOGY_OP "close diamond:1"
set -g OCR_CONFIDENCE_THRESHOLD 60
set -g OUTPUT_CONFIDENCE_REPORT true
# v2.1: Configurable OCR engine params
set -g OCR_PSM 6
set -g OCR_OEM 1
set -g OCR_USER_WORDS ""
set -g OCR_LANGUAGE "eng"

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
# UNIFIED CHECKPOINT FUNCTIONS (Single JSON file)
# ============================================================================

set -g CHECKPOINT_FILE ".pipeline_state.json"

function checkpoint_init
    set state_file "$OUTPUT_DIR/$CHECKPOINT_FILE"
    if not test -f $state_file
        echo '{"steps": {}, "created": "'(date -Iseconds)'", "version": "2.0"}' > $state_file
    end
end

function checkpoint_exists
    set step_name $argv[1]
    set state_file "$OUTPUT_DIR/$CHECKPOINT_FILE"

    if not test -f $state_file
        return 1
    end

    if not command -v jq &>/dev/null
        # Fallback: simple grep
        grep -q "\"$step_name\"" $state_file
        return $status
    end

    set result (jq -r ".steps.\"$step_name\" // \"null\"" $state_file 2>/dev/null)
    test "$result" != "null"
end

function checkpoint_mark
    set step_name $argv[1]
    set state_file "$OUTPUT_DIR/$CHECKPOINT_FILE"

    checkpoint_init

    if not command -v jq &>/dev/null
        log_warn "jq not available, checkpoint tracking limited"
        return
    end

    # Update the JSON with timestamp for this step
    jq ".steps.\"$step_name\" = \""(date -Iseconds)"\" | .updated = \""(date -Iseconds)"\"" $state_file > $state_file.tmp
    mv $state_file.tmp $state_file

    log_substep "Checkpoint saved: $step_name"
end

function checkpoint_clear
    set state_file "$OUTPUT_DIR/$CHECKPOINT_FILE"
    rm -f $state_file 2>/dev/null

    # Also clean up old-style checkpoints
    rm -f $OUTPUT_DIR/.checkpoint_* 2>/dev/null

    log_info "All checkpoints cleared"
end

function checkpoint_status
    set state_file "$OUTPUT_DIR/$CHECKPOINT_FILE"

    echo (set_color yellow)"Checkpoint Status:"(set_color normal) >&2

    if not test -f $state_file
        echo "  No checkpoints found" >&2
        return
    end

    for step in extract preprocess ocr cleanup
        if checkpoint_exists $step
            if command -v jq &>/dev/null
                set timestamp (jq -r ".steps.\"$step\"" $state_file 2>/dev/null)
                echo "  ✓ $step ($timestamp)" >&2
            else
                echo "  ✓ $step" >&2
            end
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
    set -g DO_DESPECKLE (jq -r '.preprocessing.despeckle // false' $CONFIG_FILE)
    set -g CONTRAST_STRETCH (jq -r '.preprocessing.contrast_stretch // "2%x2%"' $CONFIG_FILE)
    set -g LEVEL_ADJUST (jq -r '.preprocessing.level // "10%,90%,1.0"' $CONFIG_FILE)

    # Morphology: check if it's explicitly set and not null
    set morphology_val (jq -r '.preprocessing.morphology // "null"' $CONFIG_FILE)
    if test "$morphology_val" = "null"
        set -g DO_MORPHOLOGY false
    else
        set -g DO_MORPHOLOGY true
        set -g MORPHOLOGY_OP $morphology_val
    end
    
    # Load OCR settings
    set -g OCR_CONFIDENCE_THRESHOLD (jq -r '.ocr.confidence_threshold // 60' $CONFIG_FILE)
    set -g OUTPUT_CONFIDENCE_REPORT (jq -r '.ocr.output_confidence_report // true' $CONFIG_FILE)
    set -g OCR_PSM (jq -r '.ocr.psm // 6' $CONFIG_FILE)
    set -g OCR_OEM (jq -r '.ocr.oem // 1' $CONFIG_FILE)
    set -g OCR_LANGUAGE (jq -r '.ocr.language // "eng"' $CONFIG_FILE)
    
    # Load user words file (relative to config file or absolute)
    set user_words_val (jq -r '.ocr.user_words // ""' $CONFIG_FILE)
    if test -n "$user_words_val"
        if test -f "$user_words_val"
            set -g OCR_USER_WORDS $user_words_val
        else
            # Try relative to script directory
            set script_dir (dirname (status filename))
            if test -f "$script_dir/$user_words_val"
                set -g OCR_USER_WORDS "$script_dir/$user_words_val"
            end
        end
    end
    
    log_info "Config loaded: DPI=$DPI, parallel=$PARALLEL_JOBS jobs, PSM=$OCR_PSM, OEM=$OCR_OEM"
    if test -n "$OCR_USER_WORDS"
        log_info "Using user words: $OCR_USER_WORDS"
    end
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
# PARALLEL PAGE PROCESSOR - PREPROCESSING STAGE
# ============================================================================

function preprocess_single_page
    set img $argv[1]
    set temp_dir $argv[2]
    set basename (basename $img .png)

    # Skip if interactive preprocessing artifacts exist (user already cleaned)
    set cleaned_img $temp_dir/$basename-cleaned.png
    set column_1_img $temp_dir/$basename-column-1.png

    if test -f $cleaned_img; or test -f $column_1_img
        # Interactive preprocessing already done, skip auto-preprocessing
        echo "done" > $temp_dir/$basename-preprocess.complete
        return 0
    end

    # Run auto-preprocessing
    preprocess_image $img $temp_dir/$basename-processed.png

    echo "done" > $temp_dir/$basename-preprocess.complete
end

function preprocess_pages_parallel
    set temp_dir $argv[1]
    # Only process original pages, not intermediate files
    set page_files (find $temp_dir -name "page-*.png" \
                    -not -name "*-processed.png" \
                    -not -name "*-cleaned.png" \
                    -not -name "*-column-*.png" | sort -V)
    set total_pages (count $page_files)
    set processed 0
    set completed 0

    log_substep "Preprocessing $total_pages pages with $PARALLEL_JOBS parallel jobs..."

    progress_start $total_pages "Preprocess images"

    for img in $page_files
        set basename (basename $img .png)

        # Skip if already preprocessed
        if test -f $temp_dir/$basename-preprocess.complete
            set processed (math $processed + 1)
            set completed (math $completed + 1)
            progress_update $completed
            continue
        end

        # Launch background job
        preprocess_single_page $img $temp_dir &

        # Limit concurrent jobs
        while test (jobs -p | wc -l) -ge $PARALLEL_JOBS
            set new_completed (count $temp_dir/*-preprocess.complete 2>/dev/null)
            if test $new_completed -gt $completed
                set completed $new_completed
                progress_update $completed
            end
            sleep 0.2
        end

        set processed (math $processed + 1)
    end

    # Wait for all jobs
    while test (jobs -p | wc -l) -gt 0
        set new_completed (count $temp_dir/*-preprocess.complete 2>/dev/null)
        if test $new_completed -gt $completed
            set completed $new_completed
            progress_update $completed
        end
        sleep 0.3
    end

    progress_update $total_pages
    progress_finish

    log_substep "All $total_pages pages preprocessed"
end

# ============================================================================
# PARALLEL PAGE PROCESSOR - OCR STAGE
# ============================================================================

function ocr_single_page
    set temp_dir $argv[1]
    set basename $argv[2]

    # Check for interactive preprocessing artifacts
    set cleaned_img $temp_dir/$basename-cleaned.png
    set column_1_img $temp_dir/$basename-column-1.png
    set processed_img $temp_dir/$basename-processed.png
    set original_img $temp_dir/$basename.png

    # Determine which image(s) to use for OCR
    if test -f $column_1_img
        # Interactive preprocessing created column images - OCR each separately
        # Write status to progress queue (for inline progress display)
        progress_set_status "columns: $basename" "$temp_dir/.progress_status"

        # Find all column images
        set column_images
        set col_num 1
        while test -f $temp_dir/$basename-column-$col_num.png
            set column_images $column_images $temp_dir/$basename-column-$col_num.png
            set col_num (math $col_num + 1)
        end

        # OCR each column
        set combined_text ""
        set combined_tsv_header ""
        set combined_lowconf ""

        for col_idx in (seq 1 (count $column_images))
            set col_img $column_images[$col_idx]
            set col_base "$basename-col$col_idx"

            # Run OCR on this column
            set tess_args $col_img $temp_dir/$col_base
            set tess_args $tess_args -l $OCR_LANGUAGE
            set tess_args $tess_args --psm $OCR_PSM
            set tess_args $tess_args --oem $OCR_OEM

            if test -n "$OCR_USER_WORDS"; and test -f "$OCR_USER_WORDS"
                set tess_args $tess_args --user-words $OCR_USER_WORDS
            end

            tesseract $tess_args tsv 2>/dev/null
            tesseract $tess_args txt 2>/dev/null

            # Extract low-confidence words from this column
            if test -f $temp_dir/$col_base.tsv
                awk -F'\t' -v threshold=$OCR_CONFIDENCE_THRESHOLD \
                    'NR > 1 && $11 != "" && $11 < threshold && $12 != "" {
                        print $12 " (conf: " $11 ")"
                    }' $temp_dir/$col_base.tsv >> $temp_dir/$basename-lowconf.txt
            end
        end

        # Combine column text files into single output
        echo "" > $temp_dir/$basename-text.txt
        for col_idx in (seq 1 (count $column_images))
            set col_base "$basename-col$col_idx"
            if test -f $temp_dir/$col_base.txt
                echo "" >> $temp_dir/$basename-text.txt
                echo "" >> $temp_dir/$basename-text.txt
                echo "<!-- COLUMN $col_idx -->" >> $temp_dir/$basename-text.txt
                echo "" >> $temp_dir/$basename-text.txt
                cat $temp_dir/$col_base.txt >> $temp_dir/$basename-text.txt
            end
        end

    else if test -f $cleaned_img
        # Interactive preprocessing created a cleaned image (no columns)
        # Write status to progress queue (for inline progress display)
        progress_set_status "cleaned: $basename" "$temp_dir/.progress_status"

        # Use cleaned image directly (already preprocessed by user)
        set tess_args $cleaned_img $temp_dir/$basename
        set tess_args $tess_args -l $OCR_LANGUAGE
        set tess_args $tess_args --psm $OCR_PSM
        set tess_args $tess_args --oem $OCR_OEM

        if test -n "$OCR_USER_WORDS"; and test -f "$OCR_USER_WORDS"
            set tess_args $tess_args --user-words $OCR_USER_WORDS
        end

        tesseract $tess_args tsv 2>/dev/null
        tesseract $tess_args txt 2>/dev/null

        # Extract low-confidence words
        if test -f $temp_dir/$basename.tsv
            awk -F'\t' -v threshold=$OCR_CONFIDENCE_THRESHOLD \
                'NR > 1 && $11 != "" && $11 < threshold && $12 != "" {
                    print $12 " (conf: " $11 ")"
                }' $temp_dir/$basename.tsv > $temp_dir/$basename-lowconf.txt
        end

    else if test -f $processed_img
        # Auto-preprocessed image exists
        set tess_args $processed_img $temp_dir/$basename
        set tess_args $tess_args -l $OCR_LANGUAGE
        set tess_args $tess_args --psm $OCR_PSM
        set tess_args $tess_args --oem $OCR_OEM

        if test -n "$OCR_USER_WORDS"; and test -f "$OCR_USER_WORDS"
            set tess_args $tess_args --user-words $OCR_USER_WORDS
        end

        tesseract $tess_args tsv 2>/dev/null
        tesseract $tess_args txt 2>/dev/null

        # Extract low-confidence words
        if test -f $temp_dir/$basename.tsv
            awk -F'\t' -v threshold=$OCR_CONFIDENCE_THRESHOLD \
                'NR > 1 && $11 != "" && $11 < threshold && $12 != "" {
                    print $12 " (conf: " $11 ")"
                }' $temp_dir/$basename.tsv > $temp_dir/$basename-lowconf.txt
        end
    else
        log_warn "No preprocessed image found for $basename, skipping OCR"
        return 1
    end

    echo "done" > $temp_dir/$basename-ocr.complete
end

function ocr_pages_parallel
    set temp_dir $argv[1]
    
    # Find unique page basenames from any page artifact (columns, cleaned, processed, or original)
    set page_basenames (find $temp_dir -name "page-*.png" -o -name "page-*-column-*.png" -o -name "page-*-cleaned.png" | \
                        sed 's/-column-[0-9]*\.png$//' | sed 's/-cleaned\.png$//' | sed 's/-processed\.png$//' | \
                        sed 's/\.png$//' | sort -u | xargs -n1 basename)
    
    set total_pages (count $page_basenames)
    set processed 0
    set completed 0

    log_substep "OCR $total_pages pages with $PARALLEL_JOBS parallel jobs..."

    # Initialize progress tracking with status file for parallel jobs
    progress_start $total_pages "OCR pages" $temp_dir

    for basename in $page_basenames
        # Skip if already OCR'd (for resume capability)
        if test -f $temp_dir/$basename-ocr.complete
            set processed (math $processed + 1)
            set completed (math $completed + 1)
            progress_update $completed
            continue
        end

        # Launch background job
        ocr_single_page $temp_dir $basename &

        # Limit concurrent jobs
        while test (jobs -p | wc -l) -ge $PARALLEL_JOBS
            # Check for newly completed jobs and update progress
            set new_completed (count $temp_dir/*-ocr.complete 2>/dev/null)
            if test $new_completed -gt $completed
                set completed $new_completed
                progress_update $completed
            end
            sleep 0.2
        end

        set processed (math $processed + 1)
    end

    # Wait for all jobs to complete
    while test (jobs -p | wc -l) -gt 0
        set new_completed (count $temp_dir/*-ocr.complete 2>/dev/null)
        if test $new_completed -gt $completed
            set completed $new_completed
            progress_update $completed
        end
        sleep 0.3
    end

    # Final update
    progress_update $total_pages
    progress_finish

    log_substep "All $total_pages pages OCR'd"
end

# ============================================================================
# MAIN CONVERSION PIPELINE - STAGED EXECUTION
# ============================================================================

function stage_extract
    if checkpoint_exists "extract"
        log_step "STEP 1: PDF Extraction [CACHED]"
        log_substep "Using cached extraction from previous run"
    else
        log_step "STEP 1: PDF Extraction"

        # Get total page count for progress
        set total_pages 0
        if command -v pdfinfo &>/dev/null
            set total_pages (pdfinfo $PDF_FILE 2>/dev/null | grep "Pages:" | awk '{print $2}')
        end
        if test -z "$total_pages"; or test "$total_pages" = "0"
            set total_pages 1
        end

        if set -q DEMO_MODE
            log_substep "DEMO MODE: Extracting first page only at $DPI DPI..."
            set total_pages 1
        end

        log_substep "Extracting $total_pages pages at $DPI DPI (using pdftocairo)..."
        progress_start $total_pages "Extracting pages"

        # Use pdftocairo with JPEG for faster extraction (2-3x faster than pdftoppm PNG)
        # Falls back to pdftoppm if pdftocairo not available
        if command -v pdftocairo &>/dev/null
            if set -q DEMO_MODE
                pdftocairo -jpeg -r $DPI -f 1 -l 1 $PDF_FILE $TEMP_DIR/page 2>/dev/null &
            else
                pdftocairo -jpeg -r $DPI $PDF_FILE $TEMP_DIR/page 2>/dev/null &
            end
        else
            log_warn "pdftocairo not found, falling back to pdftoppm (slower)"
            if set -q DEMO_MODE
                pdftoppm -jpeg -r $DPI -f 1 -l 1 $PDF_FILE $TEMP_DIR/page 2>/dev/null &
            else
                pdftoppm -jpeg -r $DPI $PDF_FILE $TEMP_DIR/page 2>/dev/null &
            end
        end

        set extract_pid $last_pid

        # Monitor progress by counting extracted files
        set extracted_count 0
        while kill -0 $extract_pid 2>/dev/null
            set new_count (count $TEMP_DIR/page-*.jpg 2>/dev/null)
            if test $new_count -gt $extracted_count
                set extracted_count $new_count
                progress_update $extracted_count
            end
            sleep 0.3
        end

        # Wait for completion and get final count
        wait $extract_pid

        # Rename jpg to png for consistency with rest of pipeline
        for jpg_file in $TEMP_DIR/page-*.jpg
            if test -f $jpg_file
                set png_file (string replace '.jpg' '.png' $jpg_file)
                mv $jpg_file $png_file
            end
        end

        set page_files $TEMP_DIR/page-*.png
        set final_count (count $page_files)
        progress_update $final_count
        progress_finish

        if test $final_count -eq 0
            log_error "No pages extracted from PDF!"
            return 1
        end

        log_substep "Extracted $final_count pages"
        checkpoint_mark "extract"
    end

    log_complete
end

function stage_preprocess
    # Ensure extraction has been done first
    if not checkpoint_exists "extract"
        stage_extract
        or return 1
    end

    if checkpoint_exists "preprocess"
        log_step "STEP 2: Auto-Preprocessing [CACHED]"
        log_substep "Using cached preprocessing from previous run"
    else
        log_step "STEP 2: Auto-Preprocessing"

        # Validate that we have pages to preprocess
        set page_files $TEMP_DIR/page-*.png
        set page_count (count $page_files)

        if test $page_count -eq 0
            log_error "No pages found in $TEMP_DIR - extraction may have failed"
            return 1
        end

        log_substep "Found $page_count pages to preprocess"
        preprocess_pages_parallel $TEMP_DIR

        checkpoint_mark "preprocess"
    end

    log_complete
end

function stage_ocr
    # Ensure extraction and preprocessing have been done
    if not checkpoint_exists "extract"
        stage_extract
        or return 1
    end
    if not checkpoint_exists "preprocess"
        stage_preprocess
        or return 1
    end

    if checkpoint_exists "ocr"
        log_step "STEP 3: OCR [CACHED]"
        log_substep "Using cached OCR results from previous run"
    else
        log_step "STEP 3: OCR (Parallel)"

        ocr_pages_parallel $TEMP_DIR

        checkpoint_mark "ocr"
    end

    log_complete
end

function stage_combine
    if checkpoint_exists "combine"
        log_step "STEP 4: Combining Output [CACHED]"
        log_substep "Using cached combined output from previous run"
        log_complete
        return 0
    end

    log_step "STEP 4: Combining Output"

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

    # Create markdown
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

    checkpoint_mark "combine"
    log_complete
end

function run_conversion
    # Run based on STAGE variable
    switch $STAGE
        case "extract"
            stage_extract
        case "preprocess"
            stage_preprocess
        case "ocr"
            stage_ocr
        case "combine"
            stage_combine
        case "all"
            # Run all stages in sequence
            stage_extract
            stage_preprocess
            # Note: Interactive preprocessing happens externally between preprocess and ocr
            stage_ocr
            stage_combine
        case "*"
            log_error "Invalid stage: $STAGE"
            log_error "Valid stages: extract, preprocess, ocr, combine, all"
            return 1
    end
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
            case --stage
                set i (math $i + 1)
                set -g STAGE $argv[$i]
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
    echo "  --stage STAGE        Run specific stage: extract, preprocess, ocr, combine, all (default: all)"
    echo "  --resume             Resume from last checkpoint"
    echo "  --clean              Clear checkpoints and start fresh"
    echo "  --status             Show checkpoint status only"
    echo "  --demo               Demo mode: only process first page"
    echo ""
    echo "Examples:"
    echo "  # Full pipeline (all stages):"
    echo "  ./harbinger_convert.fish book.pdf output/ --config pipeline_config.json"
    echo ""
    echo "  # Run specific stages:"
    echo "  ./harbinger_convert.fish book.pdf output/ --stage extract"
    echo "  ./harbinger_convert.fish book.pdf output/ --stage preprocess"
    echo "  ./harbinger_convert.fish book.pdf output/ --stage ocr"
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
# Only cleanup images if we completed OCR or running full pipeline
# This preserves images for interactive preprocessing
if test "$STAGE" = "all"; or test "$STAGE" = "combine"
    log_step "Cleanup"
    rm -f $TEMP_DIR/page-*.png $TEMP_DIR/*-processed.png 2>/dev/null
    log_substep "Temporary images removed (checkpoints preserved)"
    log_complete
else
    log_step "Cleanup"
    log_substep "Preserving images for interactive preprocessing"
    log_complete
end

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
