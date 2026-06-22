#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const args = new Map();
for (let i = 2; i < process.argv.length; i += 1) {
  const arg = process.argv[i];
  if (arg.startsWith('--')) {
    args.set(arg.slice(2), process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[++i] : '1');
  }
}

const port = Number(args.get('port') || 17862);
const debugPort = Number(args.get('debug-port') || 17863);
const profileDir = args.get('profile') || path.join(os.homedir(), 'AppData', 'Local', 'LLGHD', 'LocalAIRender', 'PinterestChrome');
const chromePath = findChrome();
const workerVersion = '0.4.7-worker-navigation-wait';

function json(res, code, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': '*'
  });
  res.end(body);
}

function html(res, code, body) {
  res.writeHead(code, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store'
  });
  res.end(body);
}

function findChrome() {
  const candidates = [
    process.env.CHROME_PATH,
    path.join(process.env.PROGRAMFILES || '', 'Google', 'Chrome', 'Application', 'chrome.exe'),
    path.join(process.env['PROGRAMFILES(X86)'] || '', 'Google', 'Chrome', 'Application', 'chrome.exe'),
    path.join(process.env.LOCALAPPDATA || '', 'Google', 'Chrome', 'Application', 'chrome.exe'),
    path.join(process.env.PROGRAMFILES || '', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
    path.join(process.env['PROGRAMFILES(X86)'] || '', 'Microsoft', 'Edge', 'Application', 'msedge.exe')
  ].filter(Boolean);
  return candidates.find((candidate) => fs.existsSync(candidate)) || 'chrome.exe';
}

async function fetchJson(url, options = {}) {
  const response = await fetch(url, options);
  if (!response.ok) throw new Error(`HTTP ${response.status} ${await response.text()}`);
  return response.json();
}

async function isChromeReady() {
  try {
    await fetchJson(`http://127.0.0.1:${debugPort}/json/version`);
    return true;
  } catch (_error) {
    return false;
  }
}

async function ensureChrome(url) {
  if (!(await isChromeReady())) {
    fs.mkdirSync(profileDir, { recursive: true });
    const chromeArgs = [
      `--remote-debugging-port=${debugPort}`,
      `--user-data-dir=${profileDir}`,
      '--no-first-run',
      '--disable-features=Translate',
      '--new-window',
      url || 'about:blank'
    ];
    const child = spawn(chromePath, chromeArgs, {
      detached: true,
      stdio: 'ignore',
      windowsHide: false
    });
    child.unref();
    const started = Date.now();
    while (Date.now() - started < 15000) {
      if (await isChromeReady()) return true;
      await wait(350);
    }
    throw new Error('Chrome remote debugging did not become ready.');
  }

  if (url) {
    await openPage(url);
  }
  return true;
}

async function openPage(url) {
  const encoded = encodeURIComponent(url);
  try {
    await fetchJson(`http://127.0.0.1:${debugPort}/json/new?${encoded}`, { method: 'PUT' });
  } catch (_error) {
    await fetchJson(`http://127.0.0.1:${debugPort}/json/new?${encoded}`);
  }
}

async function pageFor(_url) {
  await ensureChrome();
  let target;
  try {
    target = await fetchJson(`http://127.0.0.1:${debugPort}/json/new?about:blank`, { method: 'PUT' });
  } catch (_error) {
    target = await fetchJson(`http://127.0.0.1:${debugPort}/json/new?about:blank`);
  }
  if (!target.webSocketDebuggerUrl) throw new Error('Chrome did not expose a debugger websocket for the Pinterest page.');
  return new CdpSession(target.webSocketDebuggerUrl);
}

class CdpSession {
  constructor(url) {
    this.url = url;
    this.nextId = 1;
    this.pending = new Map();
  }

  async connect() {
    this.ws = new WebSocket(this.url);
    await new Promise((resolve, reject) => {
      this.ws.addEventListener('open', resolve, { once: true });
      this.ws.addEventListener('error', reject, { once: true });
    });
    this.ws.addEventListener('message', (event) => {
      let message;
      try {
        message = JSON.parse(event.data);
      } catch (_error) {
        return;
      }
      if (!message.id || !this.pending.has(message.id)) return;
      const { resolve, reject } = this.pending.get(message.id);
      this.pending.delete(message.id);
      if (message.error) reject(new Error(message.error.message || JSON.stringify(message.error)));
      else resolve(message.result || {});
    });
    return this;
  }

  send(method, params = {}) {
    const id = this.nextId++;
    this.ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      setTimeout(() => {
        if (!this.pending.has(id)) return;
        this.pending.delete(id);
        reject(new Error(`CDP timeout: ${method}`));
      }, 20000);
    });
  }

  close() {
    try {
      this.ws.close();
    } catch (_error) {
      // noop
    }
  }
}

async function pinterestSearch(query, count) {
  const searchUrl = `https://www.pinterest.com/search/pins/?q=${encodeURIComponent(query)}`;
  const session = await pageFor(searchUrl).then((page) => page.connect());
  try {
    await session.send('Page.enable');
    await session.send('Runtime.enable');
    await session.send('Page.navigate', { url: searchUrl });
    await waitForLocation(session, searchUrl, 20000);
    await waitForPinterestImages(session, 22000);
    for (let i = 0; i < 5; i += 1) {
      await session.send('Runtime.evaluate', {
        expression: 'window.scrollBy(0, Math.max(window.innerHeight * 1.4, 900));',
        returnByValue: true
      });
      await wait(1200);
    }
    await waitForPinterestImages(session, 8000);
    const expression = imageExtractionExpression(Math.max(count * 5, 30));
    const result = await session.send('Runtime.evaluate', {
      expression,
      returnByValue: true,
      awaitPromise: true
    });
    if (result.exceptionDetails) {
      throw new Error(`Pinterest extraction failed: ${exceptionText(result.exceptionDetails)}`);
    }
    const value = (result.result && result.result.value) || {};
    const urls = Array.isArray(value) ? value : (Array.isArray(value.urls) ? value.urls : []);
    return {
      ok: true,
      query,
      search_url: searchUrl,
      image_count: Number(value.image_count || value.imageCount || 0),
      pin_count: Number(value.pin_count || value.pinCount || urls.length || 0),
      urls: urls.slice(0, Math.max(count * 3, count))
    };
  } finally {
    session.close();
  }
}

function exceptionText(details) {
  if (!details) return 'unknown runtime exception';
  const description = details.exception && (details.exception.description || details.exception.value);
  return description || details.text || JSON.stringify(details).slice(0, 500);
}

async function waitForLocation(session, expectedUrl, maxMs) {
  const started = Date.now();
  while (Date.now() - started < maxMs) {
    const result = await session.send('Runtime.evaluate', {
      expression: `(() => ({ href: location.href, readyState: document.readyState, title: document.title }))()`,
      returnByValue: true,
      awaitPromise: true
    });
    const value = (result.result && result.result.value) || {};
    if (String(value.href || '').startsWith(expectedUrl.split('?')[0]) && value.readyState !== 'loading') {
      return value;
    }
    await wait(500);
  }
  return {};
}

async function waitForPinterestImages(session, maxMs) {
  const started = Date.now();
  let lastCount = 0;
  while (Date.now() - started < maxMs) {
    const result = await session.send('Runtime.evaluate', {
      expression: `(() => {
        const images = Array.from(document.images);
        const pins = images.filter((img) => {
          const rect = img.getBoundingClientRect();
          const url = [img.currentSrc, img.src, img.getAttribute('srcset')].filter(Boolean).join(' ');
          return url.includes('i.pinimg.com/') &&
            !url.includes('/60x60/') &&
            rect.width >= 120 &&
            rect.height >= 120 &&
            img.naturalWidth >= 120 &&
            img.naturalHeight >= 120;
        });
        return {
          readyState: document.readyState,
          title: document.title,
          bodyLength: document.body ? document.body.innerText.length : 0,
          imageCount: images.length,
          pinCount: pins.length
        };
      })()`,
      returnByValue: true,
      awaitPromise: true
    });
    const value = (result.result && result.result.value) || {};
    lastCount = Number(value.pinCount || 0);
    if (lastCount > 0) return value;
    await session.send('Runtime.evaluate', {
      expression: 'window.scrollBy(0, Math.max(window.innerHeight, 800));',
      returnByValue: true
    }).catch(() => {});
    await wait(1200);
  }
  return { pinCount: lastCount };
}

function imageExtractionExpression(limit) {
  return `(() => {
    const urls = new Set();
    const normalize = (rawValue) => {
      if (!rawValue || typeof rawValue !== 'string') return null;
      let url = rawValue.trim().split(' ')[0].trim();
      if (!url) return null;
      url = url.replace(/&amp;/g, '&');
      if (url.startsWith('//')) url = 'https:' + url;
      if (url.startsWith('i.pinimg.com')) url = 'https://' + url;
      if (!url.includes('i.pinimg.com/')) return null;
      url = url.split('?')[0];
      const lower = url.toLowerCase();
      if (!(lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp'))) return null;
      if (lower.includes('avatar') || lower.includes('rs=') || lower.includes('instagram-background') || lower.includes('originals/d5/3b/01')) return null;
      if (lower.includes('/60x60/')) return null;
      const parts = url.split('/');
      const normalized = parts.map((part) => {
        const lowerPart = part.toLowerCase();
        const fixedSizes = ['75x75', '136x136', '170x', '236x', '474x', '564x'];
        const numericSize = lowerPart.endsWith('x') && lowerPart.length > 1 && lowerPart.slice(0, -1).split('').every((char) => char >= '0' && char <= '9');
        return fixedSizes.includes(lowerPart) || numericSize ? '736x' : part;
      });
      return normalized.join('/');
    };
    const add = (value) => {
      if (!value || typeof value !== 'string') return;
      value.split(',').forEach((part) => {
        const url = normalize(part);
        if (url) urls.add(url);
      });
    };
    document.querySelectorAll('img').forEach((img) => {
      const rect = img.getBoundingClientRect();
      const looksLikePin = rect.width >= 120 && rect.height >= 120 && img.naturalWidth >= 120 && img.naturalHeight >= 120;
      const altLooksLikePin = (img.alt || '').includes('图片') || (img.alt || '').toLowerCase().includes('pin');
      if (!looksLikePin && !altLooksLikePin) return;
      add(img.currentSrc);
      add(img.src);
      add(img.getAttribute('src'));
      add(img.getAttribute('srcset'));
    });
    return {
      image_count: document.images.length,
      pin_count: urls.size,
      urls: Array.from(urls).slice(0, ${Number(limit) || 30})
    };
  })()`;
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://127.0.0.1:${port}`);
    if (url.pathname === '/status') {
      json(res, 200, {
        ok: true,
        worker_version: workerVersion,
        chrome_ready: await isChromeReady(),
        port,
        debug_port: debugPort,
        profile_dir: profileDir
      });
      return;
    }

    if (url.pathname === '/login') {
      await ensureChrome('https://www.pinterest.com/login/');
      html(res, 200, '<!doctype html><meta charset="utf-8"><title>Pinterest 登录</title><body style="font-family:Segoe UI,sans-serif;padding:24px">已打开 Pinterest 登录窗口。登录完成后回到 SketchUp 插件里重新验证。</body>');
      return;
    }

    if (url.pathname === '/search') {
      const query = url.searchParams.get('q') || 'modern interior design inspiration';
      const count = Math.max(1, Math.min(24, Number(url.searchParams.get('count') || 8)));
      const payload = await pinterestSearch(query, count);
      json(res, 200, payload);
      return;
    }

    json(res, 404, { ok: false, error: 'not found' });
  } catch (error) {
    json(res, 500, { ok: false, error: error.message, error_class: error.name });
  }
});

server.listen(port, '127.0.0.1');
