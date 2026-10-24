(() => {
  const badge = document.createElement('div');
  badge.style.cssText = 'position:fixed;bottom:8px;right:12px;z-index:9999;font:11px system-ui;color:#aab;background:#12151bcc;padding:5px 9px;border-radius:8px;pointer-events:none';
  if (!(['127.0.0.1','localhost'].includes(location.hostname) && new URLSearchParams(location.search).has('airslide-preview'))) document.body.append(badge);
  let retry = 1000;
  function connect() {
    badge.textContent = 'Remote connecting…';
    const ws = new WebSocket(`${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}/_airslide/ws`);
    ws.onmessage = event => {
      let message; try { message = JSON.parse(event.data); } catch { return; }
      if (message.ready) { badge.textContent = 'Remote connected'; retry = 1000; return; }
      if (!['next', 'prev'].includes(message.direction)) return;
      window.dispatchEvent(new CustomEvent('airslide-gesture', { detail: message }));
      // A deck can take over navigation; otherwise press the arrow key most decks already handle.
      if (typeof window.airslideNavigate === 'function') return window.airslideNavigate(message.direction);
      const [key, code] = message.direction === 'next' ? ['ArrowRight', 39] : ['ArrowLeft', 37];
      const press = new KeyboardEvent('keydown', { key, code: key, bubbles: true, cancelable: true });
      for (const legacy of ['keyCode', 'which']) Object.defineProperty(press, legacy, { get: () => code });
      (document.activeElement || document.body).dispatchEvent(press);
    };
    ws.onclose = event => {
      badge.textContent = 'Remote disconnected — reconnecting…';
      setTimeout(connect, retry); retry = Math.min(10000, retry * 2);
    };
    ws.onerror = () => ws.close();
  }
  connect();
})();
