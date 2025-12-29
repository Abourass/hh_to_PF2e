#!/usr/bin/env python3
"""
AD&D 2e Stat Block Extractor
Parses OCR'd text and extracts stat blocks into formatted markdown

Usage: python3 extract_statblocks.py input.md [output_dir]
"""

import re
import sys
import os
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional, List, Dict

# Try to import tqdm for progress bars, fall back gracefully
try:
    from tqdm import tqdm
    HAS_TQDM = True
except ImportError:
    HAS_TQDM = False
    def tqdm(iterable, **kwargs):
        """Fallback tqdm that just returns the iterable with occasional progress prints"""
        total = kwargs.get('total', None)
        desc = kwargs.get('desc', 'Processing')
        items = list(iterable)
        if total is None:
            total = len(items)
        for i, item in enumerate(items):
            if i == 0 or (i + 1) % max(1, total // 10) == 0 or i == total - 1:
                print(f"\r{desc}: {i + 1}/{total}", end='', file=sys.stderr, flush=True)
            yield item
        print(file=sys.stderr)  # New line after completion


@dataclass
class StatBlock:
    """Represents an AD&D 2e stat block"""
    name: str = ""
    race_class: str = ""
    alignment: str = ""
    
    # Combat stats
    ac: str = ""
    thac0: str = ""
    hp: str = ""
    mv: str = ""
    attacks: str = ""
    damage: str = ""
    
    # Special abilities
    special_attacks: str = ""
    special_defenses: str = ""
    magic_resistance: str = ""
    
    # Other stats
    size: str = ""
    morale: str = ""
    xp: str = ""
    
    # Ability scores
    strength: str = ""
    dexterity: str = ""
    constitution: str = ""
    intelligence: str = ""
    wisdom: str = ""
    charisma: str = ""
    
    # Equipment and spells
    equipment: List[str] = field(default_factory=list)
    spells: List[str] = field(default_factory=list)
    
    # Raw text for reference
    raw_text: str = ""
    source_location: str = ""

    def to_markdown(self) -> str:
        """Convert to nicely formatted markdown"""
        lines = []
        
        # Header
        lines.append(f"## {self.name}")
        lines.append("")
        
        if self.race_class:
            lines.append(f"*{self.race_class}*")
            lines.append("")
        
        # Core stats table
        lines.append("### Combat Statistics")
        lines.append("")
        lines.append("| Stat | Value |")
        lines.append("|------|-------|")
        
        if self.ac:
            lines.append(f"| **AC** | {self.ac} |")
        if self.thac0:
            lines.append(f"| **THAC0** | {self.thac0} |")
        if self.hp:
            lines.append(f"| **hp** | {self.hp} |")
        if self.mv:
            lines.append(f"| **MV** | {self.mv} |")
        if self.attacks:
            lines.append(f"| **#AT** | {self.attacks} |")
        if self.damage:
            lines.append(f"| **Dmg** | {self.damage} |")
        
        lines.append("")
        
        # Special abilities
        if self.special_attacks or self.special_defenses or self.magic_resistance:
            lines.append("### Special Abilities")
            lines.append("")
            if self.special_attacks:
                lines.append(f"- **Special Attacks:** {self.special_attacks}")
            if self.special_defenses:
                lines.append(f"- **Special Defenses:** {self.special_defenses}")
            if self.magic_resistance:
                lines.append(f"- **Magic Resistance:** {self.magic_resistance}")
            lines.append("")
        
        # Ability scores (if present)
        abilities = []
        if self.strength:
            abilities.append(f"Str {self.strength}")
        if self.dexterity:
            abilities.append(f"Dex {self.dexterity}")
        if self.constitution:
            abilities.append(f"Con {self.constitution}")
        if self.intelligence:
            abilities.append(f"Int {self.intelligence}")
        if self.wisdom:
            abilities.append(f"Wis {self.wisdom}")
        if self.charisma:
            abilities.append(f"Cha {self.charisma}")
        
        if abilities:
            lines.append("### Ability Scores")
            lines.append("")
            lines.append(" | ".join(abilities))
            lines.append("")
        
        # Other info
        other = []
        if self.size:
            other.append(f"**Size:** {self.size}")
        if self.morale:
            other.append(f"**Morale:** {self.morale}")
        if self.alignment:
            other.append(f"**Alignment:** {self.alignment}")
        if self.xp:
            other.append(f"**XP:** {self.xp}")
        
        if other:
            lines.append("### Additional Info")
            lines.append("")
            lines.append(" | ".join(other))
            lines.append("")
        
        # Equipment
        if self.equipment:
            lines.append("### Equipment")
            lines.append("")
            for item in self.equipment:
                lines.append(f"- {item}")
            lines.append("")
        
        # Spells
        if self.spells:
            lines.append("### Spells")
            lines.append("")
            for spell in self.spells:
                lines.append(f"- {spell}")
            lines.append("")
        
        lines.append("---")
        lines.append("")
        
        return "\n".join(lines)


def parse_stat_value(text: str, patterns: List[str]) -> str:
    """Extract a stat value using multiple possible patterns"""
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            return match.group(1).strip()
    return ""


def extract_stat_block(text: str, start_pos: int = 0) -> Optional[StatBlock]:
    """Extract a single stat block from text"""
    
    # Common patterns for AD&D 2e stats
    patterns = {
        'ac': [
            r'AC[:\s]+(-?\d+(?:/[-\d]+)?)',
            r'Armor Class[:\s]+(-?\d+)',
        ],
        'thac0': [
            r'THAC0[:\s]+(\d+)',
            r'THACO[:\s]+(\d+)',
            r'To Hit[:\s]+(\d+)',
        ],
        'hp': [
            r'hp[:\s]+(\d+(?:\s*\([^)]+\))?)',
            r'Hit Points?[:\s]+(\d+)',
            r'HP[:\s]+(\d+)',
        ],
        'mv': [
            r'MV[:\s]+([\d,\s\w()]+?)(?:\s*[;#]|\s*$)',
            r'Movement[:\s]+([\d\'"]+)',
        ],
        'attacks': [
            r'#AT[:\s]+([\d/]+)',
            r'Attacks?[:\s]+([\d/]+)',
        ],
        'damage': [
            r'Dmg[:\s]+([^;]+?)(?:;|\s*SA|\s*SD|\s*MR|\s*$)',
            r'Damage[:\s]+([^;]+)',
        ],
        'special_attacks': [
            r'SA[:\s]+([^;]+?)(?:;|\s*SD|\s*MR|\s*$)',
            r'Special Attacks?[:\s]+([^;]+)',
        ],
        'special_defenses': [
            r'SD[:\s]+([^;]+?)(?:;|\s*MR|\s*$)',
            r'Special Defenses?[:\s]+([^;]+)',
        ],
        'magic_resistance': [
            r'MR[:\s]+(\d+%?)',
            r'Magic Resistance[:\s]+(\d+%?)',
        ],
        'size': [
            r'SZ[:\s]+([TFSMHLG](?:\s*\([^)]+\))?)',
            r'Size[:\s]+(\w+)',
        ],
        'morale': [
            r'ML[:\s]+(\d+(?:-\d+)?(?:\s*\([^)]+\))?)',
            r'Morale[:\s]+(\d+)',
        ],
        'xp': [
            r'XP[:\s]+([\d,]+)',
            r'Experience[:\s]+([\d,]+)',
        ],
        'alignment': [
            r'\b(LG|NG|CG|LN|N|CN|LE|NE|CE)\b',
            r'AL[:\s]+(\w+)',
        ],
    }
    
    # Ability score patterns
    ability_patterns = {
        'strength': [r'\bStr\s+(\d+(?:/\d+)?)', r'Strength[:\s]+(\d+)'],
        'dexterity': [r'\bDex\s+(\d+)', r'Dexterity[:\s]+(\d+)'],
        'constitution': [r'\bCon\s+(\d+)', r'Constitution[:\s]+(\d+)'],
        'intelligence': [r'\bInt\s+(\d+)', r'Intelligence[:\s]+(\d+)'],
        'wisdom': [r'\bWis\s+(\d+)', r'Wisdom[:\s]+(\d+)'],
        'charisma': [r'\bCha\s+(\d+)', r'Charisma[:\s]+(\d+)'],
    }
    
    block = StatBlock()
    block.raw_text = text
    
    # Extract each stat
    for stat_name, stat_patterns in patterns.items():
        value = parse_stat_value(text, stat_patterns)
        setattr(block, stat_name, value)
    
    for stat_name, stat_patterns in ability_patterns.items():
        value = parse_stat_value(text, stat_patterns)
        setattr(block, stat_name, value)
    
    # A valid stat block should have at least THAC0 or AC or HP
    if not (block.thac0 or block.ac or block.hp):
        return None
    
    return block


def find_stat_blocks(text: str) -> List[tuple]:
    """Find all potential stat block regions in text"""
    
    # Look for regions that contain stat block indicators
    # THAC0 is the most reliable indicator for AD&D 2e
    
    stat_regions = []
    
    # Pattern to find stat block starts (name followed by stats)
    # Common patterns:
    # 1. Name in bold/caps followed by stats
    # 2. "Pl/♂ human" type race/class indicators
    # 3. Direct stat listings
    
    # Split by common delimiters
    # Look for THAC0 as anchor point
    thac0_matches = list(re.finditer(r'THAC0', text, re.IGNORECASE))
    
    for match in thac0_matches:
        # Find the start of this stat block (look backwards for name)
        start = match.start()
        
        # Look back up to 500 chars for a name (usually bold or caps)
        lookback_start = max(0, start - 500)
        lookback_text = text[lookback_start:start]
        
        # Try to find a name - often in bold (**name**) or all caps
        name_match = None
        
        # Check for bold markdown name
        bold_match = re.search(r'\*\*([^*]+)\*\*', lookback_text)
        if bold_match:
            name_match = bold_match
            start = lookback_start + bold_match.start()
        else:
            # Check for caps name (at least 3 chars, possibly with spaces)
            caps_match = re.search(r'\b([A-Z][A-Z\s]{2,}[A-Z])\b', lookback_text)
            if caps_match:
                name_match = caps_match
                start = lookback_start + caps_match.start()
        
        # Find the end of this stat block (look for XP value or next stat block)
        end = match.end()
        lookahead_text = text[end:end + 1000]
        
        # XP typically ends a stat block
        xp_match = re.search(r'XP\s+[\d,]+\.?', lookahead_text)
        if xp_match:
            end = match.end() + xp_match.end()
        else:
            # Look for double newline or next stat block
            break_match = re.search(r'\n\n', lookahead_text)
            if break_match:
                end = match.end() + break_match.start()
            else:
                end = match.end() + len(lookahead_text)
        
        block_text = text[start:end]
        
        # Extract name if found
        name = ""
        if name_match:
            name = name_match.group(1).strip('* ')
        
        stat_regions.append((start, end, name, block_text))
    
    return stat_regions


def process_file(input_path: str, output_dir: str) -> List[StatBlock]:
    """Process a markdown file and extract all stat blocks"""
    
    with open(input_path, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    
    os.makedirs(output_dir, exist_ok=True)
    
    stat_blocks = []
    regions = find_stat_blocks(content)
    
    print(f"Found {len(regions)} potential stat block regions")
    
    for i, (start, end, name, block_text) in enumerate(tqdm(regions, desc="Extracting stat blocks", unit="block")):
        block = extract_stat_block(block_text)
        
        if block:
            block.name = name if name else f"Unknown NPC {i+1}"
            block.source_location = f"chars {start}-{end}"
            stat_blocks.append(block)
            
            # Save individual stat block
            safe_name = re.sub(r'[^\w\s-]', '', block.name).strip().replace(' ', '_')
            if not safe_name:
                safe_name = f"statblock_{i+1}"
            
            output_file = os.path.join(output_dir, f"{safe_name}.md")
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(block.to_markdown())
            
            print(f"  Extracted: {block.name}")
    
    # Also create combined file
    if stat_blocks:
        combined_file = os.path.join(output_dir, "_all_statblocks.md")
        with open(combined_file, 'w', encoding='utf-8') as f:
            f.write("# Extracted Stat Blocks\n\n")
            f.write(f"*Extracted from: {input_path}*\n\n")
            f.write(f"*Total NPCs: {len(stat_blocks)}*\n\n")
            f.write("---\n\n")
            
            for block in stat_blocks:
                f.write(block.to_markdown())
                f.write("\n")
        
        print(f"\nCombined output: {combined_file}")
    
    return stat_blocks


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 extract_statblocks.py input.md [output_dir]")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else "extracted_statblocks"
    
    if not os.path.exists(input_file):
        print(f"Error: Input file not found: {input_file}")
        sys.exit(1)
    
    blocks = process_file(input_file, output_dir)
    
    print(f"\nExtracted {len(blocks)} stat blocks")
