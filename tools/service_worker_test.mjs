import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const handlers = {};
const stores = new Map();
const network = [];
const source = (await readFile(new URL('../web/splitrip_service_worker.js', import.meta.url), 'utf8'))
  .replace('__SPLITRIP_VERSION__', 'test-build')
  .replace('__SPLITRIP_FILES__', JSON.stringify(['index.html', 'main.dart.js', 'assets/FontManifest.json']));
const cacheApi = {
  async open(name) {
    if (!stores.has(name)) stores.set(name, new Map());
    const store = stores.get(name);
    const key = request => typeof request === 'string' ? request : request.url;
    return {
      async addAll(requests) { for (const request of requests) store.set(key(request), new Response(`cached:${key(request)}`)); },
      async match(request) { return store.get(key(request))?.clone(); },
      async put(request, response) { store.set(key(request), response); },
    };
  },
  async keys() { return [...stores.keys()]; },
  async delete(name) { return stores.delete(name); },
};
let skippedWaiting = false;
vm.runInNewContext(source, {
  URL, Request, Response, caches: cacheApi,
  fetch: async request => { network.push(request.url); return new Response('network'); },
  self: {
    location: 'https://example.test/app/splitrip_service_worker.js',
    registration: { active: { scriptURL: 'https://example.test/app/splitrip_service_worker.js' } },
    skipWaiting: async () => { skippedWaiting = true; },
    clients: { claim: async () => {} },
    addEventListener: (type, handler) => { handlers[type] = handler; },
  },
});
async function lifecycle(type) {
  let promise;
  handlers[type]({ waitUntil: value => { promise = value; } });
  await promise;
}
async function request(url, mode = 'cors', method = 'GET') {
  let promise;
  handlers.fetch({ request: { url, mode, method }, respondWith: value => { promise = value; } });
  return promise ? (await promise).text() : undefined;
}
await cacheApi.open('splitrip-shell-old');
await cacheApi.open('unrelated-app');
await lifecycle('install');
assert.equal(skippedWaiting, false, 'updates wait for open clients to close');
await lifecycle('activate');
assert.equal(stores.has('splitrip-shell-old'), false);
assert.equal(stores.has('unrelated-app'), true);
assert.match(await request('https://example.test/app/join/ABCD2345', 'navigate'), /index.html/);
assert.match(await request('https://example.test/app/main.dart.js?v=2'), /main.dart.js/);
assert.match(await request('https://example.test/app/assets/FontManifest.json'), /FontManifest/);
assert.equal(await request('https://firestore.googleapis.com/listen'), undefined);
assert.equal(await request('https://identitytoolkit.googleapis.com/signIn'), undefined);
assert.equal(await request('https://example.test/app/main.dart.js', 'cors', 'POST'), undefined);
const sdk = 'https://www.gstatic.com/firebasejs/1.2.3/firebase-app.js';
assert.equal(await request(sdk), 'network');
assert.equal(await request(sdk), 'network');
assert.deepEqual(network, [sdk], 'SDK is reused offline; API responses never enter the cache');
const renderer = 'https://www.gstatic.com/flutter-canvaskit/abc123/canvaskit.wasm';
assert.equal(await request(renderer), 'network');
assert.equal(await request(renderer), 'network');
assert.equal(network.filter(url => url === renderer).length, 1, 'CDN renderer is fetched once, then served offline');
// A missing shell entry (partial eviction) falls back to the network.
stores.get('splitrip-shell-test-build').delete('https://example.test/app/main.dart.js');
assert.equal(await request('https://example.test/app/main.dart.js'), 'network');
stores.get('splitrip-shell-test-build').delete('https://example.test/app/index.html');
assert.equal(await request('https://example.test/app/', 'navigate'), 'network');
console.log('Service worker install, update isolation, offline routes/assets and SDK caching passed.');
