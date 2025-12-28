#!/usr/bin/env fish

# harbinger_master.fish - Complete PDF to clean Markdown pipeline
# Usage: ./harbinger_master.fish [options] input.pdf
#
# Options:
#   --dpi NUM          DPI for image extraction (default: 300)
#   --no-cleanup       Skip OCR cleanup steps
#   --no-dict          Skip dictionary-based corrections
#   --keep-pagebreaks  Keep page break markers in output
#   --chapter NAME     Convert single chapter (e.g., intro:1-5)
#   --open             Open results in VS Code when done
#   --ai               Enable AI cleanup with Ollama
#   --ai-claude        Enable AI cleanup with Claude Code
#   --ai-ollama MODEL  Enable AI cleanup with specific Ollama model

set -g DPI 300
set -g DO_CLEANUP true
set -g DO_DICT true
set -g KEEP_PAGEBREAKS true
set -g OPEN_VSCODE false
set -g SINGLE_CHAPTER ""
set -g AI_CLEANUP false
set -g AI_BACKEND "ollama"
set -g AI_MODEL "llama3.2"

# Parse arguments
set -l pdf_file ""
for i in (seq (count $argv))
    switch $argv[$i]
        case --dpi
            set -g DPI $argv[(math $i + 1)]
        case --no-cleanup
            set -g DO_CLEANUP false
        case --no-dict
            set -g DO_DICT false
        case --keep-pagebreaks
            set -g KEEP_PAGEBREAKS true
        case --chapter
            set -g SINGLE_CHAPTER $argv[(math $i + 1)]
        case --open
            set -g OPEN_VSCODE true
        case '*.pdf'
            set pdf_file $argv[$i]
        case --ai
            set -g AI_CLEANUP true
        case --ai-claude
            set -g AI_CLEANUP true
            set -g AI_BACKEND "claude"
        case --ai-ollama
            set -g AI_CLEANUP true
            set -g AI_MODEL $argv[(math $i + 1)]
    end
end

# Validate input
if test -z "$pdf_file"
    echo (set_color red)"[ERROR]"(set_color normal) "No PDF file specified"
    echo ""
    echo "Usage: ./harbinger_master.fish [options] input.pdf"
    echo ""
    echo "Options:"
    echo "  --dpi NUM          DPI for image extraction (default: 300)"
    echo "  --no-cleanup       Skip OCR cleanup steps"
    echo "  --no-dict          Skip dictionary-based corrections"
    echo "  --keep-pagebreaks  Keep page break markers in output"
    echo "  --chapter NAME     Convert single chapter (e.g., intro:1-5)"
    echo "  --open             Open results in VS Code when done"
    echo "  --ai               Enable AI cleanup with Ollama"
    echo "  --ai-claude        Enable AI cleanup with Claude Code"
    echo "  --ai-ollama MODEL  Enable AI cleanup with Ollama (specify model)"
    exit 1
end

if not test -f "$pdf_file"
    echo (set_color red)"[ERROR]"(set_color normal) "PDF file not found: $pdf_file"
    exit 1
end

# Setup
set BASE_NAME (basename $pdf_file .pdf)
set OUTPUT_ROOT "converted_$BASE_NAME"
set FINAL_OUTPUT "$OUTPUT_ROOT/final"
set STATS_FILE "$OUTPUT_ROOT/conversion_stats.txt"

mkdir -p $FINAL_OUTPUT

# Banner
echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color yellow)"     HARBINGER HOUSE PDF CONVERSION PIPELINE           "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""
echo (set_color green)"Input:       "(set_color normal)"$pdf_file"
echo (set_color green)"Output Root: "(set_color normal)"$OUTPUT_ROOT"
echo (set_color green)"DPI:         "(set_color normal)"$DPI"
echo (set_color green)"Cleanup:     "(set_color normal)(test $DO_CLEANUP = true && echo "Enabled" || echo "Disabled")
echo (set_color green)"Dictionary:  "(set_color normal)(test $DO_DICT = true && echo "Enabled" || echo "Disabled")
echo (set_color green)"AI Cleanup:  "(set_color normal)(test $AI_CLEANUP = true && echo "Enabled ($AI_BACKEND)" || echo "Disabled")
echo ""

# Initialize stats
set -g TOTAL_CHAPTERS 0
set -g TOTAL_PAGES 0
set -g START_TIME (date +%s)

# Log function
function log_step
    echo ""
    echo (set_color cyan)"┌─["(set_color yellow)" $argv[1] "(set_color cyan)"]"(set_color normal)
end

function log_substep
    echo (set_color cyan)"│ "(set_color normal)"$argv"
end

function log_complete
    echo (set_color cyan)"└─"(set_color green)" ✓ Complete"(set_color normal)
end

# ============================================================================
# STEP 1: PDF CONVERSION
# ============================================================================

log_step "STEP 1: PDF Conversion"

if test -n "$SINGLE_CHAPTER"
    log_substep "Converting single chapter: $SINGLE_CHAPTER"
    
    set parts (string split ":" $SINGLE_CHAPTER)
    set chapter_name $parts[1]
    set page_range $parts[2]
    set range_parts (string split "-" $page_range)
    set start_page $range_parts[1]
    set end_page $range_parts[2]
    
    set chapter_pdf $OUTPUT_ROOT/$chapter_name.pdf
    pdftk $pdf_file cat $start_page-$end_page output $chapter_pdf
    
    ./harbinger_convert.fish $chapter_pdf $OUTPUT_ROOT/$chapter_name --dpi $DPI
    
    rm $chapter_pdf
    set -g TOTAL_CHAPTERS 1
else
    log_substep "Converting entire PDF by chapters"
    ./batch_convert.fish $pdf_file --dpi $DPI
    
    # Count chapters
    set -g TOTAL_CHAPTERS (count $OUTPUT_ROOT/*/converted.md)
end

log_complete

# ============================================================================
# STEP 2: OCR CLEANUP
# ============================================================================

if test $DO_CLEANUP = true
    log_step "STEP 2: OCR Cleanup"
    
    for chapter_dir in $OUTPUT_ROOT/*/
        set chapter_name (basename $chapter_dir)
        
        # Skip 'final' directory
        if test "$chapter_name" = "final"
            continue
        end
        
        set input_file $chapter_dir/converted.md
        set cleaned_file $chapter_dir/cleaned.md
        
        if not test -f $input_file
            log_substep (set_color yellow)"Skipping $chapter_name (no converted.md found)"(set_color normal)
            continue
        end
        
        # Check if input file is empty
        set line_count (wc -l < $input_file)
        if test $line_count -eq 0
            log_substep (set_color yellow)"Warning: $chapter_name/converted.md is empty"(set_color normal)
            touch $cleaned_file
            continue
        end
        
        log_substep "Cleaning $chapter_name..."
        
        # Do all cleanup in one pipeline
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
            -e 's/Pl\/â™‚/Pl\/♂/g' \
            -e 's/Pl\/â™€/Pl\/♀/g' \
            -e 's/\+HARBINGER\*\+/# HARBINGER/g' \
            -e 's/+HOUSE +'\''/HOUSE/g' \
            -e 's/CREDI\+S/CREDITS/g' \
            -e 's/BACKGR®UND/BACKGROUND/g' \
            -e 's/WHA\+ HAS GONE BEFORE/WHAT HAS GONE BEFORE/g' \
            -e 's/¢//g' \
            -e 's/\+THE HOUSE/THE HOUSE/g' | \
        sed -e 's/\bJrom\b/from/g' \
            -e 's/\bJaction\b/faction/g' \
            -e 's/\beves\b/eyes/g' \
            -e 's/\bvou\b/you/g' \
            -e 's/\bbcrk\b/berk/g' \
            -e 's/\bLadv\b/Lady/g' \
            -e 's/\blll\b/III/g' | \
        sed -e 's/^[+*]\+\([A-Z][A-Z ]\+\)[+*]\+$/## \1/g' \
            -e 's/^[+*]\([A-Z][a-z][A-Za-z ]\+\)[+*]$/### \1/g' | \
        sed -e 's/  \+/ /g' \
            -e 's/^ \+//g' \
            -e '/^$/N;/^\n$/d' \
            > $cleaned_file
    end

    log_complete
end

# ============================================================================
# STEP 3: DICTIONARY CLEANUP
# ============================================================================

if test $DO_DICT = true
    log_step "STEP 3: Dictionary-based Corrections"
    
    for chapter_dir in $OUTPUT_ROOT/*/
        set chapter_name (basename $chapter_dir)
        
        if test "$chapter_name" = "final"
            continue
        end
        
        set input_file $chapter_dir/cleaned.md
        if not test -f $input_file
            set input_file $chapter_dir/converted.md
        end
        
        if not test -f $input_file
            continue
        end
        
        # Check if empty
        set line_count (wc -l < $input_file)
        if test $line_count -eq 0
            touch $chapter_dir/dict_cleaned.md
            continue
        end
        
        set dict_file $chapter_dir/dict_cleaned.md
        
        log_substep "Applying dictionary to $chapter_name..."
        
        sed \
            -e 's/\bberk\([^a-z]\)/berk\1/g' \
            -e 's/\bberks\b/berks/g' \
            -e 's/\bbasher\b/basher/g' \
            -e 's/\bbashers\b/bashers/g' \
            -e 's/\bcutter\b/cutter/g' \
            -e 's/\bcutters\b/cutters/g' \
            -e 's/\bblood\b/blood/g' \
            -e 's/\bbloods\b/bloods/g' \
            -e 's/\bbarmy\b/barmy/g' \
            -e 's/\bbarmies\b/barmies/g' \
            -e 's/\bfactol\b/factol/g' \
            -e 's/\bfactols\b/factols/g' \
            -e 's/\bdabus\b/dabus/g' \
            -e 's/\btanar'\''ri\b/tanar'\''ri/g' \
            -e 's/\bbaatezu\b/baatezu/g' \
            -e 's/\byugoloth\b/yugoloth/g' \
            -e 's/\byugoloths\b/yugoloths/g' \
            -e 's/\bSigil\b/Sigil/g' \
            -e 's/\bthe Cage\b/the Cage/g' \
            -e 's/\bmultiverse\b/multiverse/g' \
            -e 's/\bplanewalker\b/planewalker/g' \
            -e 's/\bplanewalkers\b/planewalkers/g' \
            -e 's/\bGodsmen\b/Godsmen/g' \
            -e 's/\bHarmonium\b/Harmonium/g' \
            -e 's/\bHardhead\b/Hardhead/g' \
            -e 's/\bHardheads\b/Hardheads/g' \
            -e 's/\bMercykiller\b/Mercykiller/g' \
            -e 's/\bMercykillers\b/Mercykillers/g' \
            -e 's/\bGuvner\b/Guvner/g' \
            -e 's/\bGuvners\b/Guvners/g' \
            -e 's/\bXaositect\b/Xaositect/g' \
            -e 's/\bXaositects\b/Xaositects/g' \
            -e 's/\bAthar\b/Athar/g' \
            $input_file > $dict_file
    end
    
    log_complete
end

# ============================================================================
# STEP 4: MARKDOWN FORMATTING
# ============================================================================

log_step "STEP 4: Markdown Formatting"

for chapter_dir in $OUTPUT_ROOT/*/
    set chapter_name (basename $chapter_dir)

    if test "$chapter_name" = "final"
        continue
    end

    # Find best source file
    if test -f $chapter_dir/dict_cleaned.md
        set input_file $chapter_dir/dict_cleaned.md
    else if test -f $chapter_dir/cleaned.md
        set input_file $chapter_dir/cleaned.md
    else if test -f $chapter_dir/converted.md
        set input_file $chapter_dir/converted.md
    else
        log_substep (set_color yellow)"Skipping $chapter_name (no source file found)"(set_color normal)
        continue
    end

    # Check if empty
    set line_count (wc -l < $input_file)
    if test $line_count -eq 0
        touch $chapter_dir/formatted.md
        continue
    end

    set formatted_file $chapter_dir/formatted.md

    log_substep "Formatting $chapter_name..."

    ./markdown_format.fish $input_file $formatted_file
end

log_complete

# ============================================================================
# STEP 5: AI CLEANUP (Optional)
# ============================================================================

if test $AI_CLEANUP = true
    log_step "STEP 5: AI-Powered Cleanup"

    for chapter_dir in $OUTPUT_ROOT/*/
        set chapter_name (basename $chapter_dir)

        if test "$chapter_name" = "final"
            continue
        end

        # Use formatted file if available
        if test -f $chapter_dir/formatted.md
            set input_file $chapter_dir/formatted.md
        else if test -f $chapter_dir/dict_cleaned.md
            set input_file $chapter_dir/dict_cleaned.md
        else if test -f $chapter_dir/cleaned.md
            set input_file $chapter_dir/cleaned.md
        else
            continue
        end

        set ai_file $chapter_dir/ai_cleaned.md

        log_substep "AI processing $chapter_name with $AI_BACKEND..."

        ./ai_cleanup_claude.fish $input_file $ai_file
    end

    log_complete
end

# ============================================================================
# STEP 6: CONSOLIDATE FINAL OUTPUT
# ============================================================================

log_step "STEP 6: Creating Final Outputs"

for chapter_dir in $OUTPUT_ROOT/*/
    set chapter_name (basename $chapter_dir)
    
    if test "$chapter_name" = "final"
        continue
    end
    
    # Determine which file to use as final (prefer most processed version)
    if test -f $chapter_dir/ai_cleaned.md
        set source_file $chapter_dir/ai_cleaned.md
    else if test -f $chapter_dir/formatted.md
        set source_file $chapter_dir/formatted.md
    else if test -f $chapter_dir/dict_cleaned.md
        set source_file $chapter_dir/dict_cleaned.md
    else if test -f $chapter_dir/cleaned.md
        set source_file $chapter_dir/cleaned.md
    else if test -f $chapter_dir/converted.md
        set source_file $chapter_dir/converted.md
    else
        continue
    end
    
    set final_file $FINAL_OUTPUT/$chapter_name.md
    
    log_substep "Finalizing $chapter_name..."
    
    # Optionally remove page breaks
    if test $KEEP_PAGEBREAKS = true
        cp $source_file $final_file
    else
        sed '/^<!-- PAGE BREAK:/d' $source_file > $final_file
    end
    
    # Count pages safely
    set page_count_output (grep -c "PAGE BREAK" $source_file 2>/dev/null; or echo "0")
    set page_count (echo $page_count_output | head -1 | string trim)
    if test -z "$page_count"
        set page_count 0
    end
    set -g TOTAL_PAGES (math $TOTAL_PAGES + $page_count)
end

log_complete

# ============================================================================
# STEP 7: GENERATE STATISTICS
# ============================================================================

log_step "STEP 7: Generating Statistics"

set END_TIME (date +%s)
set ELAPSED (math $END_TIME - $START_TIME)
set MINUTES (math $ELAPSED / 60)
set SECONDS (math $ELAPSED % 60)

# Create stats file
echo "# Conversion Statistics" > $STATS_FILE
echo "" >> $STATS_FILE
echo "**Generated:** "(date) >> $STATS_FILE
echo "**Source:** $pdf_file" >> $STATS_FILE
echo "" >> $STATS_FILE
echo "## Summary" >> $STATS_FILE
echo "" >> $STATS_FILE
echo "- **Chapters Converted:** $TOTAL_CHAPTERS" >> $STATS_FILE
echo "- **Total Pages:** $TOTAL_PAGES" >> $STATS_FILE
echo "- **Processing Time:** $MINUTES minutes, $SECONDS seconds" >> $STATS_FILE
echo "- **DPI Used:** $DPI" >> $STATS_FILE
echo "- **OCR Cleanup:** "(test $DO_CLEANUP = true && echo "Yes" || echo "No") >> $STATS_FILE
echo "- **Dictionary Corrections:** "(test $DO_DICT = true && echo "Yes" || echo "No") >> $STATS_FILE
echo "- **AI Cleanup:** "(test $AI_CLEANUP = true && echo "Yes ($AI_BACKEND)" || echo "No") >> $STATS_FILE
echo "" >> $STATS_FILE
echo "## Chapters" >> $STATS_FILE
echo "" >> $STATS_FILE

for final_file in $FINAL_OUTPUT/*.md
    if not test -f $final_file
        continue
    end
    
    set chapter (basename $final_file .md)
    set lines (wc -l < $final_file)
    set words (wc -w < $final_file)
    set pages_output (grep -c "PAGE BREAK" $final_file 2>/dev/null; or echo "0")
    set pages (echo $pages_output | head -1 | string trim)
    
    echo "### $chapter" >> $STATS_FILE
    echo "" >> $STATS_FILE
    echo "- Lines: $lines" >> $STATS_FILE
    echo "- Words: $words" >> $STATS_FILE
    echo "- Pages: $pages" >> $STATS_FILE
    echo "" >> $STATS_FILE
end

log_substep "Statistics saved to $STATS_FILE"
log_complete

# ============================================================================
# FINAL REPORT
# ============================================================================

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
echo "   Final MD:  $FINAL_OUTPUT/"
echo "   Raw OCR:   $OUTPUT_ROOT/[chapter]/converted.md"
echo "   Stats:     $STATS_FILE"
echo ""
echo (set_color yellow)"🔧 Next Steps:"(set_color normal)
echo "   1. Review final markdown files in $FINAL_OUTPUT/"
echo "   2. Check statistics: cat $STATS_FILE"
echo "   3. Run quality check: ./ocr_quality_checker.fish $FINAL_OUTPUT/*.md"
echo ""

# ============================================================================
# OPEN IN VS CODE (only if requested)
# ============================================================================

if test $OPEN_VSCODE = true
    if command -v code &>/dev/null
        echo (set_color green)"Opening in VS Code..."(set_color normal)
        code $FINAL_OUTPUT
    else
        echo (set_color yellow)"VS Code not found"(set_color normal)
    end
end

echo ""
echo (set_color green)"✨ All done!"(set_color normal)
