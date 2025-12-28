#!/usr/bin/env fish

# ocr_quality_checker.fish - Detect potential OCR errors and issues
# Usage: ./ocr_quality_checker.fish input.md [output_report.md]

set INPUT $argv[1]
set OUTPUT $argv[2]

if test -z "$OUTPUT"
    set OUTPUT (dirname $INPUT)"/quality_report.md"
end

if not test -f "$INPUT"
    echo (set_color red)"[ERROR]"(set_color normal) " Input file not found: $INPUT"
    exit 1
end

echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color yellow)"            OCR QUALITY CHECKER                           "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""
echo (set_color green)"Analyzing:"(set_color normal) "$INPUT"
echo ""

# Initialize counters
set -g TOTAL_ISSUES 0
set -g ENCODING_ISSUES 0
set -g WORD_ISSUES 0
set -g FORMAT_ISSUES 0
set -g STAT_ISSUES 0
set -g SUSPICIOUS_CHARS 0

# Header for report
echo "# OCR Quality Report" > $OUTPUT
echo "" >> $OUTPUT
echo "**File:** $INPUT" >> $OUTPUT
echo "**Generated:** "(date) >> $OUTPUT
echo "" >> $OUTPUT
echo "---" >> $OUTPUT
echo "" >> $OUTPUT

# ============================================================================
# CHECK 1: Encoding Issues
# ============================================================================

echo (set_color yellow)"[1/6]"(set_color normal) " Checking for encoding issues..."

echo "## Encoding Issues" >> $OUTPUT
echo "" >> $OUTPUT

# Check for common encoding problems
set encoding_patterns \
    "â€™" \
    "â€œ" \
    "â€" \
    "â€"" \
    "â€˜" \
    "Â" \
    "â€¢"

for pattern in $encoding_patterns
    set matches (grep -n "$pattern" $INPUT)
    if test -n "$matches"
        set count (echo "$matches" | wc -l)
        set ENCODING_ISSUES (math $ENCODING_ISSUES + $count)
        echo "- Found $count instances of '$pattern'" >> $OUTPUT
        echo "$matches" | head -5 >> $OUTPUT
        if test $count -gt 5
            set remaining (math $count - 5)
            echo "  _(and $remaining more...)_" >> $OUTPUT
        end
        echo "" >> $OUTPUT
    end
end

if test $ENCODING_ISSUES -eq 0
    echo "✓ No encoding issues found" >> $OUTPUT
    echo "" >> $OUTPUT
else
    echo (set_color red)"  Found $ENCODING_ISSUES encoding issues"(set_color normal)
end

# ============================================================================
# CHECK 2: Suspicious Character Patterns
# ============================================================================

echo (set_color yellow)"[2/6]"(set_color normal) " Checking for suspicious characters..."

echo "## Suspicious Characters" >> $OUTPUT
echo "" >> $OUTPUT

# Characters that shouldn't appear in normal text
set suspicious_chars \
    "¢:cent sign" \
    "®:registered trademark" \
    "™:trademark" \
    "§:section sign" \
    "¶:pilcrow" \
    "†:dagger" \
    "‡:double dagger" \
    "°:degree" \
    "±:plus-minus" \
    "µ:micro" \
    "×:multiplication" \
    "÷:division"

for char_pair in $suspicious_chars
    set parts (string split ":" $char_pair)
    set char $parts[1]
    set desc $parts[2]
    
    set matches (grep -n "[$char]" $INPUT)
    if test -n "$matches"
        set count (echo "$matches" | wc -l)
        set SUSPICIOUS_CHARS (math $SUSPICIOUS_CHARS + $count)
        echo "- Found $count instances of $desc ($char)" >> $OUTPUT
        echo "$matches" | head -3 >> $OUTPUT
        echo "" >> $OUTPUT
    end
end

if test $SUSPICIOUS_CHARS -eq 0
    echo "✓ No suspicious characters found" >> $OUTPUT
    echo "" >> $OUTPUT
else
    echo (set_color red)"  Found $SUSPICIOUS_CHARS suspicious characters"(set_color normal)
end

# ============================================================================
# CHECK 3: Common OCR Word Mistakes
# ============================================================================

echo (set_color yellow)"[3/6]"(set_color normal) " Checking for common OCR mistakes..."

echo "## Common OCR Mistakes" >> $OUTPUT
echo "" >> $OUTPUT

# Common OCR misreadings
set ocr_mistakes \
    "Jrom:from" \
    "Jaction:faction" \
    "eves:eyes" \
    "vou:you" \
    "thar:that" \
    "rhe:the" \
    "wilh:with" \
    "somerhing:something" \
    "anv:any" \
    "mav:may" \
    "savs:says" \
    "Ladv:Lady" \
    "lll:III" \
    "Dav:Day"

for mistake in $ocr_mistakes
    set parts (string split ":" $mistake)
    set wrong $parts[1]
    set correct $parts[2]
    
    set matches (grep -nw "$wrong" $INPUT)
    if test -n "$matches"
        set count (echo "$matches" | wc -l)
        set WORD_ISSUES (math $WORD_ISSUES + $count)
        echo "- **$wrong** should be **$correct** ($count instances)" >> $OUTPUT
        echo '```' >> $OUTPUT
        echo "$matches" | head -3 >> $OUTPUT
        echo '```' >> $OUTPUT
        echo "" >> $OUTPUT
    end
end

if test $WORD_ISSUES -eq 0
    echo "✓ No common OCR mistakes found" >> $OUTPUT
    echo "" >> $OUTPUT
else
    echo (set_color red)"  Found $WORD_ISSUES word mistakes"(set_color normal)
end

# ============================================================================
# CHECK 4: Malformed Headers
# ============================================================================

echo (set_color yellow)"[4/6]"(set_color normal) " Checking for malformed headers..."

echo "## Malformed Headers" >> $OUTPUT
echo "" >> $OUTPUT

# Check for headers with special characters
set bad_headers (grep -n '^[+*®¢]\+[A-Z]' $INPUT)
if test -n "$bad_headers"
    set count (echo "$bad_headers" | wc -l)
    set FORMAT_ISSUES (math $FORMAT_ISSUES + $count)
    echo "Found $count headers with special characters:" >> $OUTPUT
    echo '```' >> $OUTPUT
    echo "$bad_headers" >> $OUTPUT
    echo '```' >> $OUTPUT
    echo "" >> $OUTPUT
    echo (set_color red)"  Found $count malformed headers"(set_color normal)
else
    echo "✓ No malformed headers found" >> $OUTPUT
    echo "" >> $OUTPUT
end

# ============================================================================
# CHECK 5: Stat Block Issues
# ============================================================================

echo (set_color yellow)"[5/6]"(set_color normal) " Checking stat blocks..."

echo "## Stat Block Issues" >> $OUTPUT
echo "" >> $OUTPUT

# Look for stat blocks and check for common issues
set stat_block_lines (grep -n "THAC0\|#AT\|Dmg\|hp\|MV\|XP" $INPUT)

if test -n "$stat_block_lines"
    set block_count (echo "$stat_block_lines" | wc -l)
    echo "Found $block_count potential stat block lines" >> $OUTPUT
    echo "" >> $OUTPUT
    
    # Check for malformed stat blocks
    set malformed (echo "$stat_block_lines" | grep -v ":")
    if test -n "$malformed"
        set count (echo "$malformed" | wc -l)
        set STAT_ISSUES (math $STAT_ISSUES + $count)
        echo "⚠️ Found $count potentially malformed stat entries:" >> $OUTPUT
        echo '```' >> $OUTPUT
        echo "$malformed" | head -5 >> $OUTPUT
        echo '```' >> $OUTPUT
        echo "" >> $OUTPUT
    end
    
    # Check for incomplete stat blocks (missing key stats)
    set incomplete_blocks (grep -B2 -A2 "THAC0" $INPUT | grep -v "hp\|AC\|MV" | head -10)
    if test -n "$incomplete_blocks"
        echo "⚠️ Potentially incomplete stat blocks:" >> $OUTPUT
        echo '```' >> $OUTPUT
        echo "$incomplete_blocks" >> $OUTPUT
        echo '```' >> $OUTPUT
        echo "" >> $OUTPUT
    end
    
    echo (set_color yellow)"  Analyzed $block_count stat block entries"(set_color normal)
else
    echo "ℹ️ No stat blocks found in this file" >> $OUTPUT
    echo "" >> $OUTPUT
end

# ============================================================================
# CHECK 6: Planescape Terminology
# ============================================================================

echo (set_color yellow)"[6/6]"(set_color normal) " Checking Planescape terminology..."

echo "## Planescape Terminology Check" >> $OUTPUT
echo "" >> $OUTPUT

# Common terms that might be misspelled
set planescape_terms \
    "berk:berks:cutter" \
    "basher:bashers:person" \
    "blood:bloods:expert" \
    "barmy:barmies:crazy" \
    "factol:factols:faction leader" \
    "dabus:dabus:Lady's servants" \
    "Sigil:Sigil:City of Doors" \
    "tanar'ri:tanar'ri:demons" \
    "baatezu:baatezu:devils" \
    "yugoloth:yugoloths:neutral evil fiends"

set term_issues 0
for term_info in $planescape_terms
    set parts (string split ":" $term_info)
    set singular $parts[1]
    set plural $parts[2]
    
    # Check if terms appear (case-insensitive for detection)
    # Use default value of 0 if grep returns nothing
    set found_singular (grep -ic "\b$singular\b" $INPUT 2>/dev/null; or echo 0)
    set found_plural (grep -ic "\b$plural\b" $INPUT 2>/dev/null; or echo 0)
    
    # Convert to single number (grep -ic might return empty or multiple lines)
    set found_singular (echo $found_singular | head -1)
    set found_plural (echo $found_plural | head -1)
    
    # Ensure we have valid numbers
    if test -z "$found_singular"
        set found_singular 0
    end
    if test -z "$found_plural"
        set found_plural 0
    end
    
    # Fish uses -o for OR but it needs proper syntax
    if test $found_singular -gt 0; or test $found_plural -gt 0
        # Now check for case issues (should be lowercase unless proper noun)
        set wrong_case (grep -n "\b"(string upper $singular)"\b" $INPUT | grep -v "^[A-Z]")
        if test -n "$wrong_case"
            set count (echo "$wrong_case" | wc -l)
            set term_issues (math $term_issues + $count)
            echo "- **$singular** has $count potential case issues" >> $OUTPUT
        end
    end
end

if test $term_issues -eq 0
    echo "✓ Planescape terminology looks good" >> $OUTPUT
    echo "" >> $OUTPUT
else
    echo "⚠️ Found $term_issues potential terminology issues" >> $OUTPUT
    echo "" >> $OUTPUT
    echo (set_color yellow)"  Found $term_issues terminology issues"(set_color normal)
end

# ============================================================================
# CHECK 7: Line Length Issues
# ============================================================================

echo "## Line Length Analysis" >> $OUTPUT
echo "" >> $OUTPUT

set long_lines (awk 'length > 200 {print NR": "substr($0,1,100)"..."}' $INPUT)
if test -n "$long_lines"
    set count (echo "$long_lines" | wc -l)
    echo "Found $count extremely long lines (>200 chars):" >> $OUTPUT
    echo '```' >> $OUTPUT
    echo "$long_lines" | head -5 >> $OUTPUT
    echo '```' >> $OUTPUT
    echo "" >> $OUTPUT
else
    echo "✓ No extremely long lines found" >> $OUTPUT
    echo "" >> $OUTPUT
end

# ============================================================================
# SUMMARY
# ============================================================================

echo "---" >> $OUTPUT
echo "" >> $OUTPUT
echo "## Summary" >> $OUTPUT
echo "" >> $OUTPUT

set TOTAL_ISSUES (math $ENCODING_ISSUES + $WORD_ISSUES + $FORMAT_ISSUES + $STAT_ISSUES + $SUSPICIOUS_CHARS)

echo "| Category | Issues Found |" >> $OUTPUT
echo "|----------|--------------|" >> $OUTPUT
echo "| Encoding Problems | $ENCODING_ISSUES |" >> $OUTPUT
echo "| Suspicious Characters | $SUSPICIOUS_CHARS |" >> $OUTPUT
echo "| OCR Word Mistakes | $WORD_ISSUES |" >> $OUTPUT
echo "| Malformed Headers | $FORMAT_ISSUES |" >> $OUTPUT
echo "| Stat Block Issues | $STAT_ISSUES |" >> $OUTPUT
echo "| **TOTAL** | **$TOTAL_ISSUES** |" >> $OUTPUT
echo "" >> $OUTPUT

# Severity rating
if test $TOTAL_ISSUES -eq 0
    echo "### Quality: ✅ EXCELLENT" >> $OUTPUT
    echo "" >> $OUTPUT
    echo "No issues detected. This file appears to be clean!" >> $OUTPUT
    set quality_color green
    set quality_text "EXCELLENT"
else if test $TOTAL_ISSUES -lt 10
    echo "### Quality: ✓ GOOD" >> $OUTPUT
    echo "" >> $OUTPUT
    echo "Minor issues detected. Quick cleanup recommended." >> $OUTPUT
    set quality_color yellow
    set quality_text "GOOD"
else if test $TOTAL_ISSUES -lt 50
    echo "### Quality: ⚠️ FAIR" >> $OUTPUT
    echo "" >> $OUTPUT
    echo "Moderate issues detected. Cleanup recommended." >> $OUTPUT
    set quality_color yellow
    set quality_text "FAIR"
else
    echo "### Quality: ❌ NEEDS WORK" >> $OUTPUT
    echo "" >> $OUTPUT
    echo "Significant issues detected. Thorough cleanup required." >> $OUTPUT
    set quality_color red
    set quality_text "NEEDS WORK"
end

echo "" >> $OUTPUT
echo "## Recommendations" >> $OUTPUT
echo "" >> $OUTPUT

if test $ENCODING_ISSUES -gt 0
    echo "1. Run \`./fix_encoding.fish\` to fix encoding issues" >> $OUTPUT
end

if test $WORD_ISSUES -gt 0
    echo "2. Apply dictionary corrections with \`./ocr_cleanup.fish\`" >> $OUTPUT
end

if test $FORMAT_ISSUES -gt 0
    echo "3. Manually review and fix malformed headers" >> $OUTPUT
end

if test $STAT_ISSUES -gt 0
    echo "4. Review stat blocks for accuracy and completeness" >> $OUTPUT
end

echo "" >> $OUTPUT
echo "---" >> $OUTPUT
echo "" >> $OUTPUT
echo "_Report generated by OCR Quality Checker_" >> $OUTPUT

# Console output
echo ""
echo (set_color cyan)"╔════════════════════════════════════════════════════════════╗"(set_color normal)
echo (set_color cyan)"║"(set_color normal)(set_color $quality_color)"              QUALITY: $quality_text                           "(set_color normal)(set_color cyan)"║"(set_color normal)
echo (set_color cyan)"╚════════════════════════════════════════════════════════════╝"(set_color normal)
echo ""
echo (set_color yellow)"📊 Issues Found:"(set_color normal)
echo "   Encoding:    $ENCODING_ISSUES"
echo "   Suspicious:  $SUSPICIOUS_CHARS"
echo "   Words:       $WORD_ISSUES"
echo "   Formatting:  $FORMAT_ISSUES"
echo "   Stat Blocks: $STAT_ISSUES"
echo "   ─────────────────"
echo "   TOTAL:       $TOTAL_ISSUES"
echo ""
echo (set_color green)"📄 Report saved to:"(set_color normal) "$OUTPUT"
echo ""

# Offer to open report
if command -v code &>/dev/null
    echo -n "Open report in VS Code? [y/N] "
    read response
    if test "$response" = "y" -o "$response" = "Y"
        code $OUTPUT
    end
end
