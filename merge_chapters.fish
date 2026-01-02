#!/usr/bin/env fish

# merge_chapters.fish - Combine all chapters into master document
# Usage: ./merge_chapters.fish converted_dir [options]
#
# Options:
#   --output FILE       Output filename (default: harbinger_house_complete.md)
#   --no-toc            Skip table of contents
#   --no-pagebreaks     Remove page break markers
#   --chapter-prefix    Add "Chapter" prefix to headings
#   --pdf               Also generate PDF (requires pandoc)

# Source progress utilities
source (dirname (status filename))/progress_utils.fish

set CONVERTED_DIR $argv[1]
set OUTPUT_FILE "harbinger_house_complete.md"
set GENERATE_TOC true
set REMOVE_PAGEBREAKS false
set CHAPTER_PREFIX false
set GENERATE_PDF false

# Parse options
for i in (seq 2 (count $argv))
    switch $argv[$i]
        case --output
            set OUTPUT_FILE $argv[(math $i + 1)]
        case --no-toc
            set GENERATE_TOC false
        case --no-pagebreaks
            set REMOVE_PAGEBREAKS true
        case --chapter-prefix
            set CHAPTER_PREFIX true
        case --pdf
            set GENERATE_PDF true
    end
end

# Validate input
if test -z "$CONVERTED_DIR"
    echo (set_color red)"[ERROR]"(set_color normal) " No input directory specified"
    echo ""
    echo "Usage: ./merge_chapters.fish converted_dir [options]"
    echo ""
    echo "Options:"
    echo "  --output FILE       Output filename (default: harbinger_house_complete.md)"
    echo "  --no-toc            Skip table of contents"
    echo "  --no-pagebreaks     Remove page break markers"
    echo "  --chapter-prefix    Add 'Chapter' prefix to headings"
    echo "  --pdf               Also generate PDF (requires pandoc)"
    exit 1
end

if not test -d "$CONVERTED_DIR"
    echo (set_color red)"[ERROR]"(set_color normal) " Directory not found: $CONVERTED_DIR"
    exit 1
end

echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color yellow)"           HARBINGER HOUSE CHAPTER MERGER                "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""

# Find all chapter files - use pipeline_config.json for ordering if available
set CONFIG_FILE "pipeline_config.json"
set CHAPTER_FILES

if test -f "$CONFIG_FILE"
    # Read chapter order from config file
    set chapter_names (jq -r '.chapters[].name' "$CONFIG_FILE" 2>/dev/null)
    if test -n "$chapter_names"
        for chapter_name in $chapter_names
            set chapter_path "$CONVERTED_DIR/final/$chapter_name.md"
            if test -f "$chapter_path"
                set -a CHAPTER_FILES "$chapter_path"
            else
                echo (set_color yellow)"[WARN]"(set_color normal) " Chapter file not found: $chapter_path"
            end
        end
    end
end

# Fallback to alphabetical glob if no config or no chapters found
if test (count $CHAPTER_FILES) -eq 0
    set CHAPTER_FILES $CONVERTED_DIR/final/*.md
end

if test (count $CHAPTER_FILES) -eq 0
    echo (set_color red)"[ERROR]"(set_color normal) " No chapter files found in $CONVERTED_DIR/final/"
    exit 1
end

echo (set_color green)"Found "(count $CHAPTER_FILES)" chapter files"(set_color normal)
echo ""

# Create temporary working file
set TEMP_FILE (mktemp)

# ============================================================================
# FRONTMATTER
# ============================================================================

echo (set_color yellow)"[1/5]"(set_color normal) " Creating frontmatter..."

echo "# Harbinger House" > $TEMP_FILE
echo "" >> $TEMP_FILE
echo "_A PLANESCAPE Adventure_" >> $TEMP_FILE
echo "" >> $TEMP_FILE
echo "**Converted from PDF on** "(date +"%B %d, %Y") >> $TEMP_FILE
echo "" >> $TEMP_FILE
echo "---" >> $TEMP_FILE
echo "" >> $TEMP_FILE

# ============================================================================
# TABLE OF CONTENTS
# ============================================================================

if test $GENERATE_TOC = true
    echo (set_color yellow)"[2/5]"(set_color normal) " Generating table of contents..."
    
    echo "## Table of Contents" >> $TEMP_FILE
    echo "" >> $TEMP_FILE
    
    set chapter_num 0
    for chapter_file in $CHAPTER_FILES
        set chapter_num (math $chapter_num + 1)
        set chapter_name (basename $chapter_file .md)
        set chapter_title (string replace -a "_" " " $chapter_name | string replace -ra '^(\w)' (string upper '$1'))
        
        # Count sections in chapter
        set sections (grep "^## " $chapter_file | sed 's/^## //' | head -5)
        
        if test $CHAPTER_PREFIX = true
            echo "$chapter_num. [Chapter $chapter_num: $chapter_title](#chapter-$chapter_num)" >> $TEMP_FILE
        else
            echo "$chapter_num. [$chapter_title](#"(string lower $chapter_name | string replace -a " " "-")")" >> $TEMP_FILE
        end
        
        # Add subsections to TOC
        if test -n "$sections"
            for section in $sections
                set section_link (string lower $section | string replace -a " " "-" | string replace -ra '[^a-z0-9-]' '')
                echo "   - [$section](#$section_link)" >> $TEMP_FILE
            end
        end
    end
    
    echo "" >> $TEMP_FILE
    echo "---" >> $TEMP_FILE
    echo "" >> $TEMP_FILE
else
    echo (set_color yellow)"[2/5]"(set_color normal) " Skipping table of contents..."
end

# ============================================================================
# MERGE CHAPTERS
# ============================================================================

echo (set_color yellow)"[3/5]"(set_color normal) " Merging chapters..."

set chapter_num 0
set total_pages 0
set total_words 0
set total_chapter_count (count $CHAPTER_FILES)

progress_start $total_chapter_count "Merging chapters"

for chapter_file in $CHAPTER_FILES
    set chapter_num (math $chapter_num + 1)
    set chapter_name (basename $chapter_file .md)
    set chapter_title (string replace -a "_" " " $chapter_name | string replace -ra '^(\w)' (string upper '$1'))
    
    echo "   Processing: $chapter_title"
    
    # Add chapter heading
    echo "" >> $TEMP_FILE
    echo "" >> $TEMP_FILE
    
    if test $CHAPTER_PREFIX = true
        echo "# Chapter $chapter_num: $chapter_title" >> $TEMP_FILE
    else
        echo "# $chapter_title" >> $TEMP_FILE
    end
    
    echo "" >> $TEMP_FILE
    
    # Process chapter content
    if test $REMOVE_PAGEBREAKS = true
        # Remove page breaks and merge
        sed '/^<!-- PAGE BREAK:/d' $chapter_file | \
        sed '/^# Harbinger House - Converted Content/,/^---$/d' >> $TEMP_FILE
    else
        # Keep page breaks
        sed '/^# Harbinger House - Converted Content/,/^---$/d' $chapter_file >> $TEMP_FILE
    end
    
    # Update statistics
    set page_count (grep -c "PAGE BREAK" $chapter_file || echo 0)
    set word_count (wc -w < $chapter_file)
    set total_pages (math $total_pages + $page_count)
    set total_words (math $total_words + $word_count)
    
    progress_update $chapter_num
end

progress_finish

# ============================================================================
# ADD APPENDIX
# ============================================================================

echo (set_color yellow)"[4/5]"(set_color normal) " Adding appendix..."

echo "" >> $TEMP_FILE
echo "" >> $TEMP_FILE
echo "---" >> $TEMP_FILE
echo "" >> $TEMP_FILE
echo "# Appendix: Conversion Notes" >> $TEMP_FILE
echo "" >> $TEMP_FILE
echo "## Conversion Statistics" >> $TEMP_FILE
echo "" >> $TEMP_FILE
echo "- **Total Chapters:** $chapter_num" >> $TEMP_FILE
echo "- **Total Pages:** $total_pages" >> $TEMP_FILE
echo "- **Total Words:** $total_words" >> $TEMP_FILE
echo "- **Conversion Date:** "(date) >> $TEMP_FILE
echo "" >> $TEMP_FILE
echo "## Source Material" >> $TEMP_FILE
echo "" >> $TEMP_FILE
echo "This document was converted from the original Planescape module" >> $TEMP_FILE
echo "\"Harbinger House\" published by TSR, Inc." >> $TEMP_FILE
echo "" >> $TEMP_FILE
echo "Conversion process:" >> $TEMP_FILE
echo "1. PDF extraction at "(test $REMOVE_PAGEBREAKS = true && echo "300+ DPI" || echo "300 DPI") >> $TEMP_FILE
echo "2. OCR with Tesseract" >> $TEMP_FILE
echo "3. Automated cleanup and encoding fixes" >> $TEMP_FILE
echo "4. Dictionary-based Planescape terminology corrections" >> $TEMP_FILE
echo "5. Manual review and quality checking" >> $TEMP_FILE
echo "" >> $TEMP_FILE

# ============================================================================
# FINALIZE
# ============================================================================

echo (set_color yellow)"[5/5]"(set_color normal) " Creating final output..."

# Copy to final output
cp $TEMP_FILE $OUTPUT_FILE
rm $TEMP_FILE

# Generate stats
set final_lines (wc -l < $OUTPUT_FILE)
set final_words (wc -w < $OUTPUT_FILE)
set final_size (du -h $OUTPUT_FILE | cut -f1)

# ============================================================================
# GENERATE PDF (optional)
# ============================================================================

if test $GENERATE_PDF = true
    if command -v pandoc &>/dev/null
        echo ""
        echo (set_color yellow)"[BONUS]"(set_color normal) " Generating PDF..."
        
        set PDF_OUTPUT (string replace ".md" ".pdf" $OUTPUT_FILE)
        
        pandoc $OUTPUT_FILE \
            -o $PDF_OUTPUT \
            --toc \
            --toc-depth=2 \
            -V geometry:margin=1in \
            -V fontsize=11pt \
            -V documentclass=book \
            --pdf-engine=xelatex
        
        echo (set_color green)"   ✓ PDF created: $PDF_OUTPUT"(set_color normal)
    else
        echo ""
        echo (set_color red)"   ✗ Pandoc not found, skipping PDF generation"(set_color normal)
        echo (set_color yellow)"   Install with: sudo apt install pandoc texlive-xetex"(set_color normal)
    end
end

# ============================================================================
# FINAL REPORT
# ============================================================================

echo ""
echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color green)"                  MERGE COMPLETE!                          "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""
echo (set_color yellow)"📊 Final Document Statistics:"(set_color normal)
echo "   Chapters:     $chapter_num"
echo "   Pages:        $total_pages"
echo "   Lines:        $final_lines"
echo "   Words:        $final_words"
echo "   File Size:    $final_size"
echo ""
echo (set_color yellow)"📁 Output Files:"(set_color normal)
echo "   Markdown:     $OUTPUT_FILE"
if test $GENERATE_PDF = true -a (command -v pandoc &>/dev/null)
    set PDF_OUTPUT (string replace ".md" ".pdf" $OUTPUT_FILE)
    echo "   PDF:          $PDF_OUTPUT"
end
echo ""

# Offer to open
if command -v code &>/dev/null
    echo -n "Open merged document in VS Code? [y/N] "
    read response
    if test "$response" = "y" -o "$response" = "Y"
        code $OUTPUT_FILE
    end
end

echo ""
echo (set_color green)"✨ All done!"(set_color normal)
