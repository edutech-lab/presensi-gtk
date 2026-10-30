/* Service worker Presensi GTK.
   Hanya menyimpan "kerangka" aplikasi (halaman, manifest, ikon) agar cepat terbuka.
   Model pengenalan wajah (file publik face-api di jsDelivr) juga disimpan agar tidak diunduh ulang.
   Data presensi, wajah, login, dan permintaan ke Supabase TIDAK disimpan dan tidak disentuh. */
const VER = 'gtk-shell-v4';
const FACE = 'gtk-face-v1';
const FACE_RE = /^https:\/\/cdn\.jsdelivr\.net\/npm\/@vladmandic\/face-api@/;
const SHELL = ['./', 'manifest.webmanifest', 'icons/icon-192.png', 'icons/icon-512.png', 'icons/maskable-512.png', 'icons/apple-touch-icon.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VER).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(ks => Promise.all(ks.filter(k => k !== VER && k !== FACE).map(k => caches.delete(k)))).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const r = e.request, u = new URL(r.url);
  if (r.method === 'GET' && FACE_RE.test(r.url)) {                       // skrip & model wajah: cache dulu
    e.respondWith(caches.open(FACE).then(c => c.match(r).then(hit => hit || fetch(r).then(res => { if (res && (res.ok || res.type === 'opaque')) c.put(r, res.clone()); return res; }))));
    return;
  }
  if (r.method !== 'GET' || u.origin !== self.location.origin) return;   // lintas-origin (Supabase, CDN) dibiarkan langsung ke jaringan
  if (r.mode === 'navigate') {                                           // halaman: jaringan dulu, cadangan dari cache
    e.respondWith(
      fetch(r).then(res => { const cp = res.clone(); caches.open(VER).then(c => c.put('./', cp)); return res; })
        .catch(() => caches.match('./'))
    );
    return;
  }
  if (/\/(icons\/|manifest\.webmanifest$)/.test(u.pathname)) {           // ikon & manifest: cache dulu
    e.respondWith(caches.match(r).then(hit => hit || fetch(r).then(res => { const cp = res.clone(); caches.open(VER).then(c => c.put(r, cp)); return res; })));
  }
});
