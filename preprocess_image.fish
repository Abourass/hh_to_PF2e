#!/usr/bin/env fish

# preprocess_image.fish - Advanced image preprocessing for OCR
# Usage: ./preprocess_image.fish input.png output.png

set INPUT $argv[1]
set OUTPUT $argv[2]

# Detect ImageMagick version
if command -v magick &>/dev/null
    set MAGICK_CMD magick
else if command -v convert &>/dev/null
    set MAGICK_CMD convert
else
    echo (set_color red)"[ERROR]"(set_color normal) "ImageMagick not found"
    exit 1
end

if test (count $argv) -lt 2
    echo (set_color red)"[ERROR]"(set_color normal) "Usage: ./preprocess_image.fish input.png output.png"
    exit 1
end

echo (set_color green)"[INFO]"(set_color normal) "Processing $INPUT → $OUTPUT"

# Multi-stage processing for optimal OCR
$MAGICK_CMD $INPUT \
    -colorspace Gray \
    -deskew 40% \
    -despeckle \
    -contrast-stretch 5%x5% \
    -level 15%,85%,1.3 \
    -morphology close diamond:1 \
    -background white \
    -alpha remove \
    -alpha off \
    $OUTPUT

echo (set_color green)"✓ Done"(set_color normal)
