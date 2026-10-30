# Presensi Guru & Tenaga Kependidikan

Aplikasi presensi wajah + lokasi untuk SMP Negeri 1 Bandar Lampung. Backend: Supabase (PostgreSQL, Auth, Storage). Hosting: Cloudflare Workers & Pages (situs statis, tanpa proses build).

## Struktur

```text
presensi-gtk/
├── index.html                  # seluruh aplikasi (HTML, CSS, JavaScript)
├── manifest.webmanifest        # PWA: nama, warna, ikon aplikasi
├── sw.js                       # service worker (hanya menyimpan kerangka aplikasi)
├── icons/                      # ikon aplikasi presensi (192, 512, maskable, iOS)
├── _headers                    # header keamanan dasar + PWA untuk Cloudflare
├── .gitignore
├── README.md
└── supabase/
    └── Supabase_Setup.sql      # skema database, fungsi, RLS, bucket storage
```

## Pembaruan versi ini

- Pendaftaran wajah lebih ringkas: satu kali rekam (5 frame baik, sekitar 2 detik) dan satu kali ketuk, tidak lagi 3 putaran dengan pemeriksaan antar-putaran. Batas waktu 15 detik, dengan petunjuk langsung di layar jika posisi atau cahaya kurang. Wajah yang sudah terdaftar tidak berubah.
- GPS lebih andal di iPhone: lokasi cepat dari Wi-Fi/seluler diambil lebih dulu, lalu dipantau dengan akurasi tinggi. Jika 12 detik belum ada lokasi, otomatis dicoba ulang dengan mode hemat. Pesan error kini spesifik (izin ditolak, sinyal belum ada, akurasi rendah) dengan langkah perbaikannya. Tersedia tombol Ulangi, dan lokasi dimuat ulang otomatis saat pengguna kembali ke aplikasi (misalnya setelah mengubah izin di Pengaturan).
- Akurasi GPS ditampilkan di chip jarak bila di atas 100 m. Aturan jarak ke sekolah tidak berubah.
- `sw.js` naik ke `gtk-shell-v4`. `Supabase_Setup.sql` tidak berubah.

## Konfigurasi

Buka `index.html`, cari blok `KONFIGURASI APLIKASI`:

| Konstanta | Isi |
|---|---|
| `IS_PREVIEW` | `false` untuk produksi |
| `SUPABASE_URL` | Project Settings > API > Project URL |
| `SUPABASE_ANON_KEY` | Publishable / anon key (aman di browser; jangan pernah pakai `service_role`) |
| `ADMIN_EMAIL` | Email akun admin di Supabase Authentication |

Karena situs ini statis tanpa build, nilai tersebut diisi langsung di `index.html`, bukan lewat Environment Variables Vercel.

## Pemasangan Supabase (sekali saja)

1. Buat proyek di Supabase.
2. SQL Editor: jalankan seluruh isi `supabase/Supabase_Setup.sql`.
3. Authentication > Users: buat akun admin dengan email yang sama seperti `ADMIN_EMAIL`.
4. Isi `SUPABASE_URL` dan `SUPABASE_ANON_KEY` di `index.html`.

## Deploy ke Cloudflare (Workers & Pages)

1. Unggah ke GitHub (`git add . && git commit -m "Tombol Kembali & layar penuh" && git push`).
2. Cloudflare Pages: Framework preset **None**, Build command kosong, Build output directory `/` (root).
   Cloudflare Workers (static assets): arahkan direktori aset ke root proyek ini.
3. Pembaruan berikutnya: `git push`, Cloudflare otomatis deploy ulang.
4. Setelah deploy, buka aplikasi di HP, hapus aplikasi terpasang lama bila tampilan belum berubah, lalu pasang ulang.

Kamera dan GPS hanya berfungsi lewat HTTPS (domain Cloudflare sudah HTTPS).

## Pengujian setelah deploy

- Buka menu Presensi di HP: kamera menyala sendiri, izinkan akses kamera dan lokasi.
- Pindah menu, lalu kembali: kamera mati di menu lain dan menyala lagi di Presensi.
- Pasang ke layar utama, buka dari ikon (layar penuh), pindah beberapa menu, lalu tekan Kembali HP: kembali ke menu sebelumnya, bukan keluar aplikasi. Di Beranda, tekan Kembali dua kali untuk keluar.
- Di iPhone (layar penuh), pastikan header dan navigasi bawah tidak tertutup notch atau bilah bawah.
- Daftarkan wajah (pegawai baru), lalu lakukan presensi masuk dan pulang.

## Catatan PWA

- Presensi tetap membutuhkan internet. Service worker hanya menyimpan halaman, manifest, dan ikon; data presensi, wajah, login, dan permintaan ke Supabase tidak disimpan.
- Setelah memperbarui `index.html`, ubah `VER` di `sw.js` (mis. `gtk-shell-v2`) agar cache perangkat lama diganti. Halaman tetap diambil dari jaringan lebih dulu.
- Ajakan instal hanya muncul lewat HTTPS dan di browser yang mendukung (Chrome/Edge Android). Jika sudah terpasang, banner tidak tampil.

## Catatan

- Ambang kecocokan wajah di database tetap 0,55 (jarak Euclidean). Pegawai yang wajahnya sudah terdaftar tidak perlu mendaftar ulang.
- Halaman diberi `noindex` agar tidak muncul di mesin pencari.
