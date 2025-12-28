#!/usr/bin/env fish

# extract_statblocks.fish - Extract NPC stat blocks from markdown
# Usage: ./extract_statblocks.fish input.md output_dir

set INPUT_MD $argv[1]
set OUTPUT_DIR $argv[2]

mkdir -p $OUTPUT_DIR

# Extract stat blocks using pattern matching
grep -Pzo '(?s)\*\*[^*]+\*\*.*?THAC0.*?XP \d+\.' $INPUT_MD | \
    awk 'BEGIN{RS=""; ORS="\n\n"} {print > "'$OUTPUT_DIR'/statblock_"NR".txt"}'

echo "Extracted stat blocks to $OUTPUT_DIR"
