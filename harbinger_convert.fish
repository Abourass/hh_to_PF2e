#!/usr/bin/env fish

# harbinger_convert.fish - Automated PDF to Markdown converter
# Usage: ./harbinger_convert.fish input.pdf output_dir

set PDF_FILE $argv[1]
set OUTPUT_DIR $argv[2]
set TEMP_DIR (mktemp -d)

# Configuration
set DPI 300

# Parse optional DPI argument
for i in (seq 3 (count $argv))
    if test $argv[$i] = "--dpi"
        set DPI $argv[(math $i + 1)]
    end
end

set CONTRAST_LEVEL 50

# Detect ImageMagick version and set command
if command -v magick &>/dev/null
    set MAGICK_CMD magick
else if command -v convert &>/dev/null
    set MAGICK_CMD convert
else
    echo (set_color red)"[ERROR]"(set_color normal) "ImageMagick not found. Please install it."
    exit 1
end

# Use Fish's native set_color instead of escape codes
function log_info
    echo (set_color green)"[INFO]"(set_color normal) $argv
end

function log_warn
    echo (set_color yellow)"[WARN]"(set_color normal) $argv
end

function log_error
    echo (set_color red)"[ERROR]"(set_color normal) $argv
end

# Validate inputs
if test (count $argv) -lt 2
    log_error "Usage: ./harbinger_convert.fish input.pdf output_dir"
    exit 1
end

if not test -f $PDF_FILE
    log_error "PDF file not found: $PDF_FILE"
    exit 1
end

mkdir -p $OUTPUT_DIR

log_info "Starting conversion pipeline..."
log_info "PDF: $PDF_FILE"
log_info "Output: $OUTPUT_DIR"
log_info "Temp directory: $TEMP_DIR"
log_info "Using ImageMagick command: $MAGICK_CMD"

# Step 1: Extract PDF pages as images
log_info "Step 1: Extracting PDF pages..."
pdftoppm -png -r $DPI $PDF_FILE $TEMP_DIR/page
set page_files $TEMP_DIR/page-*.png
log_info "Extracted "(count $page_files)" pages"

# Step 2: Process each image
log_info "Step 2: Processing images..."
set page_count 0
for img in $TEMP_DIR/page-*.png
    set page_count (math $page_count + 1)
    set basename (basename $img .png)
    
    log_info "Processing $basename..."
    
    # Convert to grayscale, increase contrast, remove noise
    $MAGICK_CMD $img \
        -colorspace Gray \
        -contrast-stretch $CONTRAST_LEVEL% \
        -level 0%,100%,1.2 \
        -despeckle \
        -blur 0x0.5 \
        -sharpen 0x1.0 \
        $TEMP_DIR/$basename-processed.png
end

# Step 3: OCR with Tesseract
log_info "Step 3: Running OCR..."
set combined_text $TEMP_DIR/combined.txt
echo "" > $combined_text

for img in $TEMP_DIR/page-*-processed.png
    set basename (basename $img -processed.png)
    log_info "OCR on $basename..."
    
    # Use Tesseract with custom config for better column detection
    tesseract $img $TEMP_DIR/$basename \
        -l eng \
        --psm 1 \
        --oem 3 \
        txt 2>/dev/null
    
    # Append to combined file with page separator
    echo "

<!-- PAGE BREAK: $basename -->

" >> $combined_text
    cat $TEMP_DIR/$basename.txt >> $combined_text
end

# Step 4: Clean up text encoding
log_info "Step 4: Cleaning text encoding..."
set cleaned_text $OUTPUT_DIR/cleaned.txt

# Fix common OCR and encoding issues
cat $combined_text | \
    sed 's/â€™/'\''/g' | \
    sed 's/â€œ/"/g' | \
    sed 's/â€/"/g' | \
    sed 's/â€"/—/g' | \
    sed 's/â€˜/'\''/g' | \
    sed 's/â€"/–/g' | \
    sed 's/Â//g' | \
    sed 's/â€¢/•/g' | \
    sed 's/  */ /g' > $cleaned_text

# Step 5: Structure markdown
log_info "Step 5: Creating structured markdown..."
set final_md $OUTPUT_DIR/converted.md

# Add frontmatter
echo "# Harbinger House - Converted Content

> Auto-converted on "(date)"

" > $final_md

cat $cleaned_text >> $final_md

# Step 6: Optional AI cleanup via local LLM
if set -q USE_OLLAMA
    log_info "Step 6: Running AI cleanup with Ollama..."
    set ai_cleaned $OUTPUT_DIR/ai_cleaned.md
    
    ollama run llama3.2 "Clean up this OCR output, fixing obvious errors, 
    maintaining original structure. Only fix clear mistakes, don't rewrite:

"(cat $final_md) > $ai_cleaned
    
    log_info "AI-cleaned version saved to: $ai_cleaned"
end

# Cleanup
log_info "Cleaning up temporary files..."
rm -rf $TEMP_DIR

log_info ""
log_info (set_color green)"✓ Conversion complete!"(set_color normal)
log_info "Output file: $final_md"
log_info "Pages processed: $page_count"

