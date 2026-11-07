# Undangan Pernikahan Rayana & Hasna

Website undangan dengan taman 3D realistis (Three.js): tamu diajak berjalan menyusuri taman bersama sebuah karakter, lalu kartu undangan muncul satu per satu saat halaman digulir. RSVP & ucapan tersimpan di **Supabase**, dan link personal untuk tiap tamu.

```
web/
  index.html        ← halaman undangan
  config.js         ← isi URL & key Supabase di sini
  tamu.html         ← pembuat link tamu + pesan WhatsApp (untuk mempelai)
  assets/           ← taruh foto & musik di sini (opsional)
  assets/3d/        ← model 3D (kupu-kupu, sofa, lentera, vas, pot), langit & tekstur taman, jangan dihapus
supabase/
  schema.sql        ← tabel, keamanan, dan contoh tamu
```

## 1. Siapkan Supabase (±5 menit)
1. Buat project gratis di https://supabase.com.
2. Buka **SQL Editor → New query**, tempel isi `supabase/schema.sql`, lalu klik **Run**.
   Ini membuat tabel `guests` dan `rsvp`, mengaktifkan keamanan (RLS), saringan spam, realtime, dan mengisi tamu contoh: Nova, B&B, OISHI.
   File ini aman dijalankan ulang kalau nanti ada pembaruan; data yang sudah masuk tidak terhapus.
3. Buka **Project Settings → API**, salin **Project URL** dan **anon public key**.
4. Tempel keduanya ke `web/config.js`:
   ```js
   window.WEDDING_CONFIG = {
     supabaseUrl: 'https://xxxx.supabase.co',
     supabaseAnonKey: 'eyJhbGciOi...',
     eventISO: '2026-12-26T09:00:00+07:00'
   };
   ```
   Anon key memang aman ditaruh di website publik. Isi database dijaga oleh aturan RLS di `schema.sql`: tamu hanya bisa menambah ucapan dan membacanya, tidak bisa mengubah atau menghapus, dan tidak bisa melihat daftar tamu lain.

## 2. Deploy
Kode situs ada di `web/`, sedangkan `package.json`, `vite.config.mjs`, dan `vercel.json` ada di root. `npm run build` menghasilkan folder `dist/` (halaman, bundle three.js, dan seluruh isi `web/assets` + `config.js`).

```bash
npm install
npm run dev      # lokal, buka alamat yang muncul
npm run build    # hasil di dist/
npm run preview  # cek hasil build
```

**ArenHost / hosting cPanel:** situs ini statis, jadi tidak butuh PHP atau MySQL di hosting.
1. Isi `web/config.js` (langkah 1.4), lalu jalankan `npm run build`.
2. Buka cPanel → **File Manager** → `public_html` (atau folder domain/subdomain-mu).
3. Upload **isi** folder `dist/` (bukan folder `dist`-nya), yaitu `index.html`, `tamu.html`, `config.js`, `bundle/`, `assets/`. Cara cepat: kompres isi `dist/` jadi zip, upload, lalu klik **Extract**.
4. Buka domainmu. Kalau tulisan di bawah buku tamu masih "Mode pratinjau", berarti `config.js` belum terisi.

Setiap kali mengubah sesuatu, ulangi `npm run build` lalu upload ulang file yang berubah.

**Vercel (dari GitHub):** Import repo dengan Root Directory `./` (root repo, bukan `web`). Pengaturan build sudah ditulis di `vercel.json` (Install `npm ci`, Build `npm run build`, Output `dist`), jadi biarkan kolom override kosong.

Supabase bisa diisi di `web/config.js`, atau lewat Environment Variables Vercel `VITE_SUPABASE_URL` dan `VITE_SUPABASE_ANON_KEY` (lihat `.env.example`). Kalau keduanya diisi, nilai env yang dipakai. Hanya anon key yang boleh dipakai, jangan service_role key.

## 3. Link untuk tamu
Format link: `https://domainmu/?to=nova`. Nama tamu muncul di sampul ("Kepada Yth. Nova") dan otomatis terisi di formulir RSVP.

- Buka `https://domainmu/tamu.html`, tulis nama tamu satu per baris, lalu salin link atau kirim langsung lewat WhatsApp.
- Halaman itu juga membuat **SQL** untuk menambah tamu ke Supabase, supaya ejaan nama seperti `B&B` atau `OISHI` tampil persis.
- Kalau slug tidak ada di database, nama diambil dari link itu sendiri (`?to=budi-santoso` menjadi "Budi Santoso").

## 4. Ganti foto & musik (opsional)
Taruh file dengan nama berikut di `web/assets/`. Halaman memakainya otomatis; selama filenya belum ada, yang tampil ilustrasi:

| File | Dipakai untuk |
|---|---|
| `mempelai-pria.jpg`, `mempelai-wanita.jpg` | Foto profil mempelai (rasio 4:5) |
| `galeri-1.jpg` … `galeri-16.jpg` | Galeri prewedding (foto 1–4 juga tampil di easel taman 3D) |
| `foto-berdua.jpg` | Potret berdua, **posisi portrait** (rasio 3:4 atau 4:5). Tampil di dinding potret taman 3D dan di bagian "Potret" |
| `pasangan.png` | Foto full-body berdua dengan **latar transparan** (PNG). Berdiri di pelaminan taman 3D. Tanpa file ini pelaminan tampil kosong |
| `musik.mp3` | Musik latar. Tombol musik hanya muncul kalau file ini ada |

Teks (nama mempelai & orang tua, alamat, rekening, tanggal) bisa diedit langsung di `index.html`. Nama di papan gerbang, buku tamu, dan neon photo booth juga ada di sana: cari "Rayana" lalu ganti semuanya.

## 5. Melihat RSVP & moderasi ucapan
Supabase → **Table Editor → rsvp**. Bisa diekspor ke CSV. Rekap cepat lewat SQL Editor (termasuk yang disembunyikan):
```sql
select hadir, count(*) as ucapan, sum(jumlah) as orang from public.rsvp group by hadir;
```

**Menyembunyikan ucapan aneh:** di Table Editor → `rsvp`, hilangkan centang kolom **`tampil`** di baris itu, lalu simpan. Ucapan hilang dari website saat halaman dibuka ulang, tapi datanya tetap ada dan bisa dicentang lagi kapan saja. Hapus barisnya hanya kalau benar-benar tidak perlu.

**Saringan otomatis** (sudah aktif lewat `schema.sql`):
- ucapan atau nama yang berisi link/alamat website ditolak,
- ucapan yang sama persis dari nama yang sama tidak bisa dikirim dua kali,
- maks. 10 kiriman per jaringan per 10 menit, dan 30 kiriman per menit untuk seluruh website,
- kolom tersembunyi di formulir menjebak bot,
- jumlah tamu dibatasi maks. 2, dan waktu kirim tidak bisa dipalsukan.

**Mode persetujuan** (opsional): ucapan baru tidak tampil sampai kamu centang `tampil`. Jalankan di SQL Editor:
```sql
update public.pengaturan set langsung_tampil = false;  -- kembali: = true
```

## 6. Supaya Supabase tidak "tertidur"
Project Supabase gratis dijeda kalau tidak ada aktivitas sekitar 7 hari. Datanya aman, tapi selama dijeda buku tamu tidak bisa dipakai.
- Sebelum undangan disebar, **buka website undangan tiap 4–5 hari** sampai bagian buku tamu termuat. Itu sudah dihitung sebagai aktivitas. Pasang pengingat di HP.
- Setelah undangan disebar, kunjungan tamu sudah menjaganya tetap aktif.
- Kalau sempat dijeda: login ke Supabase, buka project-nya, klik **Restore**, tunggu beberapa menit.

## Kredit aset 3D
- Kupu-kupu: "Butterfly" oleh assetfactory, https://sketchfab.com/3d-models/butterfly-87ef5cea7e2f4557a28503f5b96646cd (lisensi Sketchfab Standard).
- Langit: "Kloofendal 48d Partly Cloudy (Pure Sky)" dari Poly Haven (CC0), diputar agar matahari menyamping.
- Tekstur marmer/travertine, kulit kayu platanus, dan plester dari Poly Haven (CC0).
- Daun pohon & pagar: foto daun ambientCG LeafSet024 dan LeafSet014 (CC0), dirangkai menjadi tekstur gerombol.
- Rumput: foto helai rumput ambientCG Foliage001 dan Foliage007 (CC0), dirangkai menjadi rumpun.
- Sofa pelaminan (Sofa_01), lentera kuningan (Lantern_01), vas keramik (ceramic_vase_01), pot terakota (planter_pot_clay): model scan Poly Haven (CC0).
- Kayu oak (kursi, easel, panggung), kain linen (taplak), dan batu kolam: tekstur Poly Haven oak_veneer_01, rough_linen, rock_boulder_dry (CC0).
- Tekstur rumput, kayu, air dari contoh three.js (MIT).
