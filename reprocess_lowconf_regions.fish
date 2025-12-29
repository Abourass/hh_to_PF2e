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
    set image_file $argv[1]
    set left $argv[2]
    set top $argv[3]
    set width $argv[4]
    set height $argv[5]
    set output_dir $argv[6]
    set word_id $argv[7]
    
    # Add padding around the region for better context
    set padding 10
    set crop_left (math "max(0, $left - $padding)")
    set crop_top (math "max(0, $top - $padding)")
    set crop_width (math "$width + 2 * $padding")
    set crop_height (math "$height + 2 * $padding")
    
    set crop_file "$output_dir/crop_$word_id.png"
    set text_file "$output_dir/reocr_$word_id.txt"
    
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
    
    # Re-OCR with different settings
    if test -f "$processed_crop"
        tesseract $processed_crop $output_dir/reocr_$word_id \
            --psm 7 \
            -c tessedit_char_whitelist="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'-" \
            2>/dev/null
        
        if test -f "$text_file"
            set new_text (cat $text_file | string trim)
            echo $new_text
            return 0
        end
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
    
    # Process each TSV file
    for tsv_file in $temp_dir/*.tsv
        if not test -f "$tsv_file"
            continue
        end
        
        set page_name (basename $tsv_file .tsv)
        set page_num (string replace -r 'page-0*' '' $page_name)
        
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
            set parts (string split "|" $region)
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
                set new_text (crop_and_reocr_region $page_image $left $top $width $height $reocr_dir $word_id)
                
                if test -n "$new_text"; and test "$new_text" != "$word"
                    echo "  $word → $new_text (conf: $conf%)"
                    set improved (math $improved + 1)
                    
                    # Save the correction
                    echo "$word:$new_text" >> "$reocr_dir/corrections.txt"
                end
                
                set reprocessed (math $reprocessed + 1)
            end
            
            set word_idx (math $word_idx + 1)
        end
    end
    
    if test $DRY_RUN = true
        log_info "  Would process $total_regions regions"
    else
        log_info "  Processed $reprocessed regions, $improved improved"
        
        # Output corrections file path if we found improvements
        if test $improved -gt 0
            log_info "  Corrections saved to: $reocr_dir/corrections.txt"
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
    echo "   Check .temp/reocr/ directories for corrections"
    echo "   Add corrections to corrections.json and re-run apply_corrections.fish"
end
echo ""
