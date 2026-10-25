# Undangan Pernikahan Raditya & Anindya

Website undangan dengan taman 3D realistis (Three.js): tamu diajak berjalan menyusuri taman bersama sebuah karakter, lalu kartu undangan muncul satu per satu saat halaman digulir. RSVP & ucapan tersimpan di **Supabase**, dan link personal untuk tiap tamu.

```
web/
  index.html        ← halaman undangan
  config.js         ← isi URL & key Supabase di sini
  tamu.html         ← pembuat link tamu + pesan WhatsApp (untuk mempelai)
  assets/           ← taruh foto, video, musik di sini (opsional)
  assets/3d/        ← model karakter (Xbot.glb), kupu-kupu (butterfly.glb) & tekstur taman, jangan dihapus
supabase/
  schema.sql        ← tabel, keamanan, dan contoh tamu
```

## 1. Siapkan Supabase (±5 menit)
1. Buat project gratis di https://supabase.com.
2. Buka **SQL Editor → New query**, tempel isi `supabase/schema.sql`, lalu klik **Run**.
   Ini membuat tabel `guests` dan `rsvp`, mengaktifkan keamanan (RLS), menyalakan realtime, dan mengisi tamu contoh: Nova, B&B, OISHI.
3. Buka **Project Settings → API**, salin **Project URL** dan **anon public key**.
4. Tempel keduanya ke `web/config.js`:
   ```js
   window.WEDDING_CONFIG = {
     supabaseUrl: 'https://xxxx.supabase.co',
     supabaseAnonKey: 'eyJhbGciOi...',
     eventISO: '2026-12-12T08:00:00+07:00'
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

**Vercel (dari GitHub):** Import repo dengan Root Directory `./` (root repo, bukan `web`). Pengaturan build sudah ditulis di `vercel.json` (Install `npm ci`, Build `npm run build`, Output `dist`), jadi biarkan kolom override kosong.

Supabase bisa diisi di `web/config.js`, atau lewat Environment Variables Vercel `VITE_SUPABASE_URL` dan `VITE_SUPABASE_ANON_KEY` (lihat `.env.example`). Kalau keduanya diisi, nilai env yang dipakai. Hanya anon key yang boleh dipakai, jangan service_role key.

## 3. Link untuk tamu
Format link: `https://domainmu/?to=nova`. Nama tamu muncul di sampul ("Kepada Yth. Nova") dan otomatis terisi di formulir RSVP.

- Buka `https://domainmu/tamu.html`, tulis nama tamu satu per baris, lalu salin link atau kirim langsung lewat WhatsApp.
- Halaman itu juga membuat **SQL** untuk menambah tamu ke Supabase, supaya ejaan nama seperti `B&B` atau `OISHI` tampil persis.
- Kalau slug tidak ada di database, nama diambil dari link itu sendiri (`?to=budi-santoso` menjadi "Budi Santoso").

## 4. Ganti foto, video & musik (opsional)
Taruh file dengan nama berikut di `web/assets/`. Halaman memakainya otomatis; selama filenya belum ada, yang tampil ilustrasi:

| File | Dipakai untuk |
|---|---|
| `mempelai-pria.jpg`, `mempelai-wanita.jpg` | Foto profil mempelai (rasio 4:5) |
| `galeri-1.jpg` … `galeri-6.jpg` | Galeri prewedding (foto 1–4 juga tampil di easel taman 3D) |
| `prewed.mp4` | Videotron (format MP4 H.264, sebaiknya < 20 MB) |
| `musik.mp3` | Musik latar (menggantikan musik bawaan) |

Teks (nama mempelai & orang tua, alamat, rekening, kisah, tanggal) bisa diedit langsung di `index.html`. Nama di papan gerbang, layar videotron, dan neon photo booth juga ada di sana: cari "Raditya" lalu ganti semuanya. Placeholder lain: "Jl. Contoh", "0000 1234 56".

## 5. Melihat RSVP
Supabase → **Table Editor → rsvp**. Bisa diekspor ke CSV. Rekap cepat lewat SQL Editor:
```sql
select hadir, count(*) as ucapan, sum(jumlah) as orang from public.rsvp group by hadir;
```
Untuk menghapus ucapan yang tidak pantas, hapus barisnya di Table Editor.

## Kredit aset 3D
- Kupu-kupu: "Butterfly" oleh assetfactory, https://sketchfab.com/3d-models/butterfly-87ef5cea7e2f4557a28503f5b96646cd (lisensi Sketchfab Standard).
- Karakter: Xbot dan tekstur rumput, kayu, air dari contoh three.js (MIT).
