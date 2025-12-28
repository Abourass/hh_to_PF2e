#!/usr/bin/env fish

# ai_cleanup_ollama.fish - AI-powered final cleanup using Ollama
# Usage: ./ai_cleanup_ollama.fish input.md output.md [model]

set INPUT $argv[1]
set OUTPUT $argv[2]
set MODEL "llama3.2"

if test (count $argv) -ge 3
    set MODEL $argv[3]
end

if test (count $argv) -lt 2
    echo (set_color red)"[ERROR]"(set_color normal) " Usage: ./ai_cleanup_ollama.fish input.md output.md [model]"
    exit 1
end

if not test -f "$INPUT"
    echo (set_color red)"[ERROR]"(set_color normal) " Input file not found: $INPUT"
    exit 1
end

echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color yellow)"       AI CLEANUP WITH OLLAMA ($MODEL)                  "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""

# Check if Ollama is available
if not command -v ollama &>/dev/null
    echo (set_color red)"[ERROR]"(set_color normal) " Ollama not found in PATH"
    echo ""
    echo "Install Ollama from: https://ollama.ai"
    echo "Then run: ollama pull $MODEL"
    exit 1
end

set file_size (wc -l < $INPUT)
echo (set_color green)"Input:  "(set_color normal)"$INPUT"
echo (set_color green)"Size:   "(set_color normal)"$file_size lines"
echo (set_color green)"Model:  "(set_color normal)"$MODEL"
echo ""

# Check if input is empty
if test $file_size -eq 0
    echo (set_color yellow)"⚠ Warning: Input file is empty, creating empty output"(set_color normal)
    touch $OUTPUT
    exit 0
end

echo (set_color yellow)"[1/2]"(set_color normal) " Processing with Ollama AI..."

# Create temporary file for output
set TEMP_OUTPUT (mktemp)
set TEMP_INPUT (mktemp)

# Write content to temp file
cat $INPUT > $TEMP_INPUT

# Call Ollama with a simpler, more direct prompt
ollama run $MODEL "Fix OCR errors and merge split headers in this D&D book markdown. Keep ALL game terms (THAC0, factol, dabus, tanar'ri, etc). Fix: 'bro-ken'→'broken', '## THE TALE OF\n## HARBINGER HOUSE'→'## THE TALE OF HARBINGER HOUSE'. Remove artifacts like '+2+'. Output ONLY the cleaned markdown, no commentary:

"(cat $TEMP_INPUT) > $TEMP_OUTPUT 2>/dev/null

rm -f $TEMP_INPUT

if test $status -eq 0
    echo (set_color yellow)"[2/2]"(set_color normal) " Saving cleaned output..."

    # Remove any AI preamble/commentary that might have slipped through
    cat $TEMP_OUTPUT | \
        sed -e '/^Here is the cleaned/d' \
            -e '/^Here'\''s the cleaned/d' \
            -e '/^I'\''ve cleaned/d' \
            -e '/^The cleaned/d' \
            -e '/^# Cleaned/d' \
            -e '1{/^[[:space:]]*$/d}' > $OUTPUT

    rm -f $TEMP_OUTPUT
else
    echo (set_color red)"[ERROR]"(set_color normal) " Ollama processing failed"
    rm -f $TEMP_OUTPUT
    # Fallback: copy input to output
    cp $INPUT $OUTPUT
    exit 1
end

# Validation
if not test -f $OUTPUT
    echo ""
    echo (set_color red)"✗ Output file was not created"(set_color normal)
    exit 1
end

set output_size (wc -l < $OUTPUT)
set final_words (wc -w < $OUTPUT)

# Sanity check
if test $file_size -gt 0
    set size_diff (math "abs($output_size - $file_size)")
    set size_change_pct (math "$size_diff * 100 / $file_size")

    echo ""
    if test $size_change_pct -gt 50
        echo (set_color yellow)"⚠ Warning: Output size changed by $size_change_pct% - review recommended"(set_color normal)
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
