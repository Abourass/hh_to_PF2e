export function drawRectangle(
  ctx: CanvasRenderingContext2D,
  start: { x: number; y: number },
  end: { x: number; y: number }
) {
  const width = end.x - start.x;
  const height = end.y - start.y;

  ctx.strokeStyle = '#0066ff';
  ctx.lineWidth = 2;
  ctx.setLineDash([5, 5]);
  ctx.strokeRect(start.x, start.y, width, height);
  ctx.setLineDash([]);
}

export function drawBrush(
  ctx: CanvasRenderingContext2D,
  pos: { x: number; y: number },
  size: number,
  color: string
) {
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(pos.x, pos.y, size / 2, 0, Math.PI * 2);
  ctx.fill();
}

export function clearCanvas(ctx: CanvasRenderingContext2D, width: number, height: number) {
  ctx.clearRect(0, 0, width, height);
}
