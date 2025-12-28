#!/usr/bin/env fish

# batch_convert.fish - Convert entire PDF book chapter by chapter
# Usage: ./batch_convert.fish harbinger_house.pdf

set PDF_FILE $argv[1]
set DPI 300

# Parse DPI if provided
for i in (seq 2 (count $argv))
    if test $argv[$i] = "--dpi"
        set DPI $argv[(math $i + 1)]
    end
end

if test (count $argv) -lt 1
    echo (set_color red)"[ERROR]"(set_color normal) "Usage: ./batch_convert.fish harbinger_house.pdf"
    exit 1
end

if not test -f "$PDF_FILE"
    echo (set_color red)"[ERROR]"(set_color normal) "PDF file not found: $PDF_FILE"
    exit 1
end

set BASE_NAME (basename $PDF_FILE .pdf)
set OUTPUT_ROOT "converted_$BASE_NAME"

mkdir -p $OUTPUT_ROOT

# Get page count
set PAGE_COUNT (pdfinfo $PDF_FILE | grep Pages | awk '{print $2}')
echo (set_color green)"[INFO]"(set_color normal) "PDF has $PAGE_COUNT pages"

# Define chapter ranges (customize for your book)
# Format: "chapter_name:start_page-end_page"
set CHAPTERS \
    "intro:1-5" \
    "chapter1:6-31" \
    "chapter2:32-52" \
    "chapter3:53-80"

for chapter_spec in $CHAPTERS
    set parts (string split ":" $chapter_spec)
    set chapter_name $parts[1]
    set page_range $parts[2]
    set range_parts (string split "-" $page_range)
    set start_page $range_parts[1]
    set end_page $range_parts[2]
    
    echo ""
    echo (set_color cyan)"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"(set_color normal)
    echo (set_color yellow)"Processing $chapter_name (pages $start_page-$end_page)..."(set_color normal)
    echo (set_color cyan)"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"(set_color normal)
    
    # Extract chapter pages to temp PDF
    set chapter_pdf $OUTPUT_ROOT/$chapter_name.pdf
    pdftk $PDF_FILE cat $start_page-$end_page output $chapter_pdf
    
    # Convert chapter
    ./harbinger_convert.fish $chapter_pdf $OUTPUT_ROOT/$chapter_name
    
    # Clean up temp PDF
    rm $chapter_pdf
end

echo ""
echo (set_color green)"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"(set_color normal)
echo (set_color green)"✓ All chapters converted to $OUTPUT_ROOT"(set_color normal)
echo (set_color green)"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"(set_color normal)
