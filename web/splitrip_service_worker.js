// tools/build_web.mjs replaces these values after Flutter has built the app.
const VERSION = '__SPLITRIP_VERSION__';
const FILES = __SPLITRIP_FILES__;
const SHELL = `splitrip-shell-${VERSION}`;
const RUNTIME = 'splitrip-runtime-v1';
const root = new URL('./', self.location);
const urls = FILES.map(file => new URL(file, root).href);

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(SHELL);
    await cache.addAll(urls.map(url => new Request(url, { cache: 'reload' })));
    // Replace the SDK's old no-op worker, but let our own updates wait until
    // all existing tabs close: an open app must keep one coherent build.
    if (self.registration.active && !self.registration.active.scriptURL.includes('splitrip_service_worker.js')) {
      await self.skipWaiting();
    }
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    await Promise.all((await caches.keys())
      .filter(key => key.startsWith('splitrip-shell-') && key !== SHELL)
      .map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (request.mode === 'navigate' && url.origin === root.origin && url.pathname.startsWith(root.pathname)) {
    event.respondWith(caches.open(SHELL).then(cache => cache.match(new URL('index.html', root).href)).then(r => r || fetch(request)));
    return;
  }
  const canonical = new URL(url);
  canonical.search = '';
  if (urls.includes(canonical.href)) {
    event.respondWith(caches.open(SHELL).then(cache => cache.match(canonical.href)).then(r => r || fetch(request)));
    return;
  }
  // Only immutable, public SDK/renderer/font resources (versioned URLs). Never
  // cache auth or database requests; Firestore keeps its own offline cache.
  const publicRuntime = url.protocol === 'https:' && (
    (url.hostname === 'www.gstatic.com' && (url.pathname.startsWith('/firebasejs/') || url.pathname.startsWith('/flutter-canvaskit/'))) ||
    url.hostname === 'fonts.gstatic.com'
  );
  if (publicRuntime) {
    event.respondWith((async () => {
      const cache = await caches.open(RUNTIME);
      const cached = await cache.match(request);
      if (cached) return cached;
      const response = await fetch(request);
      if (response.ok) await cache.put(request, response.clone());
      return response;
    })());
  }
});
