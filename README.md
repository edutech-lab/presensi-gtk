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

- Setelah presensi masuk/pulang berhasil, foto wajah yang diambil kamera saat presensi ditampilkan selama 5 detik di area kamera (hanya foto, tanpa teks). Bingkai dan bar hitung mundur berwarna sesuai status: hijau = Tepat Waktu, kuning = Toleransi, merah = Terlambat / Pulang Lebih Awal. Ketuk foto untuk menutup lebih cepat. Foto yang ditampilkan sama dengan yang disimpan ke rekap. Tidak ada perubahan SQL.
- Toleransi terlambat: presensi masuk setelah jam masuk sampai batas toleransi berstatus **Toleransi** (bukan Tepat Waktu) dan tidak dihitung terlambat (bawaan 10 menit; contoh jam masuk 07.00: 07.05 dan 07.10 = Toleransi, 07.11 = Terlambat). Diatur admin di Pengaturan > Jam Kerja & Hari Kerja > Toleransi terlambat (menit), rentang 0 - 60, isi 0 untuk tanpa toleransi. Berlaku juga pada koreksi presensi oleh admin. Menit terlambat 0 untuk status Toleransi; untuk Terlambat dihitung dari jam masuk. Pada dashboard dan rekap, status Toleransi masuk hitungan Tepat Waktu (tidak terlambat). Dashboard tidak menampilkan info toleransi. Data presensi yang sudah tersimpan tidak diubah.
- **Wajib:** jalankan ulang seluruh `supabase/Supabase_Setup.sql` di Supabase SQL Editor (aman diulang, data tidak hilang). Tanpa itu, server belum menerapkan toleransi.
- `sw.js` naik ke `gtk-shell-v10`.

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
