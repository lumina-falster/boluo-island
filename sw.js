/* 菠萝岛助手 Service Worker：应用外壳缓存 + data.json 网络优先 */
const VER = 'boluo-v4.0.0';
const SHELL = ['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png', './pet.png'];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(VER).then(c => Promise.allSettled(SHELL.map(u => c.add(u))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(ks => Promise.all(ks.filter(k => k !== VER).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin) return;

  // data.json：网络优先，失败回退缓存（离线可看）
  if (url.pathname.endsWith('/data.json')) {
    e.respondWith(
      fetch(e.request).then(r => {
        const cp = r.clone();
        caches.open(VER).then(c => c.put(e.request, cp));
        return r;
      }).catch(() => caches.match(e.request))
    );
    return;
  }

  // 其余：缓存优先 + 后台更新
  e.respondWith(
    caches.match(e.request).then(hit => {
      const net = fetch(e.request).then(r => {
        if (r && r.ok) {
          const cp = r.clone();
          caches.open(VER).then(c => c.put(e.request, cp));
        }
        return r;
      }).catch(() => hit);
      return hit || net;
    })
  );
});
