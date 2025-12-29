#!/usr/bin/env python3
"""
generate_corrections.py - Analyze low-confidence OCR words and generate corrections
Parses *-lowconf.txt files across chapters, finds recurring patterns, and outputs
suggested corrections to corrections.json

Usage: python3 generate_corrections.py [converted_dir] [--threshold N] [--output FILE]
"""

import os
import sys
import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from datetime import datetime

# Configuration defaults
DEFAULT_THRESHOLD = 40
DEFAULT_MIN_OCCURRENCES = 2
DEFAULT_OUTPUT = "corrections.json"

# Known corrections for common OCR errors (seed the learning)
KNOWN_CORRECTIONS = {
    "vou": "you",
    "eves": "eyes",
    "Jrom": "from",
    "Jaction": "faction",
    "rhe": "the",
    "wilh": "with",
    "thar": "that",
    "bcrk": "berk",
    "Ladv": "Lady",
    "lll": "III",
    "tev've": "they've",
    "1ere's": "here's",
    "Heen": "been",
    "vue": "you",
    "Facto1": "Factol",
    "St+tAR+": "START",
    "+ee": "the",
    "Leer": "beer",
    "eT": "et",
    "vvho": "who",
    "vvhat": "what",
    "vvith": "with",
    "rnore": "more",
    "sorne": "some",
    "tirne": "time",
    "frorn": "from",
}

# Planescape terms to preserve (don't "correct" these)
PRESERVE_TERMS = {
    "berk", "basher", "cutter", "blood", "barmy", "factol", "dabus", "sigil",
    "tanar'ri", "baatezu", "yugoloth", "thac0", "godsmen", "harmonium",
    "hardheads", "mercykillers", "guvners", "xaositects", "athar", "sod",
    "cage", "multiverse", "planewalker", "prime", "portal", "modron",
    "tiefling", "aasimar", "githzerai", "githyanki"
}

# Garbage patterns - words to delete
# Be conservative - only clear garbage, not real words
GARBAGE_PATTERNS = [
    r'^[¢®©™°±§¶]+$',      # Garbage symbols
    r'^[+*]+[A-Z]+[+*]*$',  # +HE+, *CHAPTER*, etc.
    r'^Pp\.$',              # OCR garbage
    r'^<p$',                # HTML-like garbage
    r'^wv$',                # OCR garbage
    r'^eT$',                # OCR garbage
]


def is_preserved_term(word: str) -> bool:
    """Check if word is a Planescape term that should be preserved"""
    return word.lower() in PRESERVE_TERMS


def is_garbage(word: str) -> bool:
    """Check if word matches garbage patterns"""
    for pattern in GARBAGE_PATTERNS:
        if re.match(pattern, word):
            return True
    return False


def is_pure_punctuation(word: str) -> bool:
    """Check if word is only punctuation"""
    return bool(re.match(r'^[^\w\s]+$', word))


def is_likely_number_or_stat(word: str) -> bool:
    """Check if word looks like a number, stat, or game term that shouldn't be modified"""
    # Numbers or mixed number/letter combos
    if re.match(r'^\d+$', word):  # Pure numbers
        return True
    if re.match(r'^\d+[a-z]+$', word, re.I):  # 1d6, 2nd, etc.
        return True
    if re.match(r'^[a-z]+\d+$', word, re.I):  # F10, AC5, etc.
        return True
    if re.match(r'^page-\d+$', word, re.I):  # Page markers
        return True
    return False


def suggest_correction(word: str) -> str | None:
    """Try to suggest a correction for a word"""
    # Check known corrections first
    if word in KNOWN_CORRECTIONS:
        return KNOWN_CORRECTIONS[word]
    
    # Check for garbage
    if is_garbage(word):
        return ""  # Empty string means delete
    
    # Don't try to "fix" things that look like numbers or game stats
    if is_likely_number_or_stat(word):
        return None
    
    # Don't try to fix single characters (too risky)
    if len(word) <= 2:
        return None
    
    # Pattern-based suggestions - only for specific patterns
    suggestion = word
    
    # Only replace 0/1 in the middle of words (not standalone or at word boundaries)
    # e.g., "0f" -> "of" but not "10" -> "lo"
    if re.match(r'^0[a-z]+$', word, re.I):  # 0f -> of
        suggestion = 'o' + word[1:]
    if re.match(r'^1[a-z]+$', word, re.I) and not word.startswith('1st') and not word.startswith('1d'):
        suggestion = 'l' + word[1:]  # 1ady -> lady but not 1st or 1d6
    
    # Common OCR ligature errors - only when clearly wrong
    suggestion = re.sub(r'rn(?=[aeiouy])', 'm', suggestion)  # rna -> ma, but not rns
    suggestion = re.sub(r'vv', 'w', suggestion)  # vvith -> with
    # Don't do cl -> d, it's too aggressive (would break "clean", "close", etc.)
    
    if suggestion != word:
        return suggestion
    
    return None


def parse_lowconf_file(filepath: Path) -> list[tuple[str, float]]:
    """Parse a lowconf file and return list of (word, confidence) tuples"""
    results = []
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                
                # Parse format: "word (conf: XX.XXX)"
                match = re.match(r'^(.+?) \(conf: ([\d.]+)\)$', line)
                if match:
                    word = match.group(1)
                    conf = float(match.group(2))
                    results.append((word, conf))
    except Exception as e:
        print(f"Warning: Error reading {filepath}: {e}", file=sys.stderr)
    
    return results


def find_lowconf_files(output_root: Path) -> list[Path]:
    """Find all lowconf files in the converted directory"""
    files = []
    for chapter_dir in output_root.iterdir():
        if not chapter_dir.is_dir():
            continue
        if chapter_dir.name in ('final', 'statblocks', 'diagnostics'):
            continue
        
        temp_dir = chapter_dir / '.temp'
        if temp_dir.exists():
            for f in temp_dir.glob('*-lowconf.txt'):
                files.append(f)
    
    return files


def analyze_lowconf_words(output_root: Path, threshold: float) -> dict:
    """Analyze all low-confidence words and return statistics"""
    word_counts = Counter()
    word_confidences = defaultdict(list)
    chapter_stats = defaultdict(int)
    
    lowconf_files = find_lowconf_files(output_root)
    
    for filepath in lowconf_files:
        chapter_name = filepath.parent.parent.name
        entries = parse_lowconf_file(filepath)
        
        for word, conf in entries:
            # Skip if above threshold
            if conf >= threshold:
                continue
            
            # Skip empty or whitespace
            if not word.strip():
                continue
            
            # Skip pure punctuation
            if is_pure_punctuation(word):
                continue
            
            # Skip preserved terms
            if is_preserved_term(word):
                continue
            
            word_counts[word] += 1
            word_confidences[word].append(conf)
            chapter_stats[chapter_name] += 1
    
    return {
        'word_counts': word_counts,
        'word_confidences': word_confidences,
        'chapter_stats': chapter_stats,
        'total_files': len(lowconf_files),
    }


def generate_corrections_json(analysis: dict, min_occurrences: int) -> dict:
    """Generate the corrections.json structure"""
    corrections = {}
    
    for word, count in analysis['word_counts'].most_common():
        if count < min_occurrences:
            continue
        
        suggestion = suggest_correction(word)
        if suggestion is not None:
            corrections[word] = suggestion
    
    return {
        "metadata": {
            "description": "OCR correction patterns learned from low-confidence word analysis",
            "version": "1.0.0",
            "generated": datetime.now().isoformat(),
            "word_count": len(analysis['word_counts']),
            "corrections_count": len(corrections),
        },
        "corrections": corrections,
        "garbage_patterns": GARBAGE_PATTERNS,
        "preserve_terms": list(PRESERVE_TERMS),
    }


def print_report(analysis: dict, threshold: float, min_occurrences: int):
    """Print a human-readable analysis report"""
    print()
    print("╔════════════════════════════════════════════════════════════╗")
    print("║       LOW-CONFIDENCE WORD ANALYSIS REPORT              ║")
    print("╚════════════════════════════════════════════════════════════╝")
    print()
    print(f"Settings:")
    print(f"  Confidence threshold: < {threshold}%")
    print(f"  Minimum occurrences:  {min_occurrences}")
    print()
    print("Per-Chapter Low-Confidence Words:")
    for chapter, count in sorted(analysis['chapter_stats'].items()):
        print(f"  {chapter:40} {count} words")
    print()
    print(f"Total unique words: {len(analysis['word_counts'])}")
    print(f"Total word instances: {sum(analysis['word_counts'].values())}")
    print()
    print("Most Common Low-Confidence Words (top 20):")
    for word, count in analysis['word_counts'].most_common(20):
        suggestion = suggest_correction(word)
        avg_conf = sum(analysis['word_confidences'][word]) / len(analysis['word_confidences'][word])
        if suggestion is not None:
            if suggestion == "":
                print(f"  {count:4} × {word:20} → (delete)")
            else:
                print(f"  {count:4} × {word:20} → {suggestion}")
        else:
            print(f"  {count:4} × {word:20}   (no suggestion)")
    print()


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Analyze OCR low-confidence words and generate corrections')
    parser.add_argument('output_root', nargs='?', default='converted_harbinger_house',
                        help='Path to converted directory')
    parser.add_argument('--threshold', type=float, default=DEFAULT_THRESHOLD,
                        help=f'Confidence threshold (default: {DEFAULT_THRESHOLD})')
    parser.add_argument('--min-occur', type=int, default=DEFAULT_MIN_OCCURRENCES,
                        help=f'Minimum occurrences (default: {DEFAULT_MIN_OCCURRENCES})')
    parser.add_argument('--output', default=DEFAULT_OUTPUT,
                        help=f'Output file (default: {DEFAULT_OUTPUT})')
    parser.add_argument('--quiet', action='store_true',
                        help='Suppress report output')
    
    args = parser.parse_args()
    
    output_root = Path(args.output_root)
    if not output_root.exists():
        print(f"Error: Directory not found: {output_root}", file=sys.stderr)
        sys.exit(1)
    
    # Analyze
    print(f"Analyzing low-confidence words in {output_root}...", file=sys.stderr)
    analysis = analyze_lowconf_words(output_root, args.threshold)
    
    if not args.quiet:
        print_report(analysis, args.threshold, args.min_occur)
    
    # Generate corrections
    corrections_data = generate_corrections_json(analysis, args.min_occur)
    
    # Write output
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(corrections_data, f, indent=2, ensure_ascii=False)
    
    print(f"✨ Corrections saved to {args.output}")
    print(f"   {len(corrections_data['corrections'])} corrections generated")


if __name__ == '__main__':
    main()
