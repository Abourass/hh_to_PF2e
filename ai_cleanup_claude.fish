#!/usr/bin/env fish

# ai_cleanup_claude.fish - AI-powered OCR cleanup using Claude Code
# Usage: ./ai_cleanup_claude.fish input.md output.md [--targeted lowconf_dir]
#
# Modes:
#   Standard: Prepares entire file for AI cleanup with instruction marker
#   Targeted: Extracts low-confidence words with context for focused AI review

set INPUT $argv[1]
set OUTPUT $argv[2]
set TARGETED_MODE false
set LOWCONF_DIR ""

# Parse additional arguments
for i in (seq 3 (count $argv))
    switch $argv[$i]
        case "--targeted"
            set TARGETED_MODE true
            set i_next (math $i + 1)
            if test $i_next -le (count $argv)
                set LOWCONF_DIR $argv[$i_next]
            end
    end
end

if test (count $argv) -lt 2
    echo (set_color red)"[ERROR]"(set_color normal) " Usage: ./ai_cleanup_claude.fish input.md output.md [--targeted lowconf_dir]"
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
echo (set_color green)"Mode:   "(set_color normal)(test $TARGETED_MODE = true && echo "Targeted (low-confidence focus)" || echo "Standard (full file)")
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

# ============================================================================
# TARGETED MODE: Extract low-confidence words with context
# ============================================================================

if test $TARGETED_MODE = true
    echo (set_color yellow)"[INFO]"(set_color normal) " Using targeted mode - focusing on low-confidence words"
    
    # Find lowconf files for this chapter
    set chapter_dir (dirname $INPUT)
    if test -z "$LOWCONF_DIR"
        set LOWCONF_DIR "$chapter_dir/.temp"
    end
    
    if not test -d "$LOWCONF_DIR"
        echo (set_color yellow)"[WARN]"(set_color normal) " No lowconf directory found, falling back to standard mode"
        set TARGETED_MODE false
    end
end

if test $TARGETED_MODE = true
    # Extract low-confidence words
    set lowconf_words
    for lowconf_file in $LOWCONF_DIR/*-lowconf.txt
        if test -f "$lowconf_file"
            while read -l line
                set word (string replace -r ' \(conf:.*' '' $line)
                set word (string trim $word)
                if test -n "$word"; and not contains $word $lowconf_words
                    set -a lowconf_words $word
                end
            end < $lowconf_file
        end
    end
    
    echo (set_color green)"Found "(count $lowconf_words)" unique low-confidence words"(set_color normal)
    echo ""
    
    if test (count $lowconf_words) -eq 0
        echo (set_color yellow)"[WARN]"(set_color normal) " No low-confidence words found, falling back to standard mode"
        set TARGETED_MODE false
    end
end

if test $TARGETED_MODE = true
    # Create targeted cleanup file
    echo "<!-- AI_TARGETED_CLEANUP:

You are an expert at fixing OCR errors in tabletop RPG books.

MODE: TARGETED - Focus only on the low-confidence words listed below.

LOW-CONFIDENCE WORDS DETECTED:
The following words had low OCR confidence and may be errors.
Review each one IN CONTEXT and suggest the correct word.

" > $OUTPUT

    # List the low-confidence words
    for word in $lowconf_words
        echo "- \"$word\"" >> $OUTPUT
    end
    
    echo "
INSTRUCTIONS:
1. Read through the document below
2. Find each low-confidence word in context
3. Determine if it's correct or needs fixing
4. If it's a Planescape term (berk, cutter, factol, dabus, tanar'ri, etc.) - KEEP IT
5. If it's garbled (random symbols, split words) - FIX IT
6. Output the entire corrected document

COMMON OCR ERRORS TO FIX:
- vou → you, eves → eyes, Jrom → from, rhe → the
- Split words: \"har-\" + \"binger\" → \"harbinger\"
- Garbage in headers: ¢CHAPTER → CHAPTER

PRESERVE:
- All Planescape terminology
- All D&D stats (THAC0, AC, hp, etc.)
- Page break markers

OUTPUT THE COMPLETE CORRECTED DOCUMENT:
-->

" >> $OUTPUT

    cat $INPUT >> $OUTPUT
    
    set output_size (wc -l < $OUTPUT)
    echo (set_color green)"✓ Targeted cleanup file prepared"(set_color normal)
    echo ""
    echo "  Low-conf words: "(count $lowconf_words)
    echo "  Output: $output_size lines"
    echo "  Saved:  $OUTPUT"
    echo ""
    echo (set_color cyan)"Next step: Run ./ai_process_batch.fish to process all files interactively"(set_color normal)
    echo ""
    exit 0
end

# ============================================================================
# STANDARD MODE: Full file with instruction marker
# ============================================================================

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
