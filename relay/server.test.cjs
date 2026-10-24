const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { WebSocket } = require('ws');
const { createRelay } = require('./server.cjs');

const token = 'test-secret-'.repeat(4);
function deckFixture() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'airslide-deck-'));
  fs.writeFileSync(path.join(dir, 'index.html'), '<!doctype html><title>Deck</title><body><h1>One</h1></body>');
  fs.writeFileSync(path.join(dir, 'bare.html'), '<h1>No body tag</h1>');
  fs.writeFileSync(path.join(dir, 'upper.html'), '<BODY>İstanbul</BODY >');
  fs.writeFileSync(path.join(dir, 'deck.css'), 'h1{color:red}');
  fs.writeFileSync(path.join(dir, 'pixel.png'), Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x00, 0xff]));
  fs.writeFileSync(path.join(dir, 'notes.md'), '# private notes');
  fs.writeFileSync(path.join(dir, '.env'), 'REMOTE_TOKEN=never-served');
  fs.writeFileSync(path.join(dir, '.hidden.txt'), 'hidden');
  fs.symlinkSync(path.join(dir, '.hidden.txt'), path.join(dir, 'visible.txt'));
  fs.mkdirSync(path.join(dir, 'part'));
  fs.writeFileSync(path.join(dir, 'part', 'index.html'), '<body>Part</body>');
  const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'airslide-outside-'));
  fs.writeFileSync(path.join(outside, 'secret.html'), 'outside');
  fs.symlinkSync(path.join(outside, 'secret.html'), path.join(dir, 'escape.html'));
  return dir;
}
async function start(options = {}) {
  const deckDir = deckFixture();
  const server = createRelay({ token, deckDir, ...options });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  return { server, deckDir, base: `http://127.0.0.1:${server.address().port}` };
}
const socket = base => new WebSocket(base.replace('http:', 'ws:') + '/_airslide/ws');
// Read every body: an unread streamed file keeps its connection busy and server.close() waiting.
const statusOf = async (url, init) => { const response = await fetch(url, init); await response.arrayBuffer(); return response.status; };
const stop = server => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); });
// fetch() normalises URLs, so send the raw request line to reach the server's own parser.
const rawStatus = (base, requestPath) => new Promise((resolve, reject) => {
  const { hostname, port } = new URL(base);
  http.get({ hostname, port, path: requestPath }, response => { response.resume(); resolve(response.statusCode); }).on('error', reject);
});

test('rejects a short key', () => {
  assert.throws(() => createRelay({ token: 'short' }), /at least 32 characters/);
});

test('authenticated delivery, duplicate suppression, validation and broadcast', async () => {
  const { server, base } = await start();
  const ws = socket(base);
  let second;
  try {
    const ready = once(ws, 'message');
    await once(ws, 'open');
    assert.equal(JSON.parse((await ready)[0]).ready, true);
    const post = (body, authorization = `Bearer ${token}`) => fetch(base + '/api/command', { method: 'POST', headers: { Authorization: authorization }, body: JSON.stringify(body) });
    assert.equal((await post({ id: 'a', direction: 'next' }, 'Bearer wrong')).status, 401);
    assert.equal((await post({ id: 'a', direction: 'next' }, token)).status, 401, 'The Bearer prefix is required');
    assert.equal((await post({ id: 'a', direction: 'delete' })).status, 400);
    assert.equal((await post(null)).status, 400);
    assert.equal((await post({ id: 'bad-side', direction: 'next', side: 'both' })).status, 400);
    const received = once(ws, 'message');
    const response = await post({ id: 'a', direction: 'next', side: 'right' });
    assert.equal((await response.json()).delivered, 1);
    assert.deepEqual(JSON.parse((await received)[0]), { direction: 'next', sequence: 1, side: 'right' });
    assert.equal((await (await post({ id: 'a', direction: 'next' })).json()).duplicate, true);
    assert.equal((await post({ id: 'b', direction: 'prev' })).status, 429);
    second = socket(base);
    await once(second, 'message');
    await new Promise(resolve => setTimeout(resolve, 300));
    const firstMessage = once(ws, 'message'), secondMessage = once(second, 'message');
    const broadcast = await post({ id: 'c', direction: 'prev', side: 'left' });
    assert.equal((await broadcast.json()).delivered, 2);
    assert.equal(JSON.parse((await firstMessage)[0]).direction, 'prev');
    assert.deepEqual(JSON.parse((await secondMessage)[0]), { direction: 'prev', sequence: 2, side: 'left' });
  } finally { second?.terminate(); ws.terminate(); await stop(server); }
});

test('serves the deck with the remote injected and nothing outside it', async () => {
  const { server, base } = await start();
  try {
    const page = await (await fetch(base)).text();
    assert.match(page, /<h1>One<\/h1><script src="\/_airslide\/client.js"><\/script><script type="module" src="\/_airslide\/gesture.js"><\/script><\/body>/);
    assert.match(await (await fetch(base + '/bare.html')).text(), /No body tag<\/h1><script src="\/_airslide\/client.js">/);
    assert.match(await (await fetch(base + '/upper.html')).text(), /İstanbul<script src="\/_airslide\/client.js">.*<\/BODY >$/);
    assert.match(await (await fetch(base + '/part/')).text(), /Part<script src="\/_airslide\/client.js">/);
    const css = await fetch(base + '/deck.css');
    assert.equal(css.status, 200);
    assert.match(css.headers.get('content-type'), /text\/css/);
    assert.equal(await css.text(), 'h1{color:red}');
    const png = await fetch(base + '/pixel.png');
    assert.equal(png.headers.get('content-type'), 'image/png');
    assert.deepEqual([...new Uint8Array(await png.arrayBuffer())], [0x89, 0x50, 0x4e, 0x47, 0x00, 0xff]);
    for (const hidden of ['/.env', '/notes.md', '/escape.html', '/visible.txt', '/..%2Fserver.cjs', '/%2e%2e/server.cjs', '/part/..%2F.env', '/missing.html', '/_airslide/server.cjs', '/_airslide/../server.cjs']) {
      assert.equal(await statusOf(base + hidden), 404, hidden);
    }
    for (const asset of ['client.js', 'gesture.js', 'preview.html', 'models/left.json', 'vendor/three.module.min.js']) {
      assert.equal(await statusOf(base + '/_airslide/' + asset), 200, asset);
    }
    const model = await fetch(base + '/_airslide/models/right.json');
    await model.arrayBuffer();
    assert.match(model.headers.get('cache-control'), /max-age=86400/);
    assert.equal(await statusOf(base + '/', { method: 'DELETE' }), 405);
    assert.equal(await statusOf(base + '/healthz'), 200);
  } finally { await stop(server); }
});

test('byte ranges for media', async () => {
  const { server, base } = await start();
  try {
    const part = await fetch(base + '/pixel.png', { headers: { Range: 'bytes=1-2' } });
    assert.equal(part.status, 206);
    assert.equal(part.headers.get('content-range'), 'bytes 1-2/6');
    assert.deepEqual([...new Uint8Array(await part.arrayBuffer())], [0x50, 0x4e]);
    const tail = await fetch(base + '/pixel.png', { headers: { Range: 'bytes=-2' } });
    assert.deepEqual([...new Uint8Array(await tail.arrayBuffer())], [0x00, 0xff]);
    assert.equal(await statusOf(base + '/pixel.png', { headers: { Range: 'bytes=9-' } }), 416);
  } finally { await stop(server); }
});

test('survives malformed and failing requests', async () => {
  const { server, base, deckDir } = await start();
  try {
    assert.equal(await rawStatus(base, '//a:99999/'), 400);
    if (process.getuid?.() !== 0) {
      fs.chmodSync(path.join(deckDir, 'index.html'), 0o000);
      assert.equal(await statusOf(base + '/'), 500);
    }
    assert.equal(await statusOf(base + '/healthz'), 200, 'The relay keeps serving after a failed request');
  } finally { await stop(server); }
});

test('websocket upgrades only on the relay path and up to the viewer limit', async () => {
  const { server, base } = await start({ maxViewers: 1 });
  const stray = new WebSocket(base.replace('http:', 'ws:') + '/remote');
  const first = socket(base);
  let extra;
  try {
    assert.ok((await once(stray, 'error'))[0]);
    await once(first, 'message');
    extra = socket(base);
    assert.ok((await once(extra, 'error'))[0], 'Viewers beyond the limit are refused');
  } finally { stray.terminate(); first.terminate(); extra?.terminate(); await stop(server); }
});
