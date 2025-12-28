#!/usr/bin/env fish

# ============================================================================
# STEP 2: OCR CLEANUP
# ============================================================================

if test $DO_CLEANUP = true
    log_step "STEP 2: OCR Cleanup"
    
    for chapter_dir in $OUTPUT_ROOT/*/
        set chapter_name (basename $chapter_dir)
        
        # Skip 'final' directory
        if test "$chapter_name" = "final"
            continue
        end
        
        set input_file $chapter_dir/converted.md
        set cleaned_file $chapter_dir/cleaned.md
        
        if not test -f $input_file
            log_substep (set_color yellow)"Skipping $chapter_name (no converted.md found)"(set_color normal)
            continue
        end
        
        # Check if input file is empty
        if test (wc -l < $input_file) -eq 0
            log_substep (set_color yellow)"Warning: $chapter_name/converted.md is empty, skipping cleanup"(set_color normal)
            cp $input_file $cleaned_file
            continue
        end
        
        log_substep "Cleaning $chapter_name..."
        
        # Do all cleanup in one pipeline instead of temp files
        cat $input_file | \
        # Fix encoding
        sed -e 's/â€™/'\''/g' \
            -e 's/â€œ/"/g' \
            -e 's/â€/"/g' \
            -e 's/â€"/—/g' \
            -e 's/â€˜/'\''/g' \
            -e 's/â€"/–/g' \
            -e 's/Â//g' \
            -e 's/â€¢/•/g' \
            -e 's/Facto1/Factol/g' \
            -e 's/Pl\/â™‚/Pl\/♂/g' \
            -e 's/Pl\/â™€/Pl\/♀/g' \
            -e 's/\+HARBINGER\*\+/# HARBINGER/g' \
            -e 's/+HOUSE +'\'''/HOUSE/g' \
            -e 's/CREDI\+S/CREDITS/g' \
            -e 's/BACKGR®UND/BACKGROUND/g' \
            -e 's/WHA\+ HAS GONE BEFORE/WHAT HAS GONE BEFORE/g' \
            -e 's/¢//g' \
            -e 's/\+THE HOUSE/THE HOUSE/g' | \
        # Fix common OCR word mistakes
        sed -e 's/\bJrom\b/from/g' \
            -e 's/\bJaction\b/faction/g' \
            -e 's/\beves\b/eyes/g' \
            -e 's/\bvou\b/you/g' \
            -e 's/\bbcrk\b/berk/g' \
            -e 's/\bLadv\b/Lady/g' \
            -e 's/\blll\b/III/g' | \
        # Clean up headers
        sed -e 's/^[+*]\+\([A-Z][A-Z ]\+\)[+*]\+$/## \1/g' \
            -e 's/^[+*]\([A-Z][a-z][A-Za-z ]\+\)[+*]$/### \1/g' | \
        # Fix spacing
        sed -e 's/  \+/ /g' \
            -e 's/^ \+//g' \
            -e '/^$/N;/^\n$/d' \
        > $cleaned_file
    end
    
    log_complete
end
