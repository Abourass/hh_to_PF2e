const { execFile } = require('child_process');
const { promisify } = require('util');
const fs = require('fs').promises;
const path = require('path');

const execFileAsync = promisify(execFile);

// Detect ImageMagick command (magick vs convert)
let MAGICK_CMD = 'magick';

async function detectMagick() {
  try {
    await execFileAsync('magick', ['--version']);
    MAGICK_CMD = 'magick';
    console.log('[ImageProcessor] Using ImageMagick 7+ (magick command)');
  } catch {
    try {
      await execFileAsync('convert', ['--version']);
      MAGICK_CMD = 'convert';
      console.log('[ImageProcessor] Using ImageMagick 6 (convert command)');
    } catch {
      console.error('[ImageProcessor] ImageMagick not found! Install imagemagick first.');
    }
  }
}

// Run detection on module load
detectMagick();

/**
 * Apply a mask to an image (erase regions painted by user)
 * @param {string} inputPath - Path to original image
 * @param {string} maskBase64 - Base64 encoded mask image
 * @param {string} outputPath - Path for cleaned output
 */
async function applyMask(inputPath, maskBase64, outputPath) {
  // Write mask to temp file
  const maskPath = inputPath.replace('.png', '-mask-temp.png');
  const maskBuffer = Buffer.from(maskBase64.split(',')[1], 'base64');
  await fs.writeFile(maskPath, maskBuffer);

  try {
    // Use ImageMagick composite to apply mask
    // Mask white = keep, black = erase (paint becomes transparent)
    await execFileAsync(MAGICK_CMD, [
      inputPath,
      maskPath,
      '-alpha', 'off',
      '-compose', 'CopyOpacity',
      '-composite',
      '-background', 'white',
      '-alpha', 'remove',
      outputPath,
    ]);

    console.log(`[ImageProcessor] Applied mask: ${path.basename(inputPath)} → ${path.basename(outputPath)}`);
  } finally {
    // Clean up temp mask file
    await fs.unlink(maskPath).catch(() => {});
  }
}

/**
 * Crop a column from an image
 * @param {string} inputPath - Path to input image
 * @param {object} column - Column definition {x, y, width, height}
 * @param {string} outputPath - Path for cropped output
 */
async function cropColumn(inputPath, column, outputPath) {
  const { x, y, width, height } = column;
  const cropGeometry = `${width}x${height}+${x}+${y}`;

  await execFileAsync(MAGICK_CMD, [
    inputPath,
    '-crop', cropGeometry,
    '+repage',
    outputPath,
  ]);

  console.log(`[ImageProcessor] Cropped column: ${cropGeometry} → ${path.basename(outputPath)}`);
}

module.exports = {
  applyMask,
  cropColumn,
};
