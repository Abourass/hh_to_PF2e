import { Component, onMount, createSignal, createEffect, Show } from 'solid-js';
import { initSession, session, currentPage, nextPage, prevPage, canGoNext, canGoPrev, isSaving, setMaskDataGetter } from './stores/sessionStore';
import { columns, setColumns, addColumn, removeColumn, syncColumnsFromPage } from './stores/imageStore';
import { toolState, setActiveTool, setBrushSize } from './stores/toolStore';
import { detectPageColor } from './services/colorDetector';
import { finishSession } from './services/api';
import { drawRectangle, drawBrush } from './utils/canvas';
import type { Column } from './types';

const App: Component = () => {
  let canvasRef: HTMLCanvasElement | undefined;
  let maskCanvasRef: HTMLCanvasElement | undefined;
  let imageRef: HTMLImageElement | undefined;

  const [isDrawing, setIsDrawing] = createSignal(false);
  const [startPos, setStartPos] = createSignal({ x: 0, y: 0 });
  const [lastPos, setLastPos] = createSignal({ x: 0, y: 0 });

  onMount(async () => {
    await initSession();

    // Set up mask data getter
    setMaskDataGetter(() => {
      if (!maskCanvasRef) return undefined;
      return maskCanvasRef.toDataURL();
    });
  });

  // Load image when page changes
  createEffect(() => {
    const page = currentPage();
    if (page && imageRef) {
      syncColumnsFromPage();
      imageRef.src = `data:image/png;base64,${page.imageData}`;
    }
  });

  // Redraw canvas when columns change
  createEffect(() => {
    const cols = columns();
    redrawCanvas();
  });

  function handleImageLoad() {
    if (!canvasRef || !imageRef || !maskCanvasRef) return;

    // Set canvas size to match image
    canvasRef.width = imageRef.width;
    canvasRef.height = imageRef.height;
    maskCanvasRef.width = imageRef.width;
    maskCanvasRef.height = imageRef.height;

    // Clear mask canvas to white (nothing masked)
    const maskCtx = maskCanvasRef.getContext('2d');
    if (maskCtx) {
      maskCtx.fillStyle = 'white';
      maskCtx.fillRect(0, 0, maskCanvasRef.width, maskCanvasRef.height);
    }

    redrawCanvas();
  }

  function redrawCanvas() {
    if (!canvasRef || !imageRef) return;

    const ctx = canvasRef.getContext('2d');
    if (!ctx) return;

    // Clear and draw image
    ctx.clearRect(0, 0, canvasRef.width, canvasRef.height);
    ctx.drawImage(imageRef!, 0, 0);

    // Draw existing columns
    ctx.strokeStyle = '#3b82f6';
    ctx.lineWidth = 3;
    columns().forEach((col, index) => {
      ctx.strokeRect(col.x, col.y, col.width, col.height);

      // Draw column number
      ctx.fillStyle = '#3b82f6';
      ctx.font = '24px sans-serif';
      ctx.fillText(`${col.order}`, col.x + 10, col.y + 30);
    });
  }

  function handleMouseDown(e: MouseEvent) {
    if (!canvasRef) return;

    const rect = canvasRef.getBoundingClientRect();
    const x = ((e.clientX - rect.left) * canvasRef.width) / rect.width;
    const y = ((e.clientY - rect.top) * canvasRef.height) / rect.height;

    setIsDrawing(true);
    setStartPos({ x, y });
    setLastPos({ x, y });
  }

  function handleMouseMove(e: MouseEvent) {
    if (!isDrawing() || !canvasRef) return;

    const rect = canvasRef.getBoundingClientRect();
    const x = ((e.clientX - rect.left) * canvasRef.width) / rect.width;
    const y = ((e.clientY - rect.top) * canvasRef.height) / rect.height;

    const tool = toolState().activeTool;

    if (tool === 'select') {
      // Redraw everything plus preview rectangle
      redrawCanvas();
      const ctx = canvasRef.getContext('2d');
      if (ctx) {
        drawRectangle(ctx, startPos(), { x, y });
      }
    } else if (tool === 'brush' && maskCanvasRef) {
      // Draw on mask canvas
      const maskCtx = maskCanvasRef.getContext('2d');
      if (maskCtx) {
        maskCtx.strokeStyle = toolState().brushColor;
        maskCtx.lineWidth = toolState().brushSize;
        maskCtx.lineCap = 'round';
        maskCtx.beginPath();
        maskCtx.moveTo(lastPos().x, lastPos().y);
        maskCtx.lineTo(x, y);
        maskCtx.stroke();
      }
      setLastPos({ x, y });
    }
  }

  function handleMouseUp(e: MouseEvent) {
    if (!isDrawing() || !canvasRef) return;

    const rect = canvasRef.getBoundingClientRect();
    const x = ((e.clientX - rect.left) * canvasRef.width) / rect.width;
    const y = ((e.clientY - rect.top) * canvasRef.height) / rect.height;

    const tool = toolState().activeTool;

    if (tool === 'select') {
      // Finalize column rectangle
      const start = startPos();
      const width = Math.abs(x - start.x);
      const height = Math.abs(y - start.y);
      const left = Math.min(x, start.x);
      const top = Math.min(y, start.y);

      if (width > 10 && height > 10) {
        // Only create column if it's big enough
        const newColumn: Column = {
          id: crypto.randomUUID(),
          x: Math.round(left),
          y: Math.round(top),
          width: Math.round(width),
          height: Math.round(height),
          order: columns().length + 1,
        };
        addColumn(newColumn);
      }
    }

    setIsDrawing(false);
    redrawCanvas();
  }

  async function handleNext() {
    await nextPage();
  }

  async function handlePrev() {
    await prevPage();
  }

  async function handleFinish() {
    if (confirm('Mark preprocessing as complete and close?')) {
      await finishSession();
      alert('Preprocessing complete! You can close this window.');
    }
  }

  return (
    <div class="app">
      {/* Header */}
      <header style="background: #3b82f6; color: white; padding: 1rem;">
        <h1 style="font-size: 1.5rem; font-weight: bold;">Interactive Preprocessing - HarbingerHouse</h1>
      </header>

      {/* Toolbar */}
      <div class="toolbar">
        <button
          class={`btn ${toolState().activeTool === 'select' ? 'btn-active' : ''}`}
          onClick={() => setActiveTool('select')}
        >
          📐 Select Columns
        </button>

        <button
          class={`btn ${toolState().activeTool === 'brush' ? 'btn-active' : ''}`}
          onClick={() => setActiveTool('brush')}
        >
          🖌️ Cleanup Brush
        </button>

        <div style="border-left: 1px solid #d1d5db; height: 2rem;" />

        <label>Brush Size:</label>
        <input
          type="range"
          min="5"
          max="100"
          value={toolState().brushSize}
          onInput={(e) => setBrushSize(parseInt(e.currentTarget.value))}
          style="width: 150px;"
        />

        <button class="btn" onClick={detectPageColor}>
          🎨 Auto-Detect Color
        </button>

        <div style="flex: 1;" />

        <Show when={isSaving()}>
          <span style="color: #3b82f6;">💾 Saving...</span>
        </Show>
      </div>

      {/* Main Content */}
      <main style="display: flex; flex: 1; overflow: hidden;">
        {/* Canvas Area */}
        <div style="flex: 1; overflow: auto; background: #f9fafb; display: flex; justify-content: center; align-items: center; padding: 2rem;">
          <div class="canvas-container">
            <img
              ref={imageRef}
              style="display: none;"
              onLoad={handleImageLoad}
            />
            <canvas
              ref={canvasRef}
              onMouseDown={handleMouseDown}
              onMouseMove={handleMouseMove}
              onMouseUp={handleMouseUp}
              style="border: 2px solid #d1d5db; cursor: crosshair; max-width: 100%; max-height: 100%;"
            />
            <canvas
              ref={maskCanvasRef}
              style="display: none;"
            />
          </div>
        </div>

        {/* Sidebar */}
        <aside class="sidebar">
          <h3 style="font-weight: bold; margin-bottom: 1rem;">Columns ({columns().length})</h3>
          <Show when={columns().length === 0}>
            <p style="color: #6b7280;">Draw rectangles around text columns using the Select tool.</p>
          </Show>
          {columns().map((col, index) => (
            <div class="column-list-item">
              <div>
                <strong>Column {col.order}</strong>
                <div style="font-size: 0.875rem; color: #6b7280;">
                  {col.width}×{col.height}px
                </div>
              </div>
              <button
                class="btn"
                onClick={() => removeColumn(col.id)}
                style="padding: 0.25rem 0.5rem; background: #ef4444; color: white; border: none;"
              >
                ✕
              </button>
            </div>
          ))}
        </aside>
      </main>

      {/* Footer */}
      <footer class="footer">
        <button class="btn" onClick={handlePrev} disabled={!canGoPrev()}>
          ← Previous
        </button>

        <div class="progress">
          <Show when={session()}>
            <div style="text-align: center; margin-bottom: 0.5rem;">
              Page {(currentPage()?.pageNum || 0)} - {(session()?.processedPages?.length || 0)} / {session()?.totalPages || 0} processed
            </div>
            <div class="progress-bar">
              <div
                class="progress-bar-fill"
                style={`width: ${((session()?.processedPages?.length || 0) / (session()?.totalPages || 1)) * 100}%`}
              />
            </div>
          </Show>
        </div>

        <button class="btn" onClick={handleNext} disabled={!canGoNext()}>
          Next →
        </button>

        <button class="btn btn-primary" onClick={handleFinish}>
          ✓ Finish
        </button>
      </footer>
    </div>
  );
};

export default App;
