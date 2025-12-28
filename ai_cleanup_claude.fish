#!/usr/bin/env fish

# ai_cleanup_claude.fish - AI-powered OCR cleanup using Claude Code
# Usage: ./ai_cleanup_claude.fish input.md output.md

set INPUT $argv[1]
set OUTPUT $argv[2]

if test (count $argv) -lt 2
    echo (set_color red)"[ERROR]"(set_color normal) " Usage: ./ai_cleanup_claude.fish input.md output.md"
    exit 1
end

if not test -f "$INPUT"
    echo (set_color red)"[ERROR]"(set_color normal) " Input file not found: $INPUT"
    exit 1
end

echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color yellow)"        AI-POWERED OCR CLEANUP (CLAUDE CODE)           "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""

# Check if Claude Code is available
if not command -v claude &>/dev/null
    echo (set_color red)"[ERROR]"(set_color normal) " Claude Code not found in PATH"
    echo ""
    echo "Install Claude Code from: https://github.com/anthropics/claude-code"
    exit 1
end

# Check file size - chunk if needed
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

# Create working directory in current path (not /tmp)
set WORK_DIR ".claude_temp_"(random)
mkdir -p $WORK_DIR

# Create the system prompt
set SYSTEM_PROMPT "You are an expert at cleaning OCR output from tabletop RPG books. Fix ONLY obvious OCR errors while preserving ALL original formatting.

RULES:
1. Fix OCR mistakes: vou→you, eves→eyes, Jrom→from, Jaction→faction, rhe→the, wilh→with, thar→that
2. Fix encoding: â€™→', â€œ→\", â€→\"
3. Fix headers: remove + * ® ¢ symbols from headers
4. PRESERVE: markdown (#, **, *), stat blocks (THAC0, AC, hp), Planescape terms (berk, basher, cutter, factol, dabus, Sigil)
5. OUTPUT ONLY THE CLEANED TEXT - NO EXPLANATIONS

Clean this OCR text:"

echo (set_color yellow)"[1/2]"(set_color normal) " Processing with Claude Code..."

# Create prompt file in working directory
echo "$SYSTEM_PROMPT

"(cat $INPUT) > $WORK_DIR/to_clean.txt

# Call Claude Code from working directory
cd $WORK_DIR

if claude to_clean.txt > output.txt 2>error.log
    echo (set_color yellow)"[2/2]"(set_color normal) " Saving cleaned output..."
    
    # Clean up any AI preamble
    sed -e '/^Here is the cleaned/d' \
        -e '/^I'\''ve fixed/d' \
        -e '/^The cleaned text/d' \
        -e '/^Here'\''s the/d' \
        -e '/^I need permission/d' \
        output.txt > ../temp_output.md
    
    cd ..
    mv temp_output.md $OUTPUT
else
    echo (set_color red)"[ERROR]"(set_color normal) " Claude Code failed"
    if test -f $WORK_DIR/error.log
        cat $WORK_DIR/error.log
    end
    cd ..
    cp $INPUT $OUTPUT  # Fallback to original
end

# Cleanup working directory
rm -rf $WORK_DIR

# Validation
if not test -f $OUTPUT
    echo ""
    echo (set_color red)"✗ Output file was not created"(set_color normal)
    exit 1
end

set output_size (wc -l < $OUTPUT)

# Sanity check - avoid division by zero
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

set final_words (wc -w < $OUTPUT)

echo ""
echo "  Input:  $file_size lines"
echo "  Output: $output_size lines"
echo "  Words:  $final_words"
echo "  Saved:  $OUTPUT"
echo ""
