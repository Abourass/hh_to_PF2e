#!/usr/bin/env fish

# reprocess_lowconf_regions.fish - Re-OCR regions with very low confidence
# Uses TSV bounding box data to crop and re-OCR problematic areas
#
# Usage: ./reprocess_lowconf_regions.fish [converted_dir] [options]
#   --threshold N     Re-OCR words below this confidence (default: 20)
#   --dry-run         Show what would be re-processed without doing it
#   --chapter NAME    Process only this chapter

set -g OUTPUT_ROOT "converted_harbinger_house"
set -g CONFIDENCE_THRESHOLD 20
set -g DRY_RUN false
set -g SINGLE_CHAPTER ""

# Detect ImageMagick version
if command -v magick &>/dev/null
    set -g MAGICK_CMD magick
else if command -v convert &>/dev/null
    set -g MAGICK_CMD convert
else
    echo (set_color red)"[ERROR]"(set_color normal) "ImageMagick not found"
    exit 1
end

# ============================================================================
# LOGGING
# ============================================================================

function log_info
    echo (set_color green)"[INFO]"(set_color normal) $argv >&2
end

function log_warn
    echo (set_color yellow)"[WARN]"(set_color normal) $argv >&2
end

function log_error
    echo (set_color red)"[ERROR]"(set_color normal) $argv >&2
end

function log_verbose
    echo (set_color blue)"[VERB]"(set_color normal) $argv >&2
end

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

function parse_args
    set -l i 1
    while test $i -le (count $argv)
        switch $argv[$i]
            case "--threshold"
                set i (math $i + 1)
                set -g CONFIDENCE_THRESHOLD $argv[$i]
            case "--dry-run"
                set -g DRY_RUN true
            case "--chapter"
                set i (math $i + 1)
                set -g SINGLE_CHAPTER $argv[$i]
            case "--help" "-h"
                echo "Usage: ./reprocess_lowconf_regions.fish [converted_dir] [options]"
                echo ""
                echo "Options:"
                echo "  --threshold N     Re-OCR words below this confidence (default: 20)"
                echo "  --dry-run         Show what would be re-processed without doing it"
                echo "  --chapter NAME    Process only this chapter"
                echo ""
                echo "This script uses TSV bounding box data to identify regions"
                echo "with very low OCR confidence, crops those regions from the"
                echo "original page images, and re-runs OCR with different settings."
                echo ""
                exit 0
            case "*"
                if test -d $argv[$i]
                    set -g OUTPUT_ROOT $argv[$i]
                end
        end
        set i (math $i + 1)
    end
end

# ============================================================================
# TSV PARSING FUNCTIONS
# ============================================================================

function extract_lowconf_regions_from_tsv
    # Extract bounding boxes for very low confidence words from TSV
    # Returns: page_file|word|left|top|width|height|confidence
    
    set tsv_file $argv[1]
    set threshold $argv[2]
    
    if not test -f "$tsv_file"
        return 1
    end
    
    # Parse TSV - level 5 = word level
    # Columns: level page_num block_num par_num line_num word_num left top width height conf text
    awk -F'\t' -v thresh="$threshold" '
    NR > 1 && $1 == 5 && $11 >= 0 && $11 < thresh && length($12) > 0 {
        # Skip pure punctuation
        if ($12 ~ /^[[:punct:]]+$/) next
        # Skip single characters (usually garbage)
        if (length($12) <= 1) next
        # Print: word|left|top|width|height|confidence
        printf "%s|%s|%s|%s|%s|%.1f\n", $12, $7, $8, $9, $10, $11
    }' $tsv_file
end

function find_page_image
    # Find the original or processed page image for a given page
    set temp_dir $argv[1]
    set page_num $argv[2]
    
    # Try processed first, then original
    for suffix in processed.png png
        set candidate "$temp_dir/page-$page_num.$suffix"
        if test -f "$candidate"
            echo $candidate
            return 0
        end
        
        # Also try with leading zeros
        set padded (printf "%02d" $page_num)
        set candidate "$temp_dir/page-$padded.$suffix"
        if test -f "$candidate"
            echo $candidate
            return 0
        end
    end
    
    return 1
end

function crop_and_reocr_region
    # Crop a region from an image and re-run OCR
    # Returns: new_text|confidence
    set image_file $argv[1]
    set left $argv[2]
    set top $argv[3]
    set width $argv[4]
    set height $argv[5]
    set output_dir $argv[6]
    set word_id $argv[7]
    
    # Add padding around the region for better context
    set padding 10
    set crop_left (math "$left - $padding")
    if test $crop_left -lt 0
        set crop_left 0
    end
    set crop_top (math "$top - $padding")
    if test $crop_top -lt 0
        set crop_top 0
    end
    set crop_width (math "$width + 2 * $padding")
    set crop_height (math "$height + 2 * $padding")
    
    set crop_file "$output_dir/crop_$word_id.png"
    set text_file "$output_dir/reocr_$word_id.txt"
    set tsv_file "$output_dir/reocr_$word_id.tsv"
    
    if test $DRY_RUN = true
        echo "[DRY-RUN] Would crop region $crop_left,$crop_top "$crop_width"x"$crop_height" from $image_file"
        return 0
    end
    
    # Crop the region
    $MAGICK_CMD $image_file \
        -crop "$crop_width"x"$crop_height"+"$crop_left"+"$crop_top" \
        +repage \
        $crop_file 2>/dev/null
    
    if not test -f "$crop_file"
        return 1
    end
    
    # Preprocess the cropped region more aggressively
    set processed_crop "$output_dir/crop_"$word_id"_processed.png"
    $MAGICK_CMD $crop_file \
        -colorspace Gray \
        -contrast-stretch 10%x10% \
        -level 10%,90%,1.5 \
        -sharpen 0x1 \
        -threshold 50% \
        $processed_crop 2>/dev/null
    
    # Re-OCR with TSV output to get confidence scores
    if test -f "$processed_crop"
        tesseract $processed_crop $output_dir/reocr_$word_id \
            --psm 7 \
            --oem 1 \
            -c tessedit_char_whitelist="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'-" \
            tsv 2>/dev/null
        
        if test -f "$tsv_file"
            # Extract the text and confidence from TSV
            set result (awk -F'\t' 'NR > 1 && $1 == 5 && length($12) > 0 {printf "%s|%.1f\n", $12, $11}' $tsv_file | head -n 1)
            if test -n "$result"
                echo $result
                return 0
            end
        end
    end
    
    return 1
end

function is_valid_word
    # Check if a word looks like a real word (not garbage)
    set word $argv[1]
    
    # Reject empty
    if test -z "$word"
        return 1
    end
    
    # Reject pure punctuation
    if echo $word | grep -q '^[[:punct:][:space:]]*$'
        return 1
    end
    
    # Reject single characters (usually garbage)
    if test (string length $word) -le 1
        return 1
    end
    
    # Reject if contains too many special characters (>30% of length)
    set special_count (echo $word | grep -o '[^[:alnum:] -]' | wc -l)
    set total_len (string length $word)
    set threshold (math "$total_len * 0.3")
    if test $special_count -gt $threshold
        return 1
    end
    
    # Reject if contains obvious OCR garbage patterns
    if echo $word | grep -qE '(oe|ee|ii|aa|oo){3,}|[[:punct:]]{3,}|^[0-9]+$'
        return 1
    end
    
    return 0
end

function is_better_than_original
    # Check if new OCR result is better than original
    set old_word $argv[1]
    set new_word $argv[2]
    set old_conf $argv[3]
    set new_conf $argv[4]
    
    # Must be different
    if test "$old_word" = "$new_word"
        return 1
    end
    
    # New text must pass basic validation
    if not is_valid_word $new_word
        return 1
    end
    
    # New confidence must be significantly better (at least 30% improvement)
    set conf_improvement (math "$new_conf - $old_conf")
    if test $conf_improvement -lt 30
        return 1
    end
    
    # If new confidence is still very low (<25%), be extra cautious
    if test $new_conf -lt 25
        # Only accept if it looks like a common English word pattern
        if not echo $new_word | grep -qiE '^[a-z]+$|^[a-z]+-[a-z]+$|^[a-z]+'\''[a-z]+$'
            return 1
        end
    end
    
    return 0
end

function check_spelling
    # Basic spell check using aspell if available
    set word $argv[1]
    
    if not command -v aspell &>/dev/null
        # No spell checker - accept the word
        return 0
    end
    
    # Check if it's a valid English word
    set result (echo $word | aspell -a | tail -n 1)
    if echo $result | grep -q '^[*+]'
        # Word is correct or in dictionary
        return 0
    end
    
    # Check for common D&D/Planescape terms that might not be in dictionary
    if echo $word | grep -qiE '^(sigil|githyanki|githzerai|modron|baatezu|tanarri|tiefling|bariaur|dabus)'
        return 0
    end
    
    return 1
end

# ============================================================================
# MAIN PROCESSING
# ============================================================================

function process_chapter
    set chapter_dir $argv[1]
    set chapter_name (basename $chapter_dir)
    
    set temp_dir "$chapter_dir/.temp"
    
    if not test -d "$temp_dir"
        log_warn "No .temp directory for $chapter_name"
        return 1
    end
    
    log_info "Processing $chapter_name..."
    
    set -l total_regions 0
    set -l reprocessed 0
    set -l improved 0
    
    # Create reocr output directory
    set reocr_dir "$temp_dir/reocr"
    if test $DRY_RUN = false
        mkdir -p $reocr_dir
    end
    
    # Clear previous corrections files
    if test $DRY_RUN = false
        rm -f "$reocr_dir/corrections_auto.txt"
        rm -f "$reocr_dir/corrections_manual.txt"
        rm -f "$reocr_dir/rejected.txt"
    end
    
    # Process each TSV file
    for tsv_file in $temp_dir/*.tsv
        if not test -f "$tsv_file"
            continue
        end
        
        set page_name (basename $tsv_file .tsv)
        # Extract page number, stripping 'page-' prefix and any suffix (e.g., '-col1', '-processed')
        set page_num (string replace -r 'page-0*' '' $page_name | string replace -r -- '-col\d+$|-processed$' '')
        
        # Find the corresponding image
        set page_image (find_page_image $temp_dir $page_num)
        if test -z "$page_image"
            continue
        end
        
        # Extract low-confidence regions
        set regions (extract_lowconf_regions_from_tsv $tsv_file $CONFIDENCE_THRESHOLD)
        
        if test (count $regions) -eq 0
            continue
        end
        
        log_verbose "  $page_name: "(count $regions)" low-conf regions"
        
        set word_idx 0
        for region in $regions
            set parts (string split -- "|" $region)
            set word $parts[1]
            set left $parts[2]
            set top $parts[3]
            set width $parts[4]
            set height $parts[5]
            set conf $parts[6]
            
            set word_id "$page_name"_w"$word_idx"
            
            set total_regions (math $total_regions + 1)
            
            if test $DRY_RUN = true
                echo "  Would re-OCR: \"$word\" (conf: $conf%) at $left,$top"
            else
                set result (crop_and_reocr_region $page_image $left $top $width $height $reocr_dir $word_id)
                
                if test -n "$result"
                    set result_parts (string split -- "|" $result)
                    set new_text $result_parts[1]
                    set new_conf $result_parts[2]
                    
                    if test "$new_text" != "$word"
                        # Check if the new result is actually better
                        if is_better_than_original $word $new_text $conf $new_conf
                            # Further validate with spell checking
                            if check_spelling $new_text
                                echo (set_color green)"  ✓ $word → $new_text"(set_color normal)" (was: $conf%, now: $new_conf%)"
                                set improved (math $improved + 1)
                                echo "$word:$new_text" >> "$reocr_dir/corrections_auto.txt"
                            else
                                echo (set_color yellow)"  ? $word → $new_text"(set_color normal)" (was: $conf%, now: $new_conf%) [spelling]"
                                echo "$word:$new_text|old_conf=$conf|new_conf=$new_conf|reason=spelling" >> "$reocr_dir/corrections_manual.txt"
                            end
                        else
                            echo (set_color red)"  ✗ $word → $new_text"(set_color normal)" (was: $conf%, now: $new_conf%) [not better]"
                            echo "$word:$new_text|old_conf=$conf|new_conf=$new_conf|reason=quality" >> "$reocr_dir/rejected.txt"
                        end
                    end
                end
                
                set reprocessed (math $reprocessed + 1)
            end
            
            set word_idx (math $word_idx + 1)
        end
    end
    
    if test $DRY_RUN = true
        log_info "  Would process $total_regions regions"
    else
        log_info "  Processed $reprocessed regions, $improved auto-approved"
        
        # Count corrections in each category
        set auto_count 0
        set manual_count 0
        set rejected_count 0
        
        if test -f "$reocr_dir/corrections_auto.txt"
            set auto_count (wc -l < "$reocr_dir/corrections_auto.txt")
        end
        if test -f "$reocr_dir/corrections_manual.txt"
            set manual_count (wc -l < "$reocr_dir/corrections_manual.txt")
        end
        if test -f "$reocr_dir/rejected.txt"
            set rejected_count (wc -l < "$reocr_dir/rejected.txt")
        end
        
        if test $auto_count -gt 0
            log_info "  → $auto_count auto-approved: $reocr_dir/corrections_auto.txt"
        end
        if test $manual_count -gt 0
            log_warn "  → $manual_count need review: $reocr_dir/corrections_manual.txt"
        end
        if test $rejected_count -gt 0
            log_verbose "  → $rejected_count rejected: $reocr_dir/rejected.txt"
        end
    end
end

# ============================================================================
# MAIN
# ============================================================================

parse_args $argv

echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color yellow)"       RE-OCR LOW-CONFIDENCE REGIONS                    "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""

echo (set_color green)"Settings:"(set_color normal)
echo "  Output root:     $OUTPUT_ROOT"
echo "  Threshold:       < $CONFIDENCE_THRESHOLD%"
echo "  Dry run:         $DRY_RUN"
if test -n "$SINGLE_CHAPTER"
    echo "  Single chapter:  $SINGLE_CHAPTER"
end
echo ""

# Validate
if not test -d "$OUTPUT_ROOT"
    log_error "Directory not found: $OUTPUT_ROOT"
    exit 1
end

# Process chapters
if test -n "$SINGLE_CHAPTER"
    if test -d "$OUTPUT_ROOT/$SINGLE_CHAPTER"
        process_chapter "$OUTPUT_ROOT/$SINGLE_CHAPTER"
    else
        log_error "Chapter not found: $SINGLE_CHAPTER"
        exit 1
    end
else
    for chapter_dir in $OUTPUT_ROOT/*/
        set chapter_name (basename $chapter_dir)
        
        # Skip non-chapter directories
        if test "$chapter_name" = "final"; or test "$chapter_name" = "statblocks"; or test "$chapter_name" = "diagnostics"
            continue
        end
        
        process_chapter $chapter_dir
    end
end

echo ""
if test $DRY_RUN = true
    echo (set_color yellow)"✨ Dry run complete - no changes made"(set_color normal)
else
    echo (set_color green)"✨ Re-OCR complete!"(set_color normal)
    echo ""
    echo (set_color cyan)"Next steps:"(set_color normal)
    echo "  1. Review corrections_auto.txt files - these passed all validation"
    echo "  2. Review corrections_manual.txt files - these need human review"
    echo "  3. Add approved corrections to corrections.json"
    echo "  4. Re-run apply_corrections.fish to apply them"
    echo ""
    echo (set_color yellow)"Note:"(set_color normal)" Auto-approved corrections had:"
    echo "  • Confidence improvement >30%"
    echo "  • Passed spell-checking (or common D&D terms)"
    echo "  • No obvious OCR garbage patterns"
end
echo ""
