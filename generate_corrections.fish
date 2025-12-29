#!/usr/bin/env fish

# generate_corrections.fish - Wrapper for Python-based OCR correction generator
# Analyzes low-confidence OCR words and generates corrections.json
#
# Usage: ./generate_corrections.fish [converted_dir] [--threshold N] [--output FILE]

set -g SCRIPT_DIR (dirname (status filename))

# Check for Python
if not command -v python3 &>/dev/null
    echo (set_color red)"[ERROR]"(set_color normal) " Python 3 is required"
    exit 1
end

# Find the Python script
set PYTHON_SCRIPT ""

if test -f "$SCRIPT_DIR/generate_corrections.py"
    set PYTHON_SCRIPT "$SCRIPT_DIR/generate_corrections.py"
else if test -f "./generate_corrections.py"
    set PYTHON_SCRIPT "./generate_corrections.py"
else
    echo (set_color red)"[ERROR]"(set_color normal) " Could not find generate_corrections.py"
    exit 1
end

# Pass all arguments to Python script
python3 $PYTHON_SCRIPT $argv
exit $status
