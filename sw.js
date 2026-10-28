/* Service worker Presensi GTK.
   Hanya menyimpan "kerangka" aplikasi (halaman, manifest, ikon) agar cepat terbuka.
   Data presensi, wajah, login, dan semua permintaan ke Supabase TIDAK disimpan dan tidak disentuh.
   Pengecualian: berkas model pengenalan wajah (publik, ~7 MB) disimpan agar tidak diunduh ulang. */
const VER = 'gtk-shell-v2';
const FACE = 'gtk-face-v1';   // model pengenalan wajah (berkas publik, bukan data pegawai)
const FACE_URL = 'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@1.7.12/model/';
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
  if (r.method === 'GET' && r.url.startsWith(FACE_URL)) {                // model wajah: cache dulu agar pemuatan berikutnya instan
    e.respondWith(caches.open(FACE).then(c => c.match(r).then(hit => hit || fetch(r).then(res => { if (res.ok) c.put(r, res.clone()); return res; }))));
    return;
  }
  if (r.method !== 'GET' || u.origin !== self.location.origin) return;   // lintas-origin lain (Supabase, CDN) dibiarkan langsung ke jaringan
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
