const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { WebSocketServer, WebSocket } = require('ws');

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8', '.txt': 'text/plain; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif',
  '.webp': 'image/webp', '.avif': 'image/avif', '.ico': 'image/x-icon', '.woff': 'font/woff', '.woff2': 'font/woff2',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.mp4': 'video/mp4', '.webm': 'video/webm', '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav', '.pdf': 'application/pdf',
};
// The relay's own browser files. Nothing else under relay/ is ever served.
const ASSETS = new Set(['client.js', 'gesture.js', 'preview.html', 'vendor/three.module.min.js', 'vendor/three.core.min.js', 'models/left.json', 'models/right.json']);
const INJECT = '<script src="/_airslide/client.js"></script><script type="module" src="/_airslide/gesture.js"></script>';
const hidden = relative => relative.split(/[\\/]/).some(part => part.startsWith('.'));

function createRelay({ token, deckDir = path.join(__dirname, '..', 'example-deck'), publicDir = path.join(__dirname, 'public'), maxViewers = 500 }) {
  if (!token || token.length < 32) throw new Error('REMOTE_TOKEN must have at least 32 characters');
  const deckRoot = fs.realpathSync(deckDir);
  const clients = new Set();
  const seen = new Map();
  let sequence = 0, lastCommand = 0;
  const authorized = header => {
    if (typeof header !== 'string' || !header.startsWith('Bearer ')) return false;
    const a = Buffer.from(header.slice(7)), b = Buffer.from(token);
    return a.length === b.length && crypto.timingSafeEqual(a, b);
  };
  // Map a request path to a file inside the deck folder. Hidden paths, escapes and unknown types stay unreachable.
  function deckFile(pathname) {
    let relative;
    try { relative = decodeURIComponent(pathname); } catch { return null; }
    if (relative.includes('\0') || hidden(relative)) return null;
    try {
      let file = path.join(deckRoot, relative);
      if (fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
      file = fs.realpathSync(file);
      const inside = file.startsWith(deckRoot + path.sep) && !hidden(path.relative(deckRoot, file));
      return inside && fs.statSync(file).isFile() && TYPES[path.extname(file).toLowerCase()] ? file : null;
    } catch { return null; }
  }
  function serve(req, res, file, { inject = false, cache = 'no-store' } = {}) {
    const headers = { 'Content-Type': TYPES[path.extname(file).toLowerCase()], 'Cache-Control': cache };
    if (inject) {
      const html = fs.readFileSync(file, 'utf8');
      const at = html.search(/<\/body\s*>(?![\s\S]*<\/body\s*>)/i);
      const body = Buffer.from(at === -1 ? html + INJECT : html.slice(0, at) + INJECT + html.slice(at));
      res.writeHead(200, { ...headers, 'Content-Length': body.length });
      return res.end(req.method === 'HEAD' ? undefined : body);
    }
    const size = fs.statSync(file).size;
    let start = 0, end = size - 1, status = 200;
    // A single byte range is enough for Safari to play deck videos.
    const range = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range || '');
    if (range && (range[1] || range[2])) {
      start = range[1] ? Number(range[1]) : Math.max(0, size - Number(range[2]));
      end = range[1] && range[2] ? Math.min(Number(range[2]), size - 1) : size - 1;
      if (start > end || start >= size) return res.writeHead(416, { 'Content-Range': `bytes */${size}` }).end();
      status = 206; headers['Content-Range'] = `bytes ${start}-${end}/${size}`;
    }
    res.writeHead(status, { ...headers, 'Accept-Ranges': 'bytes', 'Content-Length': size ? end - start + 1 : 0 });
    if (req.method === 'HEAD' || !size) return res.end();
    fs.createReadStream(file, { start, end }).on('error', () => res.destroy()).pipe(res);
  }
  function handle(req, res) {
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    let url;
    try { url = new URL(req.url, 'http://localhost'); } catch { return res.writeHead(400).end(); }
    if (url.pathname === '/healthz') return res.writeHead(200).end('ok');
    if (url.pathname === '/api/command' && req.method === 'POST') {
      if (!authorized(req.headers.authorization)) return res.writeHead(401).end();
      let body = '';
      req.on('data', data => { body += data; if (body.length > 1024) req.destroy(); });
      req.on('end', () => {
        let command;
        try { command = JSON.parse(body); } catch { return res.writeHead(400).end(); }
        if (!command || !['next', 'prev'].includes(command.direction) || typeof command.id !== 'string' || command.id.length > 80 || !command.id.length) return res.writeHead(400).end();
        if (command.side !== undefined && !['left', 'right'].includes(command.side)) return res.writeHead(400).end();
        const now = Date.now();
        for (const [id, time] of seen) if (now - time > 60000) seen.delete(id);
        if (seen.has(command.id)) return res.writeHead(200).end(JSON.stringify({ duplicate: true }));
        if (now - lastCommand < 250) return res.writeHead(429).end();
        lastCommand = now; seen.set(command.id, now);
        const payload = JSON.stringify({ direction: command.direction, sequence: ++sequence, ...(command.side ? { side: command.side } : {}) });
        for (const ws of clients) if (ws.readyState === WebSocket.OPEN) ws.send(payload);
        res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({ delivered: clients.size, sequence }));
      });
      return;
    }
    if (req.method !== 'GET' && req.method !== 'HEAD') return res.writeHead(405).end();
    if (url.pathname.startsWith('/_airslide/')) {
      const asset = url.pathname.slice('/_airslide/'.length);
      if (!ASSETS.has(asset)) return res.writeHead(404).end();
      // three.js and the AirPod models are about 2.5 MB, so viewers may keep them for a day.
      return serve(req, res, path.join(publicDir, asset), { cache: /^(vendor|models)\//.test(asset) ? 'public, max-age=86400' : 'no-store' });
    }
    const file = deckFile(url.pathname);
    if (!file) return res.writeHead(404).end();
    serve(req, res, file, { inject: path.extname(file).toLowerCase() === '.html' });
  }
  const server = http.createServer((req, res) => {
    try { handle(req, res); } catch (error) {
      console.error(`AirSlide relay: ${req.method} request failed: ${error.message}`);
      if (res.headersSent) res.destroy(); else res.writeHead(500).end();
    }
  });
  const wss = new WebSocketServer({ noServer: true, maxPayload: 1024 });
  server.on('upgrade', (req, socket, head) => {
    if (req.url !== '/_airslide/ws' || clients.size >= maxViewers) return socket.destroy();
    wss.handleUpgrade(req, socket, head, ws => {
      ws.isAlive = true; ws.on('pong', () => { ws.isAlive = true; }); clients.add(ws); ws.send(JSON.stringify({ ready: true }));
      ws.on('error', () => {});
      ws.on('close', () => { clients.delete(ws); });
    });
  });
  const heartbeat = setInterval(() => { for (const ws of clients) { if (!ws.isAlive) { ws.terminate(); clients.delete(ws); } else { ws.isAlive = false; ws.ping(); } } }, 20000);
  heartbeat.unref();
  server.on('close', () => { clearInterval(heartbeat); for (const ws of wss.clients) ws.terminate(); wss.close(); });
  return server;
}

if (require.main === module) {
  const host = process.env.HOST || '127.0.0.1', port = Number(process.env.PORT) || 8094;
  const deckDir = process.env.DECK_DIR ? path.resolve(process.env.DECK_DIR) : undefined;
  createRelay({ token: process.env.REMOTE_TOKEN, deckDir }).listen(port, host, () => console.log(`AirSlide relay serving ${deckDir || 'example-deck'} on http://${host}:${port}`));
}
module.exports = { createRelay };
