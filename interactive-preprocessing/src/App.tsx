import { Component, onMount, createSignal, createEffect, Show, For } from 'solid-js';
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
  let containerRef: HTMLDivElement | undefined;

  const [isDrawing, setIsDrawing] = createSignal(false);
  const [startPos, setStartPos] = createSignal({ x: 0, y: 0 });
  const [lastPos, setLastPos] = createSignal({ x: 0, y: 0 });
  const [zoom, setZoom] = createSignal(1);
  const [selectedColumnId, setSelectedColumnId] = createSignal<string | null>(null);
  const [dragPreview, setDragPreview] = createSignal<{x: number, y: number, width: number, height: number} | null>(null);

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
      setZoom(1); // Reset zoom when changing pages
      setSelectedColumnId(null); // Clear selection when changing pages
    }
  });

  // Redraw canvas when columns change or selection changes
  createEffect(() => {
    const cols = columns();
    const selected = selectedColumnId();
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

    const selectedId = selectedColumnId();

    // Draw existing columns
    columns().forEach((col, index) => {
      const isSelected = col.id === selectedId;

      if (isSelected) {
        // Highlighted selected column
        ctx.strokeStyle = '#10b981';
        ctx.fillStyle = 'rgba(16, 185, 129, 0.3)';
        ctx.lineWidth = 5;
      } else {
        // Normal columns
        ctx.strokeStyle = '#3b82f6';
        ctx.fillStyle = 'rgba(59, 130, 246, 0.1)';
        ctx.lineWidth = 3;
      }

      ctx.fillRect(col.x, col.y, col.width, col.height);
      ctx.strokeRect(col.x, col.y, col.width, col.height);

      // Draw column number
      ctx.fillStyle = isSelected ? '#10b981' : '#3b82f6';
      ctx.font = 'bold 28px sans-serif';
      ctx.strokeStyle = 'white';
      ctx.lineWidth = 4;
      ctx.strokeText(`${col.order}`, col.x + 10, col.y + 35);
      ctx.fillText(`${col.order}`, col.x + 10, col.y + 35);
    });

    // Draw drag preview
    const preview = dragPreview();
    if (preview) {
      ctx.strokeStyle = '#f59e0b';
      ctx.fillStyle = 'rgba(245, 158, 11, 0.2)';
      ctx.lineWidth = 3;
      ctx.setLineDash([5, 5]);
      ctx.fillRect(preview.x, preview.y, preview.width, preview.height);
      ctx.strokeRect(preview.x, preview.y, preview.width, preview.height);
      ctx.setLineDash([]);
    }
  }

  function getCanvasCoords(e: MouseEvent): { x: number; y: number } {
    if (!canvasRef) return { x: 0, y: 0 };
    const rect = canvasRef.getBoundingClientRect();
    const x = ((e.clientX - rect.left) * canvasRef.width) / rect.width;
    const y = ((e.clientY - rect.top) * canvasRef.height) / rect.height;
    return { x, y };
  }

  function handleMouseDown(e: MouseEvent) {
    if (!canvasRef) return;

    const { x, y } = getCanvasCoords(e);

    setIsDrawing(true);
    setStartPos({ x, y });
    setLastPos({ x, y });
  }

  function handleMouseMove(e: MouseEvent) {
    if (!isDrawing() || !canvasRef) return;

    const { x, y } = getCanvasCoords(e);
    const tool = toolState().activeTool;

    if (tool === 'select') {
      // Update preview rectangle
      const start = startPos();
      const width = x - start.x;
      const height = y - start.y;
      const left = width < 0 ? x : start.x;
      const top = height < 0 ? y : start.y;

      setDragPreview({
        x: left,
        y: top,
        width: Math.abs(width),
        height: Math.abs(height)
      });
      redrawCanvas();
    } else if (tool === 'brush' && maskCanvasRef) {
      // Draw circles for brush strokes
      const maskCtx = maskCanvasRef.getContext('2d');
      if (maskCtx) {
        const brushSize = toolState().brushSize;

        // Draw line of circles between last position and current
        const dx = x - lastPos().x;
        const dy = y - lastPos().y;
        const distance = Math.sqrt(dx * dx + dy * dy);
        const steps = Math.max(1, Math.floor(distance / (brushSize / 4)));

        for (let i = 0; i <= steps; i++) {
          const t = i / steps;
          const cx = lastPos().x + dx * t;
          const cy = lastPos().y + dy * t;

          maskCtx.fillStyle = toolState().brushColor;
          maskCtx.beginPath();
          maskCtx.arc(cx, cy, brushSize / 2, 0, Math.PI * 2);
          maskCtx.fill();
        }
      }
      setLastPos({ x, y });
    }
  }

  function handleMouseUp(e: MouseEvent) {
    if (!isDrawing() || !canvasRef) return;

    const { x, y } = getCanvasCoords(e);
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
      setDragPreview(null);
    }

    setIsDrawing(false);
    redrawCanvas();
  }

  function handleWheel(e: WheelEvent) {
    e.preventDefault();
    const delta = e.deltaY > 0 ? -0.1 : 0.1;
    setZoom(Math.min(Math.max(0.1, zoom() + delta), 5));
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

  // Get current chapter info
  function getCurrentChapter() {
    const page = currentPage();
    if (!page) return null;
    const sess = session();
    if (!sess) return null;
    return sess.chapters.find(ch => ch.name === page.chapter);
  }

  // Get progress within current chapter
  function getChapterProgress() {
    const chapter = getCurrentChapter();
    const page = currentPage();
    if (!chapter || !page) return { current: 0, total: 0 };

    const currentPageIndex = chapter.pages.findIndex(p => p.includes(`page-${page.pageNum}`));
    return {
      current: currentPageIndex + 1,
      total: chapter.pages.length
    };
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

        <label>Brush Size: {toolState().brushSize}px</label>
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

        <div style="border-left: 1px solid #d1d5db; height: 2rem;" />

        <label>Zoom: {Math.round(zoom() * 100)}%</label>
        <button class="btn" onClick={() => setZoom(1)}>
          Reset Zoom
        </button>

        <div style="flex: 1;" />

        <Show when={isSaving()}>
          <span style="color: #3b82f6;">💾 Saving...</span>
        </Show>
      </div>

      {/* Main Content */}
      <main style="display: flex; flex: 1; overflow: hidden;">
        {/* Canvas Area */}
        <div
          ref={containerRef}
          style="flex: 1; overflow: auto; background: #f9fafb; display: flex; justify-content: center; align-items: center; padding: 2rem;"
        >
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
              onWheel={handleWheel}
              style={`border: 2px solid #d1d5db; cursor: crosshair; transform: scale(${zoom()}); transform-origin: center; max-width: 100%; max-height: 100%;`}
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
            <p style="color: #6b7280; font-size: 0.875rem;">Draw rectangles around text columns using the Select tool.</p>
          </Show>
          <For each={columns()}>
            {(col) => (
              <div
                class={`column-list-item ${selectedColumnId() === col.id ? 'column-list-item-selected' : ''}`}
                onClick={() => setSelectedColumnId(selectedColumnId() === col.id ? null : col.id)}
                style="cursor: pointer;"
              >
                <div style="flex: 1;">
                  <strong>Column {col.order}</strong>
                  <div style="font-size: 0.875rem; color: #6b7280;">
                    {col.width}×{col.height}px at ({col.x}, {col.y})
                  </div>
                </div>
                <button
                  class="btn"
                  onClick={(e) => {
                    e.stopPropagation();
                    if (confirm(`Delete Column ${col.order}?`)) {
                      removeColumn(col.id);
                      if (selectedColumnId() === col.id) {
                        setSelectedColumnId(null);
                      }
                    }
                  }}
                  style="padding: 0.25rem 0.5rem; background: #ef4444; color: white; border: none;"
                >
                  🗑️
                </button>
              </div>
            )}
          </For>
        </aside>
      </main>

      {/* Footer */}
      <footer class="footer">
        <button class="btn" onClick={handlePrev} disabled={!canGoPrev()}>
          ← Previous
        </button>

        <div class="progress">
          <Show when={session() && currentPage()}>
            <div style="text-align: center; margin-bottom: 0.5rem; font-size: 0.875rem;">
              <strong>{getCurrentChapter()?.name || 'Unknown'}</strong> —
              Page {getChapterProgress().current} of {getChapterProgress().total} in chapter ({currentPage()?.pageNum})
              <div style="color: #6b7280; font-size: 0.75rem; margin-top: 0.25rem;">
                Total: {session()?.processedPages?.length || 0} / {session()?.totalPages || 0} processed overall
              </div>
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
