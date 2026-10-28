# Presensi Guru & Tenaga Kependidikan

Aplikasi presensi wajah + lokasi untuk SMP Negeri 1 Bandar Lampung. Backend: Supabase (PostgreSQL, Auth, Storage). Hosting: Vercel (situs statis, tanpa proses build).

## Struktur

```text
presensi-gtk/
├── index.html                  # seluruh aplikasi (HTML, CSS, JavaScript)
├── manifest.webmanifest        # PWA: nama, warna, ikon aplikasi
├── sw.js                       # service worker (hanya menyimpan kerangka aplikasi)
├── icons/                      # ikon aplikasi presensi (192, 512, maskable, iOS)
├── vercel.json                 # konfigurasi Vercel (header keamanan dasar + PWA)
├── .gitignore
├── README.md
└── supabase/
    └── Supabase_Setup.sql      # skema database, fungsi, RLS, bucket storage
```

## Pembaruan versi ini

- Pemindaian lebih cepat: model wajah dimuat di latar belakang setelah login dan dipanaskan, deteksi memakai ukuran input lebih kecil, sidik wajah disiapkan selama wajah terlihat sehingga tombol Presensi langsung diproses, dan hasil presensi langsung diumumkan tanpa menunggu penyegaran status.
- Kamera aktif otomatis saat menu Presensi dibuka (tombol Aktifkan Kamera dihapus) dan mati otomatis saat pindah menu, keluar aplikasi, atau tab disembunyikan.
- Tombol Kembali pada HP/tablet membuka menu sebelumnya. Jika modal atau menu samping terbuka, Kembali menutupnya terlebih dahulu. Di Beranda, Kembali meminta konfirmasi sekali sebelum keluar.
- Pemindaian wajah lebih akurat: panduan posisi langsung (cahaya, jarak, posisi tengah, wajah lurus), hanya frame berkualitas baik yang dipindai, beberapa frame dirata-ratakan, dan frame yang menyimpang dibuang.
- Tampilan kamera lebih profesional: bingkai oval, garis pemindai, dan status langsung.
- PWA: aplikasi bisa dipasang di HP. Android/Chrome menampilkan banner "Pasang Aplikasi" di dalam aplikasi; iPhone menampilkan petunjuk "Tambah ke Layar Utama" (iOS tidak mendukung ajakan instal otomatis). Banner yang ditutup tidak muncul lagi selama 7 hari.
- Ikon aplikasi bertema presensi (pemindai wajah + centang), bukan logo sekolah.
- File `Supabase_Setup.sql` tidak berubah. Tidak perlu dijalankan ulang jika database sudah dipasang.

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

## Unggah ke GitHub

```bash
git init
git add .
git commit -m "Presensi GTK: kamera otomatis, tombol kembali, pemindaian wajah akurat"
git branch -M main
git remote add origin https://github.com/<username>/<repositori>.git
git push -u origin main
```

## Import ke Vercel

1. vercel.com > Add New > Project > pilih repositori GitHub.
2. Framework Preset: **Other**.
3. Build Command: kosongkan. Output Directory: kosongkan (root). Install Command: kosongkan.
4. Klik Deploy.
5. Pembaruan berikutnya: `git push` ke `main`, Vercel otomatis deploy ulang.

Kamera dan GPS hanya berfungsi lewat HTTPS. Domain `*.vercel.app` sudah HTTPS.

## Pengujian setelah deploy

- Buka menu Presensi di HP: kamera menyala sendiri, izinkan akses kamera dan lokasi.
- Pindah menu, lalu kembali: kamera mati di menu lain dan menyala lagi di Presensi.
- Tekan tombol Kembali HP: berpindah ke menu sebelumnya.
- Daftarkan wajah (pegawai baru), lalu lakukan presensi masuk dan pulang.

## Catatan PWA

- Presensi tetap membutuhkan internet. Service worker menyimpan halaman, manifest, ikon, dan berkas model pengenalan wajah (berkas publik, bukan data pegawai); data presensi, wajah, login, dan permintaan ke Supabase tidak disimpan.
- Setelah memperbarui `index.html`, ubah `VER` di `sw.js` (mis. `gtk-shell-v2`) agar cache perangkat lama diganti. Halaman tetap diambil dari jaringan lebih dulu.
- Ajakan instal hanya muncul lewat HTTPS dan di browser yang mendukung (Chrome/Edge Android). Jika sudah terpasang, banner tidak tampil.

## Catatan

- Ambang kecocokan wajah di database tetap 0,55 (jarak Euclidean). Pegawai yang wajahnya sudah terdaftar tidak perlu mendaftar ulang.
- Halaman diberi `noindex` agar tidak muncul di mesin pencari.
