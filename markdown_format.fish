#!/usr/bin/env fish

# markdown_format.fish - Convert OCR text to proper markdown
# Usage: ./markdown_format.fish input.md output.md

set INPUT $argv[1]
set OUTPUT $argv[2]

if test (count $argv) -lt 2
    echo (set_color red)"[ERROR]"(set_color normal) " Usage: ./markdown_format.fish input.md output.md"
    exit 1
end

if not test -f "$INPUT"
    echo (set_color red)"[ERROR]"(set_color normal) " Input file not found: $INPUT"
    exit 1
end

echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color yellow)"           MARKDOWN FORMATTING PROCESSOR               "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""

set file_size (wc -l < $INPUT)
echo (set_color green)"Input:  "(set_color normal)"$INPUT"
echo (set_color green)"Size:   "(set_color normal)"$file_size lines"
echo ""

# Check if input is empty
if test $file_size -eq 0
    echo (set_color yellow)"⚠ Warning: Input file is empty, creating empty output"(set_color normal)
    touch $OUTPUT
    exit 0
end

echo (set_color yellow)"[1/6]"(set_color normal) " Cleaning headers and titles..."

# Step 1: Fix headers - remove stray symbols and convert to markdown
cat $INPUT | \
    sed -e 's/^+*\([A-Z][A-Z ]\{3,\}\)+*$/## \1/g' \
        -e 's/^[*+]\+\([A-Z][A-Za-z ]\+\)[*+]\+$/### \1/g' \
        -e 's/CREDI+S/## CREDITS/g' \
        -e 's/^THE TALE oF$/## THE TALE OF/g' \
        -e 's/^HARBINGER HOUSE$/# HARBINGER HOUSE/g' \
        -e 's/^BACKGROUND$/## BACKGROUND/g' \
        -e 's/^THE HOUSE$/### THE HOUSE/g' \
        -e 's/^WHA+ HAS GONE BEFORE$/### WHAT HAS GONE BEFORE/g' \
        -e 's/^THE PLANARI+Y$/### THE PLANARITY/g' \
        -e 's/^AND tHE FOCRUX$/AND THE FOCRUX/g' \
        -e 's/^S®UGAD AND TR@®LAN$/### SOUGAD AND TROLAN/g' \
        -e 's/^SUMMARY OF tHE$/### SUMMARY OF THE/g' \
        -e 's/^ADVEN+F+URE$/ADVENTURE/g' \
        -e 's/^CONTENTS$/## CONTENTS/g' > /tmp/md_step1.txt

echo (set_color yellow)"[2/6]"(set_color normal) " Fixing broken paragraphs..."

# Step 2: Join broken paragraphs and fix hyphenation
# This uses awk to intelligently join lines
awk '
BEGIN { buffer = "" }
{
    # Skip page breaks - pass through immediately
    if ($0 ~ /^<!-- PAGE BREAK/) {
        if (buffer != "") {
            print buffer
            buffer = ""
        }
        print $0
        next
    }

    # Skip markdown headers
    if ($0 ~ /^#+ /) {
        if (buffer != "") {
            print buffer
            buffer = ""
        }
        print $0
        next
    }

    # Handle blank lines
    if ($0 ~ /^[[:space:]]*$/) {
        if (buffer != "") {
            print buffer
            buffer = ""
        }
        print $0
        next
    }

    # Handle hyphenation at end of line
    if (buffer ~ /-$/ && $0 !~ /^[[:space:]]*$/ && $0 !~ /^#+ /) {
        # Remove hyphen and join without space
        sub(/-$/, "", buffer)
        buffer = buffer $0
        next
    }

    # Handle lines ending with hyphen followed by newline mid-word
    if ($0 ~ /^[a-z]/ && buffer ~ /-[[:space:]]*$/) {
        sub(/-[[:space:]]*$/, "", buffer)
        buffer = buffer $0
        next
    }

    # Merge consecutive markdown headers
    if ($0 ~ /^## / && buffer ~ /^## /) {
        buffer = buffer " " substr($0, 4)
        next
    }

    # Join lines that are part of the same paragraph
    if (buffer != "" && $0 !~ /^[[:space:]]*$/ && $0 !~ /^#+ / && $0 !~ /^>/ && $0 !~ /^[-*]/) {
        # If previous line doesnt end with punctuation and this line starts lowercase, join
        if (buffer !~ /[.!?:"]$/ && $0 ~ /^[a-z]/) {
            buffer = buffer " " $0
            next
        }
    }

    # Otherwise, print buffer and start new one
    if (buffer != "") {
        print buffer
    }
    buffer = $0
}
END {
    if (buffer != "") {
        print buffer
    }
}
' /tmp/md_step1.txt > /tmp/md_step2.txt

echo (set_color yellow)"[3/6]"(set_color normal) " Cleaning up extra blank lines..."

# Step 3: Remove excessive blank lines (max 2 consecutive)
cat /tmp/md_step2.txt | \
    cat -s | \
    awk 'BEGIN {blanks=0}
         /^[[:space:]]*$/ {blanks++; if (blanks<=2) print; next}
         {blanks=0; print}' > /tmp/md_step3.txt

echo (set_color yellow)"[4/6]"(set_color normal) " Formatting special elements..."

# Step 4: Clean up page breaks and remove OCR garbage
cat /tmp/md_step3.txt | \
    sed -e 's/<!-- PAGE BREAK: page-\([0-9]*\) -->/<!-- PAGE BREAK: page-\1 -->/g' \
        -e '/^| .*$/d' \
        -e '/^By =.*$/d' \
        -e '/^f De Ge/d' \
        -e '/^— FAC.*$/d' \
        -e '/^er +He.*$/d' \
        -e '/^+[0-9]\+$/d' \
        -e '/^\*[0-9]$/d' \
        -e '/^[a-z]$/d' \
        -e '/^AN /d' \
        -e 's/powersto-be/powers-to-be/g' \
        -e 's/powers-to- be/powers-to-be/g' > /tmp/md_step4.txt

echo (set_color yellow)"[5/6]"(set_color normal) " Fixing remaining OCR errors..."

# Step 5: Fix remaining common OCR mistakes
cat /tmp/md_step4.txt | \
    sed -e 's/\bthar\b/that/g' \
        -e 's/\boF\b/OF/g' \
        -e 's/\btHE\b/THE/g' \
        -e 's/ — / — /g' \
        -e 's/  \+/ /g' > /tmp/md_step5.txt

echo (set_color yellow)"[6/6]"(set_color normal) " Writing output..."

# Step 6: Final cleanup and write
cat /tmp/md_step5.txt > $OUTPUT

# Cleanup temp files
rm -f /tmp/md_step*.txt

# Validation
if not test -f $OUTPUT
    echo ""
    echo (set_color red)"✗ Output file was not created"(set_color normal)
    exit 1
end

set output_size (wc -l < $OUTPUT)
set final_words (wc -w < $OUTPUT)

# Calculate size difference
if test $file_size -gt 0
    set size_diff (math "abs($output_size - $file_size)")
    set size_change_pct (math "$size_diff * 100 / $file_size")

    echo ""
    if test $size_change_pct -gt 30
        echo (set_color yellow)"⚠ Size changed by $size_change_pct% - this is normal due to paragraph joining"(set_color normal)
    else
        echo (set_color green)"✓ Complete!"(set_color normal)
    end
else
    echo ""
    echo (set_color green)"✓ Complete!"(set_color normal)
end

echo ""
echo "  Input:  $file_size lines"
echo "  Output: $output_size lines"
echo "  Words:  $final_words"
echo "  Saved:  $OUTPUT"
echo ""
