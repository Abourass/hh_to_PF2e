const express = require('express');
const cors = require('cors');
const { Server } = require('socket.io');
const http = require('http');
const path = require('path');
const fs = require('fs').promises;
const { applyMask, cropColumn } = require('./imageProcessor');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: '*' },
  maxHttpBufferSize: 50e6 // 50MB for large images
});

app.use(cors());
app.use(express.json({ limit: '50mb' }));

let SESSION_FILE = '';
let OUTPUT_ROOT = '';

// ============================================================================
// API ROUTES
// ============================================================================

/**
 * GET /api/session
 * Returns the current session state with all chapters and pages
 */
app.get('/api/session', async (req, res) => {
  try {
    const data = await fs.readFile(SESSION_FILE, 'utf-8');
    const session = JSON.parse(data);

    // Calculate total pages
    let totalPages = 0;
    for (const chapter of session.chapters) {
      totalPages += chapter.pages.length;
    }
    session.totalPages = totalPages;

    res.json(session);
  } catch (error) {
    console.error('[Server] Error loading session:', error.message);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/page/:chapter/:pageNum
 * Returns page image as base64 with existing metadata
 */
app.get('/api/page/:chapter/:pageNum', async (req, res) => {
  const { chapter, pageNum } = req.params;
  const paddedNum = pageNum.padStart(3, '0');
  const pagePath = path.join(OUTPUT_ROOT, chapter, '.temp', `page-${paddedNum}.png`);

  try {
    // Read image and convert to base64
    const imageBuffer = await fs.readFile(pagePath);
    const base64 = imageBuffer.toString('base64');

    // Check for existing metadata
    const metadataPath = pagePath.replace('.png', '-metadata.json');
    let metadata = { columns: [], processed: false };

    try {
      const metadataContent = await fs.readFile(metadataPath, 'utf-8');
      metadata = JSON.parse(metadataContent);
    } catch {
      // No metadata yet - that's OK
    }

    res.json({
      chapter,
      pageNum: parseInt(pageNum),
      imagePath: pagePath,
      imageData: base64,
      ...metadata,
    });
  } catch (error) {
    console.error(`[Server] Error loading page ${chapter}/${pageNum}:`, error.message);
    res.status(404).json({ error: 'Page not found' });
  }
});

/**
 * POST /api/save
 * Saves user edits: applies mask, crops columns, saves metadata
 */
app.post('/api/save', async (req, res) => {
  const { chapter, pageNum, columns, maskData } = req.body;

  console.log(`[Server] Saving page ${chapter}/${pageNum} with ${columns.length} columns`);

  try {
    const paddedNum = pageNum.toString().padStart(3, '0');
    const basePath = path.join(OUTPUT_ROOT, chapter, '.temp', `page-${paddedNum}`);
    const originalPath = `${basePath}.png`;
    const cleanedPath = `${basePath}-cleaned.png`;

    // 1. Apply mask if provided, otherwise copy original
    if (maskData) {
      await applyMask(originalPath, maskData, cleanedPath);
    } else {
      await fs.copyFile(originalPath, cleanedPath);
      console.log(`[Server] No mask - copied original to cleaned`);
    }

    // 2. Crop columns (if any)
    for (let i = 0; i < columns.length; i++) {
      const col = columns[i];
      const cropPath = `${basePath}-column-${col.order || (i + 1)}.png`;
      await cropColumn(cleanedPath, col, cropPath);
    }

    // 3. Save metadata
    const metadata = {
      columns,
      processed: true,
      timestamp: new Date().toISOString(),
      maskApplied: !!maskData,
    };
    await fs.writeFile(`${basePath}-metadata.json`, JSON.stringify(metadata, null, 2));

    // 4. Update session state
    const sessionContent = await fs.readFile(SESSION_FILE, 'utf-8');
    const session = JSON.parse(sessionContent);

    if (!session.processedPages) session.processedPages = [];
    const pageId = `${chapter}:${pageNum}`;

    if (!session.processedPages.includes(pageId)) {
      session.processedPages.push(pageId);
    }

    await fs.writeFile(SESSION_FILE, JSON.stringify(session, null, 2));

    // 5. Emit progress update via WebSocket
    const totalPages = session.totalPages || 0;
    io.emit('progress', {
      total: totalPages,
      processed: session.processedPages.length,
      percentage: totalPages > 0 ? Math.round((session.processedPages.length / totalPages) * 100) : 0,
    });

    console.log(`[Server] ✓ Saved page ${chapter}/${pageNum} (${session.processedPages.length}/${totalPages})`);
    res.json({ success: true });

  } catch (error) {
    console.error('[Server] Save error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/finish
 * Marks the session as completed
 */
app.post('/api/finish', async (req, res) => {
  try {
    const sessionContent = await fs.readFile(SESSION_FILE, 'utf-8');
    const session = JSON.parse(sessionContent);

    session.status = 'completed';
    session.completedAt = new Date().toISOString();

    await fs.writeFile(SESSION_FILE, JSON.stringify(session, null, 2));

    console.log('[Server] Session marked as completed');
    io.emit('session-completed', { message: 'Preprocessing complete!' });

    res.json({ success: true });
  } catch (error) {
    console.error('[Server] Error finishing session:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// WEBSOCKET
// ============================================================================

io.on('connection', (socket) => {
  console.log('[WebSocket] Client connected:', socket.id);

  socket.on('disconnect', () => {
    console.log('[WebSocket] Client disconnected:', socket.id);
  });

  socket.on('ping', () => {
    socket.emit('pong', { timestamp: Date.now() });
  });
});

// ============================================================================
// SERVER STARTUP
// ============================================================================

/**
 * Start the server
 * @param {string} sessionFile - Path to .interactive_session.json
 * @param {number} port - Server port (default: 3001)
 */
function start(sessionFile, port = 3001) {
  SESSION_FILE = sessionFile;
  OUTPUT_ROOT = path.dirname(sessionFile);

  server.listen(port, () => {
    console.log('');
    console.log('╔═══════════════════════════════════════════════════════════╗');
    console.log('║  Interactive Preprocessing Server                        ║');
    console.log('╚═══════════════════════════════════════════════════════════╝');
    console.log('');
    console.log(`  Server:  http://localhost:${port}`);
    console.log(`  Session: ${sessionFile}`);
    console.log(`  Output:  ${OUTPUT_ROOT}`);
    console.log('');
    console.log('  Ready for connections...');
    console.log('');
  });
}

module.exports = { start };

// ============================================================================
// CLI ENTRY POINT
// ============================================================================

if (require.main === module) {
  const args = process.argv.slice(2);
  const sessionFile = args[0] || '.interactive_session.json';
  const port = parseInt(args[1]) || 3001;

  // Validate session file exists
  const fs_sync = require('fs');
  if (!fs_sync.existsSync(sessionFile)) {
    console.error(`[Error] Session file not found: ${sessionFile}`);
    process.exit(1);
  }

  start(sessionFile, port);
}
