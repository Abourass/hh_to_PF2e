import { currentPage } from '../stores/sessionStore';
import { setBrushColor } from '../stores/toolStore';

/**
 * Auto-detect the most common color in the image (likely page background)
 * Samples from corners and edges where the page background is usually visible
 * Uses color quantization to group similar colors together
 */
export async function detectPageColor(): Promise<string> {
  const page = currentPage();
  if (!page || !page.imageData) return '#ffffff';

  // Create temporary canvas
  const canvas = document.createElement('canvas');
  const ctx = canvas.getContext('2d');
  if (!ctx) return '#ffffff';

  // Load image
  const img = new Image();
  img.src = `data:image/png;base64,${page.imageData}`;
  await new Promise(resolve => (img.onload = resolve));

  canvas.width = img.width;
  canvas.height = img.height;
  ctx.drawImage(img, 0, 0);

  // Sample corners and edges (page background is usually at borders)
  const sampleSize = 150;
  const sampleRegions = [
    { x: 0, y: 0, w: sampleSize, h: sampleSize }, // Top-left
    { x: img.width - sampleSize, y: 0, w: sampleSize, h: sampleSize }, // Top-right
    { x: 0, y: img.height - sampleSize, w: sampleSize, h: sampleSize }, // Bottom-left
    {
      x: img.width - sampleSize,
      y: img.height - sampleSize,
      w: sampleSize,
      h: sampleSize,
    }, // Bottom-right
  ];

  // Collect RGB values for averaging
  const colorSamples: Array<{ r: number; g: number; b: number }> = [];

  for (const region of sampleRegions) {
    const imageData = ctx.getImageData(region.x, region.y, region.w, region.h);

    // Sample every 4th pixel (i += 16 means every 4 pixels)
    for (let i = 0; i < imageData.data.length; i += 16) {
      const r = imageData.data[i];
      const g = imageData.data[i + 1];
      const b = imageData.data[i + 2];

      // Only sample light-colored pixels (likely background, not text)
      // Brightness threshold: average RGB > 200
      const brightness = (r + g + b) / 3;
      if (brightness > 180) {
        colorSamples.push({ r, g, b });
      }
    }
  }

  if (colorSamples.length === 0) {
    // Fallback to white if no light pixels found
    setBrushColor('#ffffff');
    console.log(`[ColorDetector] No light pixels found, using white`);
    return '#ffffff';
  }

  // Calculate average color from samples
  let totalR = 0;
  let totalG = 0;
  let totalB = 0;

  for (const sample of colorSamples) {
    totalR += sample.r;
    totalG += sample.g;
    totalB += sample.b;
  }

  const avgR = Math.round(totalR / colorSamples.length);
  const avgG = Math.round(totalG / colorSamples.length);
  const avgB = Math.round(totalB / colorSamples.length);

  const detectedColor = `#${avgR.toString(16).padStart(2, '0')}${avgG
    .toString(16)
    .padStart(2, '0')}${avgB.toString(16).padStart(2, '0')}`;

  // Auto-set brush color when detected
  setBrushColor(detectedColor);
  console.log(`[ColorDetector] Detected page color: ${detectedColor} (from ${colorSamples.length} samples)`);

  return detectedColor;
}
