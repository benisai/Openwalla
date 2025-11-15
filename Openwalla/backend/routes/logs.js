const express = require('express');
const router = express.Router();
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const LOG_DIR = path.join(__dirname, '../../logs');
const BACKEND_LOG = path.join(LOG_DIR, 'backend.log');
const FRONTEND_LOG = path.join(LOG_DIR, 'frontend.log');

// Get log file path
function getLogPath(type) {
  return type === 'backend' ? BACKEND_LOG : FRONTEND_LOG;
}

// Read last N lines of a file
function readLastLines(filePath, lines = 100) {
  return new Promise((resolve, reject) => {
    if (!fs.existsSync(filePath)) {
      resolve('');
      return;
    }

    const tail = spawn('tail', ['-n', lines.toString(), filePath]);
    let output = '';

    tail.stdout.on('data', (data) => {
      output += data.toString();
    });

    tail.on('close', (code) => {
      if (code === 0) {
        resolve(output);
      } else {
        reject(new Error(`tail process exited with code ${code}`));
      }
    });

    tail.on('error', (err) => {
      reject(err);
    });
  });
}

// Get logs (last N lines)
router.get('/:type', async (req, res) => {
  try {
    const { type } = req.params;
    const lines = parseInt(req.query.lines) || 100;

    if (type !== 'backend' && type !== 'frontend') {
      return res.status(400).json({ error: 'Invalid log type' });
    }

    const logPath = getLogPath(type);
    const content = await readLastLines(logPath, lines);

    res.json({ content, path: logPath });
  } catch (error) {
    console.error('Error reading logs:', error);
    res.status(500).json({ error: error.message });
  }
});

// Tail logs (Server-Sent Events)
router.get('/:type/tail', (req, res) => {
  const { type } = req.params;

  if (type !== 'backend' && type !== 'frontend') {
    return res.status(400).json({ error: 'Invalid log type' });
  }

  const logPath = getLogPath(type);

  // Set headers for SSE
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');

  // Send initial connection message
  res.write(`data: ${JSON.stringify({ type: 'connected' })}\n\n`);

  // Check if file exists, if not wait for it
  if (!fs.existsSync(logPath)) {
    res.write(`data: ${JSON.stringify({ type: 'info', message: 'Waiting for log file...' })}\n\n`);
  }

  // Start tailing the log file
  const tail = spawn('tail', ['-f', '-n', '0', logPath]);

  tail.stdout.on('data', (data) => {
    const lines = data.toString().split('\n').filter(line => line.trim());
    lines.forEach(line => {
      res.write(`data: ${JSON.stringify({ type: 'log', message: line })}\n\n`);
    });
  });

  tail.stderr.on('data', (data) => {
    console.error('Tail error:', data.toString());
  });

  // Clean up on client disconnect
  req.on('close', () => {
    tail.kill();
  });

  tail.on('error', (err) => {
    console.error('Tail process error:', err);
    res.write(`data: ${JSON.stringify({ type: 'error', message: err.message })}\n\n`);
  });
});

module.exports = router;
