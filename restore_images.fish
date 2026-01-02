#!/usr/bin/env fish

# restore_images.fish - Restore PNG files from trash back to working directory

set TRASH_DIR "/home/navi/.local/share/Trash/files/converted_harbinger_house (Copy)"
set TARGET_DIR "/home/navi/Code/HarbingerHouse/converted_harbinger_house"

echo "Restoring PNG files from trash..."
echo "Source: $TRASH_DIR"
echo "Target: $TARGET_DIR"
echo ""

# Get list of chapter directories
for chapter_dir in "$TRASH_DIR"/*/
    set chapter_name (basename "$chapter_dir")
    
    # Skip if .temp doesn't exist
    if not test -d "$chapter_dir/.temp"
        echo "Skipping $chapter_name (no .temp directory)"
        continue
    end
    
    echo "Processing $chapter_name..."
    
    # Create target .temp if it doesn't exist
    mkdir -p "$TARGET_DIR/$chapter_name/.temp"
    
    # Count PNG files
    set png_files (find "$chapter_dir/.temp" -name "*.png" 2>/dev/null)
    set png_count (count $png_files)
    
    if test $png_count -eq 0
        echo "  No PNG files found"
        continue
    end
    
    echo "  Found $png_count PNG files"
    
    # Copy (not move) PNG files to preserve originals
    cp -v "$chapter_dir/.temp/"*.png "$TARGET_DIR/$chapter_name/.temp/" 2>/dev/null
    
    if test $status -eq 0
        echo "  ✓ Restored $png_count files"
    else
        echo "  ✗ Error restoring files"
    end
    
    echo ""
end

echo "Restoration complete!"
echo ""
echo "To verify, run: find $TARGET_DIR -name '*.png' | wc -l"
