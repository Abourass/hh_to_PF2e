import { currentPage } from '../stores/sessionStore';
import { setBrushColor } from '../stores/toolStore';

/**
 * Auto-detect the most common color in the image (likely page background)
 * Samples from corners and edges where the page background is usually visible
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
  const sampleSize = 100;
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

  const colorCounts = new Map<string, number>();

  for (const region of sampleRegions) {
    const imageData = ctx.getImageData(region.x, region.y, region.w, region.h);

    for (let i = 0; i < imageData.data.length; i += 40) {
      // Sample every 10 pixels
      const r = imageData.data[i];
      const g = imageData.data[i + 1];
      const b = imageData.data[i + 2];
      const color = `#${r.toString(16).padStart(2, '0')}${g
        .toString(16)
        .padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;

      colorCounts.set(color, (colorCounts.get(color) || 0) + 1);
    }
  }

  // Find most common color
  let maxCount = 0;
  let mostCommonColor = '#ffffff';

  colorCounts.forEach((count, color) => {
    if (count > maxCount) {
      maxCount = count;
      mostCommonColor = color;
    }
  });

  // Auto-set brush color when detected
  setBrushColor(mostCommonColor);
  console.log(`[ColorDetector] Detected page color: ${mostCommonColor}`);

  return mostCommonColor;
}
