#!/usr/bin/env fish

# fix_encoding.fish - Fix common OCR encoding issues
# Usage: ./fix_encoding.fish input.md output.md

set INPUT $argv[1]
set OUTPUT $argv[2]

if test (count $argv) -lt 2
    echo (set_color red)"[ERROR]"(set_color normal) "Usage: ./fix_encoding.fish input.md output.md"
    exit 1
end

if not test -f "$INPUT"
    echo (set_color red)"[ERROR]"(set_color normal) "Input file not found: $INPUT"
    exit 1
end

echo (set_color green)"[INFO]"(set_color normal) "Fixing encoding: $INPUT → $OUTPUT"

# Fix encoding issues commonly introduced by OCR
cat $INPUT | \
# Unicode/encoding fixes
sed -e 's/â€™/'\''/g' \
    -e 's/â€œ/"/g' \
    -e 's/â€/"/g' \
    -e 's/â€"/—/g' \
    -e 's/â€˜/'\''/g' \
    -e 's/â€"/–/g' \
    -e 's/Â//g' \
    -e 's/â€¢/•/g' \
    -e 's/â„¢/™/g' \
    -e 's/Ã©/é/g' \
    -e 's/Ã¨/è/g' \
    -e 's/Ã¯/ï/g' \
    -e 's/Ã¶/ö/g' \
    -e 's/Ã¼/ü/g' | \
# Planescape-specific OCR fixes
sed -e 's/Facto1/Factol/g' \
    -e 's/Pl\/â™‚/Pl\/♂/g' \
    -e 's/Pl\/â™€/Pl\/♀/g' | \
# Header cleanup (remove garbage characters)
sed -e 's/\+HARBINGER\*\+/# HARBINGER/g' \
    -e 's/+HOUSE +'\'''/HOUSE/g' \
    -e 's/CREDI\+S/CREDITS/g' \
    -e 's/BACKGR®UND/BACKGROUND/g' \
    -e 's/WHA\+ HAS GONE BEFORE/WHAT HAS GONE BEFORE/g' \
    -e 's/¢//g' \
    -e 's/\+THE HOUSE/THE HOUSE/g' | \
# Remove stray special characters from headers
sed -e 's/^[+*®¢]\+\([A-Z]\)/\1/g' \
    -e 's/[+*®¢]\+$//g' \
> $OUTPUT

# Count changes
set input_size (wc -c < $INPUT)
set output_size (wc -c < $OUTPUT)
set diff_size (math "abs($input_size - $output_size)")

echo (set_color green)"✓ Done"(set_color normal)
echo "  Input:  $input_size bytes"
echo "  Output: $output_size bytes"
echo "  Diff:   $diff_size bytes"
