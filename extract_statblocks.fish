#!/usr/bin/env fish

# extract_statblocks.fish - Intelligent AD&D 2e stat block extractor
# Detects stat blocks in OCR'd text and outputs formatted markdown
# Usage: ./extract_statblocks.fish input.md [output_dir]

set -g INPUT_FILE $argv[1]
set -g OUTPUT_DIR $argv[2]

# Get the directory where this script is located
set SCRIPT_DIR (dirname (status filename))

# ============================================================================
# LOGGING
# ============================================================================

function log_info
    echo (set_color green)"[INFO]"(set_color normal) $argv
end

function log_warn
    echo (set_color yellow)"[WARN]"(set_color normal) $argv
end

function log_error
    echo (set_color red)"[ERROR]"(set_color normal) $argv
end

# ============================================================================
# VALIDATION
# ============================================================================

if test -z "$INPUT_FILE"
    echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
    echo (set_color cyan)"║"(set_color normal)(set_color yellow)"     STAT BLOCK EXTRACTOR - AD&D 2e to Markdown         "(set_color normal)(set_color cyan)"║"(set_color normal)
    echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
    echo ""
    log_error "No input file specified"
    echo ""
    echo "Usage: ./extract_statblocks.fish input.md [output_dir]"
    echo ""
    echo "This tool extracts AD&D 2nd Edition stat blocks from OCR'd"
    echo "markdown text and formats them into clean, readable markdown."
    echo ""
    echo "Detected stats include:"
    echo "  • AC, THAC0, hp, MV, #AT, Dmg"
    echo "  • SA, SD, MR (Special Attacks/Defenses, Magic Resistance)"
    echo "  • Ability scores (Str, Dex, Con, Int, Wis, Cha)"
    echo "  • Size, Morale, XP, Alignment"
    echo ""
    echo "Output:"
    echo "  • Individual .md files for each NPC"
    echo "  • Combined _all_statblocks.md file"
    exit 1
end

if not test -f "$INPUT_FILE"
    log_error "Input file not found: $INPUT_FILE"
    exit 1
end

if test -z "$OUTPUT_DIR"
    set -g OUTPUT_DIR (dirname $INPUT_FILE)"/statblocks"
end

mkdir -p $OUTPUT_DIR

# Banner
echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color yellow)"     STAT BLOCK EXTRACTOR - AD&D 2e to Markdown         "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""
echo (set_color green)"Input:  "(set_color normal)"$INPUT_FILE"
echo (set_color green)"Output: "(set_color normal)"$OUTPUT_DIR"
echo ""

# Check for Python
if not command -v python3 &>/dev/null
    log_error "Python 3 is required for stat block extraction"
    exit 1
end

# Find the Python script
# Check in same directory as this script first, then current directory
set PYTHON_SCRIPT ""

if test -f "$SCRIPT_DIR/extract_statblocks.py"
    set PYTHON_SCRIPT "$SCRIPT_DIR/extract_statblocks.py"
else if test -f "./extract_statblocks.py"
    set PYTHON_SCRIPT "./extract_statblocks.py"
else if test -f (dirname $INPUT_FILE)"/extract_statblocks.py"
    set PYTHON_SCRIPT (dirname $INPUT_FILE)"/extract_statblocks.py"
end

if test -z "$PYTHON_SCRIPT"
    log_error "Could not find extract_statblocks.py"
    log_error "Make sure extract_statblocks.py is in the same directory as this script"
    exit 1
end

# Run extraction
log_info "Scanning for stat blocks..."
log_info "Using Python script: $PYTHON_SCRIPT"
echo ""

python3 $PYTHON_SCRIPT $INPUT_FILE $OUTPUT_DIR

set exit_code $status

echo ""

if test $exit_code -eq 0
    echo (set_color green)"✨ Extraction complete!"(set_color normal)
    echo "   Check $OUTPUT_DIR for extracted stat blocks"
else
    log_error "Extraction failed with exit code $exit_code"
    exit $exit_code
end
