#!/usr/bin/env fish

# harbinger_master.fish - Complete PDF to clean Markdown pipeline (v2)
# Now with: config files, parallel processing, checkpoints, OCR confidence, stat block extraction
# Usage: ./harbinger_master.fish [options] input.pdf

# Source progress utilities
source (dirname (status filename))/progress_utils.fish

# ============================================================================
# GLOBAL CONFIGURATION
# ============================================================================

set -g PDF_FILE ""
set -g CONFIG_FILE ""
set -g OUTPUT_ROOT ""
set -g FINAL_OUTPUT ""
set -g STATS_FILE ""

# Defaults (can be overridden by config or flags)
set -g DPI 300
set -g PARALLEL_JOBS 4
set -g DO_CLEANUP true
set -g DO_DICT true
set -g DO_AI_CLEANUP false
set -g AI_BACKEND "claude"
set -g KEEP_PAGEBREAKS true
set -g EXTRACT_STATBLOCKS true
set -g DO_LEARNED_CORRECTIONS true
set -g ARCHIVE_DIAGNOSTICS true
set -g CLEANUP_TEMP_FILES true
set -g OPEN_VSCODE false

# Pipeline state
set -g TOTAL_CHAPTERS 0
set -g TOTAL_PAGES 0
set -g START_TIME 0
set -g SKIP_OCR_CHAPTERS

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

function master_checkpoint_init
    set state_file "$OUTPUT_ROOT/$CHECKPOINT_FILE"
    if not test -f $state_file
        echo '{"master_steps": {}, "chapters": {}, "created": "'(date -Iseconds)'", "version": "2.0"}' > $state_file
    end
end

function master_checkpoint_exists
    set step_name $argv[1]
    set state_file "$OUTPUT_ROOT/$CHECKPOINT_FILE"

    if not test -f $state_file
        return 1
    end

    if not command -v jq &>/dev/null
        grep -q "\"$step_name\"" $state_file
        return $status
    end

    set result (jq -r ".master_steps.\"$step_name\" // \"null\"" $state_file 2>/dev/null)
    test "$result" != "null"
end

function master_checkpoint_mark
    set step_name $argv[1]
    set state_file "$OUTPUT_ROOT/$CHECKPOINT_FILE"

    master_checkpoint_init

    if not command -v jq &>/dev/null
        log_warn "jq not available, checkpoint tracking limited"
        return
    end

    jq ".master_steps.\"$step_name\" = \""(date -Iseconds)"\" | .updated = \""(date -Iseconds)"\"" $state_file > $state_file.tmp
    mv $state_file.tmp $state_file
end

function master_checkpoint_clear
    set state_file "$OUTPUT_ROOT/$CHECKPOINT_FILE"
    rm -f $state_file 2>/dev/null

    # Also clean up old-style checkpoints
    set -l master_checkpoints $OUTPUT_ROOT/.master_checkpoint_* 2>/dev/null
    if test (count $master_checkpoints) -gt 0
        rm -f $master_checkpoints
    end

    # Clean up old chapter-level checkpoints
    for chapter_dir in $OUTPUT_ROOT/*/
        # Use 'set' to safely expand globs that may not match
        set -l checkpoint_files $chapter_dir/.checkpoint_* 2>/dev/null
        if test (count $checkpoint_files) -gt 0
            rm -f $checkpoint_files 2>/dev/null
        end
        if test -f $chapter_dir/.pipeline_state.json
            rm -f $chapter_dir/.pipeline_state.json
        end
    end

    log_info "All checkpoints cleared (unified to single file)"
end

function master_checkpoint_status
    set state_file "$OUTPUT_ROOT/$CHECKPOINT_FILE"

    echo (set_color yellow)"Master Pipeline Status:"(set_color normal) >&2

    if not test -f $state_file
        echo "  No checkpoints found" >&2
        return
    end

    for step in chapters cleanup dictionary learned_corrections ai_cleanup statblocks finalize diagnostics
        if master_checkpoint_exists $step
            if command -v jq &>/dev/null
                set timestamp (jq -r ".master_steps.\"$step\"" $state_file 2>/dev/null)
                echo "  ✓ $step ($timestamp)" >&2
            else
                echo "  ✓ $step" >&2
            end
        else
            echo "  ○ $step" >&2
        end
    end

    # Show chapter status if available
    if command -v jq &>/dev/null
        set chapter_count (jq -r '.chapters | length' $state_file 2>/dev/null)
        if test "$chapter_count" -gt 0
            echo "" >&2
            echo (set_color cyan)"  Chapters processed: $chapter_count"(set_color normal) >&2
        end
    end
end

# ============================================================================
# CONFIG LOADING
# ============================================================================

function load_config
    if test -z "$CONFIG_FILE"; or not test -f "$CONFIG_FILE"
        return
    end
    
    if not command -v jq &>/dev/null
        log_warn "jq not found, cannot parse JSON config"
        return
    end
    
    log_info "Loading configuration from $CONFIG_FILE"
    
    # Load input PDF if not provided via CLI
    if test -z "$PDF_FILE"
        set config_input (jq -r '.input // empty' $CONFIG_FILE)
        if test -n "$config_input"
            set -g PDF_FILE $config_input
        end
    end
    
    # Load general settings
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
    
    # Load cleanup settings
    set cleanup_encoding (jq -r '.cleanup.encoding // empty' $CONFIG_FILE)
    set cleanup_dict (jq -r '.cleanup.dictionary // empty' $CONFIG_FILE)
    set cleanup_ai (jq -r '.cleanup.ai_backend // empty' $CONFIG_FILE)
    
    if test "$cleanup_encoding" = "false"
        set -g DO_CLEANUP false
    end
    if test "$cleanup_dict" = "false"
        set -g DO_DICT false
    end
    if test -n "$cleanup_ai"; and test "$cleanup_ai" != "null"
        set -g DO_AI_CLEANUP true
        set -g AI_BACKEND $cleanup_ai
    end
    
    # Load stat block settings
    set statblock_enabled (jq -r '.statblock_detection.enabled // empty' $CONFIG_FILE)
    if test "$statblock_enabled" = "false"
        set -g EXTRACT_STATBLOCKS false
    end
    
    # Load chapters with skip_ocr flag
    set -g SKIP_OCR_CHAPTERS (jq -r '.chapters[] | select(.skip_ocr == true) | .name' $CONFIG_FILE 2>/dev/null)
    if test -n "$SKIP_OCR_CHAPTERS"
        log_info "OCR will be skipped for: "(string join ", " $SKIP_OCR_CHAPTERS)
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
            case --output -o
                set i (math $i + 1)
                set -g OUTPUT_ROOT $argv[$i]
            case --dpi
                set i (math $i + 1)
                set -g DPI $argv[$i]
            case --jobs -j
                set i (math $i + 1)
                set -g PARALLEL_JOBS $argv[$i]
            case --no-cleanup
                set -g DO_CLEANUP false
            case --no-dict
                set -g DO_DICT false
            case --ai
                set -g DO_AI_CLEANUP true
            case --ai-claude
                set -g DO_AI_CLEANUP true
                set -g AI_BACKEND "claude"
            case --no-statblocks
                set -g EXTRACT_STATBLOCKS false
            case --open
                set -g OPEN_VSCODE true
            case --resume
                set -g RESUME_MODE true
            case --clean
                set -g CLEAN_MODE true
            case --status
                set -g STATUS_ONLY true
            case --demo
                # Demo mode: only process first chapter/page
                set -g DEMO_MODE true
            case '*.pdf'
                set -g PDF_FILE $argv[$i]
            case '*.json'
                # Also accept JSON as config
                set -g CONFIG_FILE $argv[$i]
            case '*'
                if not string match -q -- '-*' $argv[$i]
                    if test -z "$PDF_FILE"
                        set -g PDF_FILE $argv[$i]
                    end
                end
        end
        set i (math $i + 1)
    end
end

# ============================================================================
# STEP: PDF EXTRACTION AND AUTO-PREPROCESSING
# ============================================================================

function step_extract_and_preprocess
    show_pipeline_progress "STEP 1: Extract & Auto-Preprocess"

    if master_checkpoint_exists "extract_preprocess"
        log_substep "Using cached extraction & preprocessing (--clean to redo)"
        set -g TOTAL_CHAPTERS (count $OUTPUT_ROOT/*/.pipeline_state.json 2>/dev/null)
        log_complete
        return 0
    end

    # Build base args
    set base_args $PDF_FILE --output $OUTPUT_ROOT --dpi $DPI --jobs $PARALLEL_JOBS

    if test -n "$CONFIG_FILE"
        set base_args $base_args --config $CONFIG_FILE
    end

    if set -q DEMO_MODE
        set base_args $base_args --demo
    end

    # Stage 1: Extract images from PDF (using fast pdftocairo)
    log_substep "Extracting images from PDF..."
    if not ./batch_convert.fish $base_args --stage extract
        log_error "Extraction failed"
        return 1
    end

    # Stage 2: Auto-preprocess images (deskew, despeckle, etc.)
    log_substep "Preprocessing images..."
    if not ./batch_convert.fish $base_args --stage preprocess
        log_error "Preprocessing failed"
        return 1
    end

    master_checkpoint_mark "extract_preprocess"
    set -g TOTAL_CHAPTERS (count $OUTPUT_ROOT/*/.pipeline_state.json 2>/dev/null)
    log_substep "Extracted & preprocessed $TOTAL_CHAPTERS chapters"

    log_complete
end

# ============================================================================
# STEP: OCR (AFTER INTERACTIVE PREPROCESSING)
# ============================================================================

function step_ocr_chapters
    show_pipeline_progress "STEP 3: OCR"

    if master_checkpoint_exists "ocr"
        log_substep "Using cached OCR results (--clean to re-OCR)"
        log_complete
        return 0
    end

    # Use batch_convert.fish with ocr+combine stages
    # This runs: OCR (on preprocessed/cleaned images) -> combine output
    set batch_args $PDF_FILE --output $OUTPUT_ROOT --dpi $DPI --jobs $PARALLEL_JOBS

    # Build stage list: ocr and combine
    # We need to run these separately to maintain checkpoints

    if test -n "$CONFIG_FILE"
        set batch_args $batch_args --config $CONFIG_FILE
    end

    if set -q DEMO_MODE
        set batch_args $batch_args --demo
    end

    # First run OCR stage
    log_substep "Running OCR on preprocessed images..."

    if ./batch_convert.fish $batch_args --stage ocr
        log_substep "OCR complete, combining output..."

        # Then run combine stage
        if ./batch_convert.fish $batch_args --stage combine
            master_checkpoint_mark "ocr"
            set -g TOTAL_CHAPTERS (count $OUTPUT_ROOT/*/converted.md 2>/dev/null)
            log_substep "OCR'd $TOTAL_CHAPTERS chapters"
        else
            log_error "Combine failed"
            return 1
        end
    else
        log_error "OCR failed"
        return 1
    end

    log_complete
end

# ============================================================================
# STEP: INTERACTIVE PREPROCESSING (Optional, runs AFTER auto-preprocessing)
# ============================================================================

function step_interactive_preprocessing
    show_pipeline_progress "STEP 2: Interactive Preprocessing"

    if master_checkpoint_exists "interactive_preprocessing"
        log_substep "Using cached interactive preprocessing"
        log_complete
        return 0
    end

    # Check if enabled
    set interactive_enabled false
    if test -n "$CONFIG_FILE"; and command -v jq &>/dev/null
        set interactive_enabled (jq -r '.interactive_preprocessing.enabled // false' $CONFIG_FILE)
    end

    if test "$interactive_enabled" != "true"
        show_pipeline_progress "STEP 2: Interactive Preprocessing [SKIPPED]"
        log_complete
        return 0
    end

    log_substep "Starting interactive preprocessing session..."
    log_warn "Browser will open. Draw columns and clean images, then click 'Finish'."
    log_substep "This runs BEFORE OCR for maximum effectiveness!"

    ./interactive_preprocessing_server.fish $OUTPUT_ROOT $CONFIG_FILE

    if test $status -eq 0
        master_checkpoint_mark "interactive_preprocessing"
        log_complete
        return 0
    else
        log_error "Interactive preprocessing cancelled"
        return 1
    end
end

# ============================================================================
# STEP: REPROCESS LOW-CONFIDENCE REGIONS (Optional, runs AFTER OCR)
# ============================================================================

function step_reprocess_lowconf
    # Check if reprocessing is enabled and threshold is set
    set reprocess_threshold 0
    if test -n "$CONFIG_FILE"; and command -v jq &>/dev/null
        set reprocess_threshold (jq -r '.ocr.reprocess_threshold // 0' $CONFIG_FILE)
    end

    if test "$reprocess_threshold" -eq 0
        show_pipeline_progress "STEP 3.5: Reprocess Low-Conf [SKIPPED]"
        log_complete
        return 0
    end

    show_pipeline_progress "STEP 3.5: Reprocess Low-Confidence Regions"

    if master_checkpoint_exists "reprocess_lowconf"
        log_substep "Using cached reprocessing"
        log_complete
        return 0
    end

    # Check if script exists
    if not test -f "./reprocess_lowconf_regions.fish"
        log_warn "reprocess_lowconf_regions.fish not found, skipping"
        log_complete
        return 0
    end

    log_substep "Reprocessing regions below $reprocess_threshold% confidence..."

    ./reprocess_lowconf_regions.fish $OUTPUT_ROOT --threshold $reprocess_threshold

    master_checkpoint_mark "reprocess_lowconf"
    log_complete
end

# ============================================================================
# STEP: OCR CLEANUP
# ============================================================================

function step_ocr_cleanup
    if not test $DO_CLEANUP = true
        show_pipeline_progress "STEP 4: OCR Cleanup [SKIPPED]"
        log_complete
        return 0
    end

    show_pipeline_progress "STEP 4: OCR Cleanup"
    
    if master_checkpoint_exists "cleanup"
        log_substep "Using cached cleanup"
        log_complete
        return 0
    end
    
    # Progress tracking for chapters in this step
    set chapter_dirs
    for chapter_dir in $OUTPUT_ROOT/*/
        set chapter_name (basename $chapter_dir)
        if test "$chapter_name" = "final"; or test "$chapter_name" = "statblocks"
            continue
        end
        if not contains $chapter_name $SKIP_OCR_CHAPTERS
            set chapter_dirs $chapter_dirs $chapter_dir
        end
    end
    
    set total_cleanup_chapters (count $chapter_dirs)
    set cleanup_idx 0
    progress_start $total_cleanup_chapters "Cleaning chapters"
    
    for chapter_dir in $chapter_dirs
        set chapter_name (basename $chapter_dir)
        set cleanup_idx (math $cleanup_idx + 1)
        
        set input_file $chapter_dir/converted.md
        set cleaned_file $chapter_dir/cleaned.md
        
        if not test -f $input_file
            continue
        end
        
        # Check if empty
        set line_count (wc -l < $input_file 2>/dev/null || echo 0)
        if test $line_count -eq 0
            touch $cleaned_file
            continue
        end
        
        log_substep "Cleaning $chapter_name..."
        
        # Comprehensive cleanup pipeline
        cat $input_file | \
        sed -e 's/â€™/'\''/g' \
            -e 's/â€œ/"/g' \
            -e 's/â€/"/g' \
            -e 's/â€"/—/g' \
            -e 's/â€˜/'\''/g' \
            -e 's/â€"/–/g' \
            -e 's/Â//g' \
            -e 's/â€¢/•/g' \
            -e 's/Facto1/Factol/g' \
            -e 's/\+HARBINGER\*\+/# HARBINGER/g' \
            -e 's/CREDI\+S/CREDITS/g' \
            -e 's/BACKGR®UND/BACKGROUND/g' \
            -e 's/¢//g' | \
        sed -e 's/\bJrom\b/from/g' \
            -e 's/\bJaction\b/faction/g' \
            -e 's/\beves\b/eyes/g' \
            -e 's/\bvou\b/you/g' \
            -e 's/\bbcrk\b/berk/g' \
            -e 's/\bLadv\b/Lady/g' \
            -e 's/\blll\b/III/g' \
            -e 's/\bthar\b/that/g' \
            -e 's/\brhe\b/the/g' \
            -e 's/\bwilh\b/with/g' | \
        sed -e 's/^[+*]\+\([A-Z][A-Z ]\+\)[+*]\+$/## \1/g' \
            -e 's/^[+*]\([A-Z][a-z][A-Za-z ]\+\)[+*]$/### \1/g' | \
        sed -e 's/  \+/ /g' \
            -e 's/^ \+//g' \
            -e '/^$/N;/^\n$/d' \
        > $cleaned_file
        
        progress_update $cleanup_idx
    end
    
    progress_finish
    master_checkpoint_mark "cleanup"
    log_complete
end

# ============================================================================
# STEP: DICTIONARY CORRECTIONS
# ============================================================================

function step_dictionary_cleanup
    if not test $DO_DICT = true
        show_pipeline_progress "STEP 5: Dictionary Corrections [SKIPPED]"
        log_complete
        return 0
    end

    show_pipeline_progress "STEP 5: Dictionary Corrections"
    
    if master_checkpoint_exists "dictionary"
        log_substep "Using cached dictionary corrections"
        log_complete
        return 0
    end
    
    # Load custom terms from config if available
    set custom_terms ""
    if test -n "$CONFIG_FILE"; and command -v jq &>/dev/null
        set custom_terms (jq -r '.planescape_dictionary.terms[]? // empty' $CONFIG_FILE 2>/dev/null)
    end
    
    for chapter_dir in $OUTPUT_ROOT/*/
        set chapter_name (basename $chapter_dir)
        
        if test "$chapter_name" = "final"; or test "$chapter_name" = "statblocks"
            continue
        end
        
        # Skip chapters marked for no OCR processing
        if contains $chapter_name $SKIP_OCR_CHAPTERS
            continue
        end
        
        # Find best input file
        set input_file ""
        for candidate in cleaned.md converted.md
            if test -f $chapter_dir/$candidate
                set input_file $chapter_dir/$candidate
                break
            end
        end
        
        if test -z "$input_file"
            continue
        end
        
        set dict_file $chapter_dir/dict_cleaned.md
        
        log_substep "Dictionary: $chapter_name..."
        
        # Planescape-specific corrections
        # These are mostly no-ops but ensure correct casing
        sed \
            -e 's/\bfactol\b/factol/gi' \
            -e 's/\bFactol\b/Factol/g' \
            -e 's/\bdabus\b/dabus/gi' \
            -e 's/\bSIGIL\b/Sigil/g' \
            -e 's/\bsigil\b/Sigil/gi' \
            -e 's/\bGodsmen\b/Godsmen/g' \
            -e 's/\bHarmonium\b/Harmonium/g' \
            -e 's/\bMercykiller\b/Mercykiller/g' \
            -e 's/\bMercykillers\b/Mercykillers/g' \
            -e 's/\bXaositect\b/Xaositect/g' \
            -e 's/\bXaositects\b/Xaositects/g' \
            -e "s/\btanar'ri\b/tanar'ri/g" \
            -e 's/\bbaatezu\b/baatezu/g' \
            -e 's/\byugoloth\b/yugoloth/g' \
            $input_file > $dict_file
    end
    
    master_checkpoint_mark "dictionary"
    log_complete
end

# ============================================================================
# STEP: LEARNED CORRECTIONS (from confidence analysis)
# ============================================================================

function step_learned_corrections
    if not test $DO_LEARNED_CORRECTIONS = true
        show_pipeline_progress "STEP 5.5: Learned Corrections [SKIPPED]"
        log_complete
        return 0
    end

    show_pipeline_progress "STEP 5.5: Learned Corrections"
    
    if master_checkpoint_exists "learned_corrections"
        log_substep "Using cached learned corrections"
        log_complete
        return 0
    end
    
    # Check if corrections.json exists
    if not test -f "./corrections.json"
        log_substep "No corrections.json found, generating from low-confidence data..."
        
        # Run the correction generator
        if test -f "./generate_corrections.fish"
            ./generate_corrections.fish $OUTPUT_ROOT 2>/dev/null
        else
            log_warn "generate_corrections.fish not found, skipping"
            log_complete
            return 0
        end
    end
    
    # Apply corrections using apply_corrections.fish
    if test -f "./apply_corrections.fish"
        log_substep "Applying learned corrections..."
        ./apply_corrections.fish $OUTPUT_ROOT --corrections ./corrections.json
        
        # Update the source file preference chain
        # The corrected.md files are now the best source
        for chapter_dir in $OUTPUT_ROOT/*/
            set chapter_name (basename $chapter_dir)
            
            if test "$chapter_name" = "final"; or test "$chapter_name" = "statblocks"; or test "$chapter_name" = "diagnostics"
                continue
            end
            
            # If corrected.md exists, it's now the best pre-AI source
            if test -f "$chapter_dir/corrected.md"
                log_substep "Applied corrections to $chapter_name"
            end
        end
    else
        log_warn "apply_corrections.fish not found, skipping"
    end
    
    master_checkpoint_mark "learned_corrections"
    log_complete
end

# ============================================================================
# STEP: AI CLEANUP (Optional)
# ============================================================================

function step_ai_cleanup
    if not test $DO_AI_CLEANUP = true
        show_pipeline_progress "STEP 6: AI Cleanup [SKIPPED]"
        log_complete
        return 0
    end

    show_pipeline_progress "STEP 6: AI Cleanup ($AI_BACKEND)"
    
    if master_checkpoint_exists "ai_cleanup"
        log_substep "Using cached AI cleanup"
        log_complete
        return 0
    end
    
    for chapter_dir in $OUTPUT_ROOT/*/
        set chapter_name (basename $chapter_dir)
        
        if test "$chapter_name" = "final"; or test "$chapter_name" = "statblocks"; or test "$chapter_name" = "diagnostics"
            continue
        end
        
        # Skip chapters marked for no OCR processing
        if contains $chapter_name $SKIP_OCR_CHAPTERS
            continue
        end
        
        # Find best input file (prefer corrected.md from learned corrections)
        set input_file ""
        for candidate in corrected.md dict_cleaned.md cleaned.md converted.md
            if test -f $chapter_dir/$candidate
                set input_file $chapter_dir/$candidate
                break
            end
        end
        
        if test -z "$input_file"
            continue
        end
        
        set ai_file $chapter_dir/ai_cleaned.md
        
        log_substep "AI processing: $chapter_name..."
        
        # Use the AI cleanup script
        if test -f ./ai_cleanup_claude.fish
            ./ai_cleanup_claude.fish $input_file $ai_file
        else
            log_warn "AI cleanup script not found, copying input"
            cp $input_file $ai_file
        end
    end
    
    master_checkpoint_mark "ai_cleanup"
    log_complete
end

# ============================================================================
# STEP: STAT BLOCK EXTRACTION
# ============================================================================

function step_extract_statblocks
    if not test $EXTRACT_STATBLOCKS = true
        show_pipeline_progress "STEP 7: Stat Block Extraction [SKIPPED]"
        log_complete
        return 0
    end

    show_pipeline_progress "STEP 7: Stat Block Extraction"
    
    if master_checkpoint_exists "statblocks"
        log_substep "Using cached stat blocks"
        log_complete
        return 0
    end
    
    set statblock_dir $OUTPUT_ROOT/statblocks
    mkdir -p $statblock_dir
    
    # Process each chapter
    for chapter_dir in $OUTPUT_ROOT/*/
        set chapter_name (basename $chapter_dir)
        
        if test "$chapter_name" = "final"; or test "$chapter_name" = "statblocks"; or test "$chapter_name" = "diagnostics"
            continue
        end
        
        # Find best input file (prefer AI cleaned, then corrected, then dict)
        set input_file ""
        for candidate in ai_cleaned.md corrected.md dict_cleaned.md cleaned.md converted.md
            if test -f $chapter_dir/$candidate
                set input_file $chapter_dir/$candidate
                break
            end
        end
        
        if test -z "$input_file"
            continue
        end
        
        log_substep "Scanning: $chapter_name..."
        
        # Run stat block extraction
        if test -f ./extract_statblocks.fish
            ./extract_statblocks.fish $input_file $statblock_dir/$chapter_name 2>/dev/null
        end
    end
    
    # Count extracted blocks
    set block_count (find $statblock_dir -name "*.md" -not -name "_all*" 2>/dev/null | wc -l)
    log_substep "Extracted $block_count stat blocks total"
    
    master_checkpoint_mark "statblocks"
    log_complete
end

# ============================================================================
# STEP: FINALIZE OUTPUT
# ============================================================================

function step_finalize
    show_pipeline_progress "STEP 8: Finalizing Output"
    
    mkdir -p $FINAL_OUTPUT
    
    for chapter_dir in $OUTPUT_ROOT/*/
        set chapter_name (basename $chapter_dir)
        
        if test "$chapter_name" = "final"; or test "$chapter_name" = "statblocks"; or test "$chapter_name" = "diagnostics"
            continue
        end
        
        # Find best source file (prefer AI cleaned, then corrected, then dict)
        set source_file ""
        for candidate in ai_cleaned.md corrected.md dict_cleaned.md cleaned.md converted.md
            if test -f $chapter_dir/$candidate
                set source_file $chapter_dir/$candidate
                break
            end
        end
        
        if test -z "$source_file"
            continue
        end
        
        set final_file $FINAL_OUTPUT/$chapter_name.md
        
        log_substep "Finalizing: $chapter_name"
        
        if test $KEEP_PAGEBREAKS = true
            cp $source_file $final_file
        else
            sed '/^<!-- PAGE BREAK:/d' $source_file > $final_file
        end
        
        # Count pages
        set page_count (grep -c "PAGE BREAK" $source_file 2>/dev/null || echo 0)
        set -g TOTAL_PAGES (math $TOTAL_PAGES + $page_count)
    end
    
    master_checkpoint_mark "finalize"
    log_complete
end

# ============================================================================
# STEP: GENERATE STATISTICS
# ============================================================================

function step_generate_stats
    show_pipeline_progress "STEP 9: Generating Statistics"
    
    set END_TIME (date +%s)
    set ELAPSED (math $END_TIME - $START_TIME)
    set MINUTES (math $ELAPSED / 60)
    set SECONDS (math $ELAPSED % 60)
    
    # Create stats file
    echo "# Conversion Statistics" > $STATS_FILE
    echo "" >> $STATS_FILE
    echo "**Generated:** "(date) >> $STATS_FILE
    echo "**Source:** $PDF_FILE" >> $STATS_FILE
    if test -n "$CONFIG_FILE"
        echo "**Config:** $CONFIG_FILE" >> $STATS_FILE
    end
    echo "" >> $STATS_FILE
    echo "## Summary" >> $STATS_FILE
    echo "" >> $STATS_FILE
    echo "| Setting | Value |" >> $STATS_FILE
    echo "|---------|-------|" >> $STATS_FILE
    echo "| Chapters | $TOTAL_CHAPTERS |" >> $STATS_FILE
    echo "| Pages | $TOTAL_PAGES |" >> $STATS_FILE
    echo "| Processing Time | $MINUTES min $SECONDS sec |" >> $STATS_FILE
    echo "| DPI | $DPI |" >> $STATS_FILE
    echo "| Parallel Jobs | $PARALLEL_JOBS |" >> $STATS_FILE
    echo "| OCR Cleanup | "(test $DO_CLEANUP = true && echo "Yes" || echo "No")" |" >> $STATS_FILE
    echo "| Dictionary | "(test $DO_DICT = true && echo "Yes" || echo "No")" |" >> $STATS_FILE
    echo "| Learned Corrections | "(test $DO_LEARNED_CORRECTIONS = true && echo "Yes" || echo "No")" |" >> $STATS_FILE
    echo "| AI Cleanup | "(test $DO_AI_CLEANUP = true && echo "Yes ($AI_BACKEND)" || echo "No")" |" >> $STATS_FILE
    echo "| Stat Blocks | "(test $EXTRACT_STATBLOCKS = true && echo "Extracted" || echo "Skipped")" |" >> $STATS_FILE
    echo "" >> $STATS_FILE
    
    # Chapter details
    echo "## Chapters" >> $STATS_FILE
    echo "" >> $STATS_FILE
    
    for final_file in $FINAL_OUTPUT/*.md
        if not test -f $final_file
            continue
        end
        
        set chapter (basename $final_file .md)
        set lines (wc -l < $final_file 2>/dev/null || echo 0)
        set words (wc -w < $final_file 2>/dev/null || echo 0)
        
        echo "### $chapter" >> $STATS_FILE
        echo "- Lines: $lines" >> $STATS_FILE
        echo "- Words: $words" >> $STATS_FILE
        echo "" >> $STATS_FILE
    end
    
    log_substep "Statistics saved to $STATS_FILE"
    log_complete
end

# ============================================================================
# STEP: ARCHIVE DIAGNOSTICS & CLEANUP TEMP
# ============================================================================

function step_archive_diagnostics
    if not test $ARCHIVE_DIAGNOSTICS = true
        show_pipeline_progress "STEP 10: Archive Diagnostics [SKIPPED]"
        log_complete
        return 0
    end

    show_pipeline_progress "STEP 10: Archive Diagnostics"
    
    if master_checkpoint_exists "diagnostics"
        log_substep "Diagnostics already archived"
        log_complete
        return 0
    end
    
    set diag_dir $OUTPUT_ROOT/diagnostics
    mkdir -p $diag_dir
    
    # Aggregate all OCR confidence reports
    log_substep "Aggregating OCR confidence reports..."
    echo "# Aggregated OCR Confidence Report" > $diag_dir/all_confidence_reports.md
    echo "" >> $diag_dir/all_confidence_reports.md
    echo "Generated: "(date) >> $diag_dir/all_confidence_reports.md
    echo "" >> $diag_dir/all_confidence_reports.md
    
    for chapter_dir in $OUTPUT_ROOT/*/
        set chapter_name (basename $chapter_dir)
        
        if test "$chapter_name" = "final"; or test "$chapter_name" = "statblocks"; or test "$chapter_name" = "diagnostics"
            continue
        end
        
        if test -f "$chapter_dir/ocr_confidence_report.txt"
            echo "## $chapter_name" >> $diag_dir/all_confidence_reports.md
            echo "" >> $diag_dir/all_confidence_reports.md
            cat "$chapter_dir/ocr_confidence_report.txt" >> $diag_dir/all_confidence_reports.md
            echo "" >> $diag_dir/all_confidence_reports.md
        end
    end
    
    # Aggregate all low-confidence words for pattern analysis
    log_substep "Analyzing low-confidence patterns..."
    echo "# Low-Confidence Word Patterns" > $diag_dir/lowconf_patterns.md
    echo "" >> $diag_dir/lowconf_patterns.md
    echo "Words with confidence below threshold, sorted by frequency" >> $diag_dir/lowconf_patterns.md
    echo "" >> $diag_dir/lowconf_patterns.md
    echo "| Count | Word | Avg Confidence |" >> $diag_dir/lowconf_patterns.md
    echo "|-------|------|----------------|" >> $diag_dir/lowconf_patterns.md
    
    # Find all lowconf files and aggregate
    set all_lowconf_files (find $OUTPUT_ROOT -name "*-lowconf.txt" -type f 2>/dev/null)
    if test (count $all_lowconf_files) -gt 0
        # Extract words and count occurrences
        for f in $all_lowconf_files
            cat $f
        end | sed 's/ (conf:.*//' | sort | uniq -c | sort -rn | head -50 | while read count word
            echo "| $count | $word | - |" >> $diag_dir/lowconf_patterns.md
        end
    end
    
    # Copy corrections.json if it exists
    if test -f "./corrections.json"
        cp ./corrections.json $diag_dir/corrections_used.json
        log_substep "Saved corrections.json to diagnostics"
    end
    
    # Cleanup temp files if enabled
    if test $CLEANUP_TEMP_FILES = true
        log_substep "Cleaning up temporary files..."
        
        set temp_dirs_removed 0
        for chapter_dir in $OUTPUT_ROOT/*/
            set chapter_name (basename $chapter_dir)
            
            if test "$chapter_name" = "final"; or test "$chapter_name" = "statblocks"; or test "$chapter_name" = "diagnostics"
                continue
            end
            
            if test -d "$chapter_dir/.temp"
                rm -rf "$chapter_dir/.temp"
                set temp_dirs_removed (math $temp_dirs_removed + 1)
            end
        end
        
        log_substep "Removed $temp_dirs_removed temp directories"
    end
    
    master_checkpoint_mark "diagnostics"
    log_complete
end

# ============================================================================
# MAIN
# ============================================================================

parse_args $argv

# Load config early to check for input PDF
load_config

# Show help if no PDF
if test -z "$PDF_FILE"
    echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
    echo (set_color cyan)"║"(set_color normal)(set_color yellow)"     HARBINGER MASTER - Complete Conversion Pipeline    "(set_color normal)(set_color cyan)"║"(set_color normal)
    echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
    echo ""
    echo "Usage: ./harbinger_master.fish [options] [input.pdf]"
    echo ""
    echo "Options:"
    echo "  --config, -c FILE   JSON configuration file (can contain input PDF)"
    echo "  --output, -o DIR    Output root directory"
    echo "  --dpi NUM           DPI for extraction (default: 300)"
    echo "  --jobs, -j NUM      Parallel jobs (default: 4)"
    echo "  --no-cleanup        Skip OCR cleanup"
    echo "  --no-dict           Skip dictionary corrections"
    echo "  --ai-claude         Enable AI cleanup with Claude"
    echo "  --no-statblocks     Skip stat block extraction"
    echo "  --open              Open results in VS Code"
    echo "  --resume            Resume from checkpoints"
    echo "  --clean             Clear all checkpoints"
    echo "  --status            Show pipeline status"
    echo "  --demo              Demo mode: only process first chapter"
    echo ""
    echo "Examples:"
    echo "  # With config file (PDF specified in config):"
    echo "  ./harbinger_master.fish --config pipeline_config.json"
    echo ""
    echo "  # Override config PDF:"
    echo "  ./harbinger_master.fish harbinger_house.pdf --config pipeline_config.json"
    echo ""
    echo "  # No config:"
    echo "  ./harbinger_master.fish harbinger_house.pdf --dpi 400 --jobs 8"
    echo ""
    exit 1
end

if not test -f "$PDF_FILE"
    log_error "PDF file not found: $PDF_FILE"
    exit 1
end

# Setup paths
if test -z "$OUTPUT_ROOT"
    set -g OUTPUT_ROOT "converted_"(basename $PDF_FILE .pdf)
end

set -g FINAL_OUTPUT "$OUTPUT_ROOT/final"
set -g STATS_FILE "$OUTPUT_ROOT/conversion_stats.md"

mkdir -p $OUTPUT_ROOT
mkdir -p $FINAL_OUTPUT

# Status only mode
if set -q STATUS_ONLY
    master_checkpoint_status
    exit 0
end

# Clean mode
if set -q CLEAN_MODE
    master_checkpoint_clear
end

# Banner
echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color yellow)"     HARBINGER MASTER - Complete Conversion Pipeline    "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""
echo (set_color green)"Input:       "(set_color normal)"$PDF_FILE"
echo (set_color green)"Output:      "(set_color normal)"$OUTPUT_ROOT"
echo (set_color green)"Config:      "(set_color normal)(test -n "$CONFIG_FILE" && echo "$CONFIG_FILE" || echo "(defaults)")
echo (set_color green)"DPI:         "(set_color normal)"$DPI"
echo (set_color green)"Parallel:    "(set_color normal)"$PARALLEL_JOBS jobs"
echo (set_color green)"Cleanup:     "(set_color normal)(test $DO_CLEANUP = true && echo "Enabled" || echo "Disabled")
echo (set_color green)"Dictionary:  "(set_color normal)(test $DO_DICT = true && echo "Enabled" || echo "Disabled")
echo (set_color green)"Learned:     "(set_color normal)(test $DO_LEARNED_CORRECTIONS = true && echo "Enabled" || echo "Disabled")
echo (set_color green)"AI Cleanup:  "(set_color normal)(test $DO_AI_CLEANUP = true && echo "Enabled ($AI_BACKEND)" || echo "Disabled")
echo (set_color green)"Stat Blocks: "(set_color normal)(test $EXTRACT_STATBLOCKS = true && echo "Enabled" || echo "Disabled")
echo (set_color green)"Diagnostics: "(set_color normal)(test $ARCHIVE_DIAGNOSTICS = true && echo "Archive & Cleanup" || echo "Keep temp files")
echo ""

# Show checkpoint status if resuming
if set -q RESUME_MODE
    master_checkpoint_status
    echo ""
end

# Record start time
set -g START_TIME (date +%s)

# Initialize pipeline step tracking (10 steps total)
set -g PIPELINE_TOTAL_STEPS 10
set -g PIPELINE_CURRENT_STEP 0

function show_pipeline_progress
    set step_name $argv[1]
    set -g PIPELINE_CURRENT_STEP (math $PIPELINE_CURRENT_STEP + 1)
    
    # Calculate ETA based on elapsed time and steps completed
    set elapsed (math (date +%s) - $START_TIME)
    set eta_str ""
    if test $PIPELINE_CURRENT_STEP -gt 1
        set avg_per_step (math --scale=0 "$elapsed / ($PIPELINE_CURRENT_STEP - 1)")
        set remaining_steps (math "$PIPELINE_TOTAL_STEPS - $PIPELINE_CURRENT_STEP + 1")
        set eta_seconds (math "$avg_per_step * $remaining_steps")
        set eta_str (format_eta $eta_seconds)
    end
    
    set progress_bar (render_progress_bar $PIPELINE_CURRENT_STEP $PIPELINE_TOTAL_STEPS 15)
    echo "" >&2
    echo (set_color cyan)"┌─["(set_color yellow)" $step_name "(set_color cyan)"] "(set_color blue)"$progress_bar"(set_color normal)" "(set_color yellow)"$eta_str"(set_color normal) >&2
end

# Run pipeline steps in correct order
# NEW ORDER: Extract -> Auto-Preprocess -> Interactive Preprocess -> OCR -> Text Cleanup
step_extract_and_preprocess
or exit 1

step_interactive_preprocessing
or exit 1

step_ocr_chapters
or exit 1

step_reprocess_lowconf
step_ocr_cleanup
step_dictionary_cleanup
step_learned_corrections
step_ai_cleanup
step_extract_statblocks
step_finalize
step_generate_stats
step_archive_diagnostics

# Final report
set END_TIME (date +%s)
set ELAPSED (math $END_TIME - $START_TIME)
set MINUTES (math $ELAPSED / 60)
set SECONDS (math $ELAPSED % 60)

echo ""
echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color green)"                 CONVERSION COMPLETE!                      "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""
echo (set_color yellow)"📊 Statistics:"(set_color normal)
echo "   Chapters:  $TOTAL_CHAPTERS"
echo "   Pages:     $TOTAL_PAGES"
echo "   Time:      $MINUTES min $SECONDS sec"
echo ""
echo (set_color yellow)"📁 Output Locations:"(set_color normal)
echo "   Final MD:     $FINAL_OUTPUT/"
echo "   Stat Blocks:  $OUTPUT_ROOT/statblocks/"
echo "   Diagnostics:  $OUTPUT_ROOT/diagnostics/"
echo "   Stats:        $STATS_FILE"
echo ""
echo (set_color yellow)"🔧 Next Steps:"(set_color normal)
echo "   1. Review final markdown: $FINAL_OUTPUT/"
echo "   2. Check extracted NPCs:  $OUTPUT_ROOT/statblocks/"
echo "   3. Review diagnostics:    $OUTPUT_ROOT/diagnostics/"
echo "   4. Merge chapters:        ./merge_chapters.fish $OUTPUT_ROOT"
echo ""

# Open in VS Code if requested
if test $OPEN_VSCODE = true
    if command -v code &>/dev/null
        log_info "Opening in VS Code..."
        code $FINAL_OUTPUT
    end
end

echo (set_color green)"✨ All done!"(set_color normal)
