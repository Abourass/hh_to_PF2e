# hh_to_PF2e
# Harbinger House PDF Conversion Pipeline v2

A comprehensive PDF-to-Markdown conversion pipeline optimized for tabletop RPG books, particularly AD&D 2nd Edition modules like Planescape's "Harbinger House".

## What's New in v2

### 1. **Advanced Image Preprocessing**
The pipeline now uses sophisticated image preprocessing before OCR:
- **Deskewing** - Automatically straightens rotated scans (configurable threshold)
- **Despeckle** - Removes noise from aged paper/poor scans
- **Contrast stretching** - Improves text/background separation
- **Morphology operations** - Repairs broken characters common in fantasy fonts

### 2. **Parallel Processing**
Pages are now processed in parallel with configurable job count:
```fish
./harbinger_convert.fish book.pdf output/ --jobs 8
```
Typical speedup: 3-4x on multi-core machines.

### 3. **Config-Driven Chapter Ranges**
No more hardcoded chapter definitions! Use a JSON config file:
```json
{
  "chapters": [
    {"name": "intro", "pages": "1-5", "description": "Introduction"},
    {"name": "chapter1", "pages": "6-31", "description": "The House"}
  ]
}
```

Or auto-detect from PDF bookmarks:
```fish
./batch_convert.fish book.pdf --auto
```

### 4. **Resume/Checkpoint Capability**
The pipeline now saves checkpoints at each major step. If something fails, resume where you left off:
```fish
# Check current status
./harbinger_master.fish book.pdf --status

# Resume from last checkpoint
./harbinger_master.fish book.pdf --resume

# Start fresh
./harbinger_master.fish book.pdf --clean
```

### 5. **OCR Confidence Scoring**
Low-confidence OCR words are now flagged for manual review:
```
output/ocr_confidence_report.txt
```
This helps you quickly find and fix the most problematic areas.

### 6. **Interactive Preprocessing** (NEW!)
Manual column selection and image cleanup for dramatically improved OCR accuracy:
- **Column Detection** - Draw rectangles around text columns (processes each separately)
- **Image Cleanup** - Brush tool to remove decorative elements, page numbers, illustrations
- **Auto-detect Page Color** - Automatically finds background color for cleanup
- **Improves OCR confidence from ~38% to 70%+** on multi-column pages

Built with **pnpm workspaces** monorepo:
```bash
pnpm install          # Install all dependencies
pnpm dev              # Run both frontend and backend
pnpm interactive      # Launch interactive mode
```

See [INTERACTIVE_PREPROCESSING_README.md](./INTERACTIVE_PREPROCESSING_README.md) for full details.

### 7. **Smart Stat Block Extraction**
The `extract_statblocks.fish` intelligently detects AD&D 2e stat blocks and outputs them as formatted markdown:

**Before (OCR mess):**
```
TROLAN Pl/♂ human P10/Athar AC 2 MV 12 hp 58 THAC0 14 #AT 1 Dmg by
weapon SA spells SD spells SZ M ML 15 Int 16 XP 4,000.
```

**After (clean markdown):**
```markdown
## TROLAN
*Pl/♂ human P10/Athar*

### Combat Statistics
| Stat | Value |
|------|-------|
| **AC** | 2 |
| **THAC0** | 14 |
| **hp** | 58 |
| **MV** | 12 |
| **#AT** | 1 |
| **Dmg** | by weapon |

### Special Abilities
- **Special Attacks:** spells
- **Special Defenses:** spells
```

## Quick Start

### Basic Usage
```fish
# Simple conversion with defaults
./harbinger_master.fish harbinger_house.pdf

# Using config file (PDF specified in config)
./harbinger_master.fish --config pipeline_config.json

# Override config PDF
./harbinger_master.fish harbinger_house.pdf --config pipeline_config.json

# Demo mode - quickly test settings on first chapter only
./harbinger_master.fish --config pipeline_config.json --demo --dpi 600

# Full options
./harbinger_master.fish --config pipeline_config.json \
    --dpi 400 \
    --jobs 8 \
    --ai-claude \
    --open
```

### Using npm Scripts (Convenience)
```bash
# If you prefer npm-style commands:
npm run convert              # Run with config file
npm run convert:clean        # Clean and convert
npm run convert:resume       # Resume from checkpoint
npm run status               # Check pipeline status
```

### Advanced: Staged Execution

The pipeline now supports running specific stages independently. This is useful for:
- Running interactive preprocessing between auto-preprocessing and OCR
- Re-running only OCR after manual image cleanup
- Testing different preprocessing settings

```fish
# Stage 1: Extract and auto-preprocess only
./harbinger_master.fish --config pipeline_config.json --stage extract

# Stage 2: Interactive preprocessing (optional)
# Launch the browser UI to manually clean images and draw columns
./interactive_preprocessing_server.fish converted_harbinger_house pipeline_config.json

# Stage 3: OCR on cleaned images
./harbinger_master.fish --config pipeline_config.json --resume --stage ocr

# Or run all stages together (default)
./harbinger_master.fish --config pipeline_config.json
```

**Available stages:**
- `extract` - Extract PDF pages to images only
- `preprocess` - Extract + auto-preprocessing (deskew, despeckle, etc.)
- `ocr` - Run OCR on preprocessed images
- `combine` - Combine OCR results into markdown
- `all` (default) - Run complete pipeline

### Pipeline Steps

**The pipeline runs in a carefully ordered sequence for optimal OCR accuracy:**

1. **PDF Extraction & Auto-Preprocessing** - Extract pages as images at specified DPI, then apply automatic preprocessing (deskew, despeckle, contrast enhancement)
2. **Interactive Preprocessing** (optional) - Manual column selection and image cleanup using browser-based UI - **runs BEFORE OCR for maximum effectiveness!**
3. **OCR** - Tesseract with confidence scoring (uses cleaned/column-separated images from step 2)
4. **Reprocess Low-Confidence** (optional) - Re-OCR regions below confidence threshold
5. **Encoding Cleanup** - Fix UTF-8 encoding issues
6. **Dictionary Corrections** - Planescape terminology
7. **Learned Corrections** - Apply patterns from confidence analysis
8. **AI Cleanup** (optional) - Claude-powered error correction
9. **Stat Block Extraction** - Extract NPC statistics
10. **Finalization** - Merge and generate reports
11. **Archive Diagnostics** - Collect reports and cleanup temp files

## File Structure

```
converted_harbinger_house/
├── front_matter/
│   ├── converted.md      # Raw OCR output
│   ├── cleaned.md        # After encoding fixes
│   ├── dict_cleaned.md   # After dictionary
│   └── ai_cleaned.md     # After AI cleanup
├── chapter1/
│   └── ...
├── statblocks/
│   ├── chapter1/
│   │   ├── TROLAN.md
│   │   ├── NARI.md
│   │   └── _all_statblocks.md
│   └── ...
├── final/
│   ├── front_matter.md
│   ├── chapter1.md
│   └── ...
├── conversion_stats.md
└── .master_checkpoint_*   # Resume checkpoints
```

## Configuration Reference

### pipeline_config.json

```json
{
  "input": "harbinger_house.pdf",
  "output_root": "converted_harbinger_house",
  "dpi": 300,
  "parallel_jobs": 4,
  
  "preprocessing": {
    "enabled": true,
    "deskew": true,
    "deskew_threshold": 40,
    "despeckle": true,
    "contrast_stretch": "5%x5%",
    "level": "15%,85%,1.3",
    "morphology": "close diamond:1"
  },
  
  "ocr": {
    "engine": "tesseract",
    "language": "eng",
    "psm": 1,
    "oem": 3,
    "confidence_threshold": 60,
    "output_confidence_report": true
  },
  
  "cleanup": {
    "encoding": true,
    "dictionary": true,
    "ai_backend": "claude"
  },
  
  "chapters": [
    {"name": "intro", "pages": "1-5"},
    {"name": "chapter1", "pages": "6-31"}
  ],
  
  "statblock_detection": {
    "enabled": true,
    "output_format": "markdown"
  }
}
```

## Dependencies

### Required (Pipeline)
- `fish` - Fish shell
- `pdftoppm` (poppler-utils) - PDF to image conversion
- `tesseract` - OCR engine
- `imagemagick` - Image preprocessing
- `pdftk` - PDF manipulation
- `python3` - Stat block extraction

### Required (Interactive Preprocessing)
- `node` >= 18.0.0 - JavaScript runtime
- `pnpm` >= 8.0.0 - Package manager for monorepo

### Optional
- `jq` - JSON config parsing
- `pdfinfo` (poppler-utils) - PDF metadata
- `claude` (Claude Code) - AI cleanup
- `pandoc` - PDF generation
- `code` (VS Code) - Open results

### Install on Ubuntu/Debian
```bash
sudo apt install fish poppler-utils tesseract-ocr imagemagick pdftk python3 jq
```

### Install on macOS
```bash
brew install fish poppler tesseract imagemagick pdftk-java python3 jq
```

## Tips for Best Results

1. **Higher DPI = Better OCR** - Use 400+ DPI for old/faded books
2. **Use demo mode to iterate quickly** - Test different DPI and preprocessing settings with `--demo` before processing the whole book
3. **Check confidence reports** - Focus manual review on low-confidence areas
4. **Use checkpoints** - For large books, run in stages
5. **Configure preprocessing** - Adjust deskew threshold for your specific PDF
6. **Extract stat blocks early** - Run before AI cleanup to get raw stats

## For Pathfinder 2e Conversion

After extraction, the AD&D 2e stat blocks are ready for conversion to PF2e. The formatted markdown output makes it easy to:

1. Review original stats
2. Map to PF2e equivalents
3. Create Foundry VTT-compatible JSON

## Troubleshooting

**Pipeline hangs on a chapter:**
```fish
./harbinger_master.fish book.pdf --status
# Then resume
./harbinger_master.fish book.pdf --resume
```

**OCR quality is poor:**
- Increase DPI: `--dpi 400`
- Check preprocessing settings in config
- Review `ocr_confidence_report.txt`

**Stat blocks not detected:**
- THAC0 is the primary detection anchor
- Check for OCR errors in stat keywords
- Run `./extract_statblocks.fish` manually with debug output

---

*Pipeline v2 - Built for Planescape, works for any tabletop RPG book*
