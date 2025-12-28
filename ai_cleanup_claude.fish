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
echo (set_color cyan)"║"(set_color normal)(set_color yellow)"    AI CLEANUP PREP (INTERACTIVE MODE REQUIRED)        "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""

# Check file size
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

# NOTE: Claude Code requires interactive permission for AI processing
# This script now acts as a passthrough, marking files for interactive AI cleanup
# Run ai_process_batch.fish after the pipeline completes to process all files

echo (set_color yellow)"[INFO]"(set_color normal) " Preparing file for interactive AI cleanup..."
echo (set_color yellow)"[INFO]"(set_color normal) " Claude Code cannot run non-interactively in pipelines"
echo ""

# Copy input to output with instructions marker
echo "<!-- AI_CLEANUP_INSTRUCTIONS:

You are an expert at cleaning OCR output from tabletop RPG books and converting to proper markdown.

RULES FOR CLEANUP:
1. Fix OCR mistakes: vou→you, eves→eyes, Jrom→from, Jaction→faction, rhe→the, wilh→with, thar→that, bcrk→berk, Ladv→Lady, lll→III
2. Fix encoding: â€™→', â€œ→\", â€→\", Â→(remove), â€"→—, â€"→–, â€¢→•, ¢→(remove), ®→(remove)
3. Fix common OCR errors in headers: remove stray + * symbols from titles

RULES FOR MARKDOWN FORMATTING:
1. Convert ALL CAPS HEADERS to proper markdown headers (# for h1, ## for h2, ### for h3)
2. Preserve page break comments but clean them up: <!-- PAGE BREAK: page-N -->
3. Create proper lists where appropriate (use - or * for bullet points)
4. Format stat blocks and game stats consistently
5. Use **bold** for emphasis on important terms (first use of proper nouns like \"Factol Ambar\", \"Harbinger House\")
6. Use > blockquotes for flavor text or quotes
7. Remove extra blank lines (max 2 consecutive blank lines)
8. Fix broken paragraphs - if a sentence continues on the next line, join them

PRESERVE COMPLETELY:
- Planescape slang: berk, basher, cutter, blood, barmy, factol, dabus, Sigil, the Cage, multiverse, planewalker, tanar'ri, baatezu, yugoloth
- Faction names: Godsmen, Harmonium, Hardheads, Mercykillers, Guvners, Xaositects, Athar
- D&D stats: THAC0, AC, hp, HD, etc.
- Existing markdown formatting
- Page break markers

OUTPUT ONLY THE CLEANED, FORMATTED MARKDOWN - NO EXPLANATIONS OR PREAMBLE

-->
" > $OUTPUT

cat $INPUT >> $OUTPUT

set output_size (wc -l < $OUTPUT)
set final_words (wc -w < $OUTPUT)

echo (set_color green)"✓ File prepared for AI cleanup"(set_color normal)
echo ""
echo "  Input:  $file_size lines"
echo "  Output: $output_size lines (with marker)"
echo "  Words:  $final_words"
echo "  Saved:  $OUTPUT"
echo ""
echo (set_color cyan)"Next step: Run ./ai_process_batch.fish to process all files interactively"(set_color normal)
echo ""
