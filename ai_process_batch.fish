#!/usr/bin/env fish

# ai_process_batch.fish - Find all files needing AI cleanup
# This script is meant to be run WITH Claude Code interactively
# Usage: ./ai_process_batch.fish

set OUTPUT_ROOT "converted_harbinger_house"

if not test -d "$OUTPUT_ROOT"
    echo (set_color red)"[ERROR]"(set_color normal) " Output directory not found: $OUTPUT_ROOT"
    echo ""
    echo "Have you run the conversion pipeline yet?"
    echo "Run: ./harbinger_master.fish harbinger_house.pdf --ai-claude"
    exit 1
end

echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color yellow)"        AI CLEANUP BATCH PROCESSOR (INTERACTIVE)        "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""
echo (set_color green)"Scanning for files to process..."(set_color normal)
echo ""

set -g FILES_TO_PROCESS

# Find all files that need AI cleanup
for chapter_dir in $OUTPUT_ROOT/*/
    set chapter_name (basename $chapter_dir)

    # Skip final directory
    if test "$chapter_name" = "final"
        continue
    end

    # Check if ai_cleaned.md already exists
    if test -f $chapter_dir/ai_cleaned.md
        echo (set_color blue)"  [SKIP]"(set_color normal) " $chapter_name (already processed)"
        continue
    end

    # Find the best source file
    if test -f $chapter_dir/dict_cleaned.md
        set source_file $chapter_dir/dict_cleaned.md
    else if test -f $chapter_dir/cleaned.md
        set source_file $chapter_dir/cleaned.md
    else if test -f $chapter_dir/converted.md
        set source_file $chapter_dir/converted.md
    else
        echo (set_color yellow)"  [WARN]"(set_color normal) " $chapter_name (no source file found)"
        continue
    end

    # Check if file is empty
    set line_count (wc -l < $source_file)
    if test $line_count -eq 0
        echo (set_color yellow)"  [SKIP]"(set_color normal) " $chapter_name (empty file)"
        touch $chapter_dir/ai_cleaned.md
        continue
    end

    echo (set_color green)"  [QUEUE]"(set_color normal) " $chapter_name ($line_count lines)"
    set -a FILES_TO_PROCESS "$source_file|$chapter_dir/ai_cleaned.md|$chapter_name"
end

echo ""
set file_count (count $FILES_TO_PROCESS)

if test $file_count -eq 0
    echo (set_color yellow)"No files need processing!"(set_color normal)
    echo ""
    echo "All chapters have been AI-cleaned already."
    exit 0
end

echo (set_color cyan)"Found $file_count file(s) to process"(set_color normal)
echo ""
echo (set_color yellow)"Ready for Claude Code to process these files interactively."(set_color normal)
echo ""

# Output the list for processing
for file_spec in $FILES_TO_PROCESS
    echo $file_spec
end
