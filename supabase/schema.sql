-- =========================================================
--  Undangan Rayana & Hasna — skema database Supabase
--  Jalankan di: Supabase Dashboard → SQL Editor → New query → tempel semua → Run
--  Aman dijalankan ulang (data yang sudah ada tidak terhapus).
-- =========================================================

-- 1) Daftar tamu (untuk link personal: /?to=nova)
create table if not exists public.guests (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique check (slug ~ '^[a-z0-9-]{1,60}$'),
  name        text not null check (char_length(name) between 1 and 80),
  created_at  timestamptz not null default now()
);

-- 2) RSVP + ucapan
create table if not exists public.rsvp (
  id          uuid primary key default gen_random_uuid(),
  guest_slug  text references public.guests(slug) on delete set null,
  nama        text not null check (char_length(nama) between 2 and 60),
  hadir       text not null check (hadir in ('hadir','ragu','tidak')),
  jumlah      int  not null default 1,
  pesan       text not null check (char_length(pesan) between 3 and 500),
  tampil      boolean not null default true,   -- hilangkan centang untuk menyembunyikan ucapan
  created_at  timestamptz not null default now()
);
alter table public.rsvp add column if not exists tampil boolean not null default true;
-- Formulir membatasi maks. 2 orang; database ikut menjaganya
alter table public.rsvp drop constraint if exists rsvp_jumlah_check;
alter table public.rsvp add constraint rsvp_jumlah_check check (jumlah between 0 and 2);
create index if not exists rsvp_created_at_idx on public.rsvp (created_at desc);

-- 3) Pengaturan
--    langsung_tampil = true  → ucapan baru langsung muncul (kamu sembunyikan kalau ada yang aneh)
--    langsung_tampil = false → ucapan baru menunggu kamu centang kolom "tampil"
create table if not exists public.pengaturan (
  id              int primary key default 1 check (id = 1),
  langsung_tampil boolean not null default true
);
insert into public.pengaturan (id) values (1) on conflict (id) do nothing;

-- Catatan kiriman per perangkat, hanya untuk batas spam (berisi sidik IP yang di-hash, bukan IP asli)
create table if not exists public.rsvp_log (
  ip_hash     text not null,
  created_at  timestamptz not null default now()
);
create index if not exists rsvp_log_idx on public.rsvp_log (ip_hash, created_at desc);

-- 4) Keamanan (Row Level Security)
alter table public.guests     enable row level security;
alter table public.rsvp       enable row level security;
alter table public.pengaturan enable row level security;  -- tanpa policy = tidak bisa diakses dari website
alter table public.rsvp_log   enable row level security;  -- tanpa policy = tidak bisa diakses dari website

-- Daftar tamu TIDAK bisa dibaca publik (nama tamu lain tidak bocor).
-- Halaman hanya bisa menanyakan satu nama lewat fungsi get_guest(slug).
create or replace function public.get_guest(p_slug text)
returns text
language sql
security definer
set search_path = public
stable
as $$
  select name from public.guests where slug = lower(p_slug) limit 1;
$$;
grant execute on function public.get_guest(text) to anon, authenticated;

-- Siapa pun boleh mengirim RSVP; yang terbaca hanya ucapan yang tampil.
-- Tidak ada yang bisa mengubah/menghapus dari halaman.
drop policy if exists "rsvp insert publik" on public.rsvp;
create policy "rsvp insert publik" on public.rsvp
  for insert to anon, authenticated with check (true);

drop policy if exists "rsvp baca publik" on public.rsvp;
create policy "rsvp baca publik" on public.rsvp
  for select to anon, authenticated using (tampil);

-- 5) Saringan otomatis untuk setiap ucapan yang masuk
create or replace function public.rsvp_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  hdr  json;
  ip   text;
  ihash text;
  link constant text := '(https?://|www\.|\m[a-z0-9-]+\.(com|net|org|xyz|io|info|site|online|link|ly|me|top|shop|id|co|biz|click|app)\M)';
begin
  new.nama  := btrim(regexp_replace(new.nama,  '\s+', ' ', 'g'));
  new.pesan := btrim(new.pesan);

  -- nilai yang tidak boleh diatur dari halaman
  new.created_at := now();
  new.tampil := coalesce((select langsung_tampil from pengaturan where id = 1), true);
  if new.hadir = 'tidak' then new.jumlah := 0;
  elsif coalesce(new.jumlah, 0) < 1 then new.jumlah := 1;
  end if;

  -- guest_slug yang tidak terdaftar disimpan sebagai NULL, bukan gagal
  if new.guest_slug is not null and not exists (select 1 from guests where slug = new.guest_slug) then
    new.guest_slug := null;
  end if;

  -- spam hampir selalu membawa link
  if new.pesan ~* link or new.nama ~* link then
    raise exception 'rsvp:link';
  end if;

  -- ucapan yang sama persis dari nama yang sama
  if exists (select 1 from rsvp where lower(nama) = lower(new.nama) and lower(pesan) = lower(new.pesan)) then
    raise exception 'rsvp:dupe';
  end if;

  -- banjir kiriman dari mana pun: maks. 30 per menit
  if (select count(*) from rsvp where created_at > now() - interval '1 minute') >= 30 then
    raise exception 'rsvp:busy';
  end if;

  -- per jaringan: maks. 10 per 10 menit. Sengaja longgar: satu keluarga bisa mengisi bergantian,
  -- dan operator seluler sering memakai satu IP untuk banyak pelanggan.
  begin
    hdr := current_setting('request.headers', true)::json;
  exception when others then hdr := null;
  end;
  ip := coalesce(hdr->>'cf-connecting-ip', nullif(btrim(split_part(hdr->>'x-forwarded-for', ',', 1)), ''), hdr->>'x-real-ip');
  if ip is not null then
    ihash := md5('undangan:' || ip);
    if (select count(*) from rsvp_log where ip_hash = ihash and created_at > now() - interval '10 minutes') >= 10 then
      raise exception 'rsvp:rate';
    end if;
    insert into rsvp_log (ip_hash) values (ihash);
    delete from rsvp_log where created_at < now() - interval '1 day';
  end if;

  return new;
end $$;

drop trigger if exists rsvp_clean_slug on public.rsvp;
drop function if exists public.rsvp_clean_slug();
drop trigger if exists rsvp_guard on public.rsvp;
create trigger rsvp_guard before insert on public.rsvp for each row execute function public.rsvp_guard();

-- 6) Realtime: ucapan baru langsung muncul tanpa refresh
do $$ begin
  alter publication supabase_realtime add table public.rsvp;
exception when duplicate_object then null; end $$;

-- 7) Angka di bawah buku tamu (orang hadir, masih ragu, jumlah ucapan).
--    Dihitung di database supaya tetap benar walaupun ucapan ditampilkan per halaman.
--    Bukan security definer: aturan RLS tetap berlaku, jadi yang dihitung hanya ucapan yang tampil.
create or replace function public.ringkasan_ucapan()
returns json language sql stable set search_path = public as $$
  select json_build_object(
    'hadir',  coalesce(sum(jumlah) filter (where hadir = 'hadir'), 0),
    'ragu',   count(*) filter (where hadir = 'ragu'),
    'ucapan', count(*)
  ) from public.rsvp where tampil;
$$;
grant execute on function public.ringkasan_ucapan() to anon, authenticated;

-- 8) Catatan buka undangan + halaman rekap (rekap.html)
--    Setiap link tamu (?to=nova) yang dibuka dicatat. Isinya hanya slug, waktu, dan sidik IP yang di-hash.
create table if not exists public.kunjungan (
  id          bigint generated always as identity primary key,
  slug        text not null check (char_length(slug) between 1 and 60),
  ip_hash     text,
  created_at  timestamptz not null default now()
);
create index if not exists kunjungan_slug_idx on public.kunjungan (slug, created_at desc);
create index if not exists kunjungan_created_idx on public.kunjungan (created_at desc);
alter table public.kunjungan enable row level security;  -- tanpa policy: hanya lewat fungsi di bawah

-- PIN halaman rekap disimpan sebagai hash, bukan PIN aslinya
alter table public.pengaturan add column if not exists rekap_pin text;

-- Catatan PIN salah, untuk mengerem tebak-tebakan PIN
create table if not exists public.rekap_log (
  ip_hash     text not null,
  created_at  timestamptz not null default now()
);
alter table public.rekap_log enable row level security;

create or replace function public._ip_hash()
returns text language plpgsql stable set search_path = public as $$
declare hdr json; ip text;
begin
  begin
    hdr := current_setting('request.headers', true)::json;
  exception when others then return null;
  end;
  ip := coalesce(hdr->>'cf-connecting-ip', nullif(btrim(split_part(hdr->>'x-forwarded-for', ',', 1)), ''), hdr->>'x-real-ip');
  return case when ip is null then null else md5('undangan:' || ip) end;
end $$;
revoke execute on function public._ip_hash() from public, anon, authenticated;

create or replace function public._hash_pin(p_pin text)
returns text language sql immutable as $$
  select encode(sha256(convert_to('undangan-rekap:' || coalesce(p_pin, ''), 'UTF8')), 'hex');
$$;
revoke execute on function public._hash_pin(text) from public, anon, authenticated;

-- Dipanggil halaman undangan setiap kali link tamu dibuka
create or replace function public.catat_buka(p_slug text)
returns void language plpgsql security definer set search_path = public as $$
declare
  s  text := lower(btrim(regexp_replace(coalesce(p_slug, ''), '\s+', ' ', 'g')));
  ih text := public._ip_hash();
begin
  if char_length(s) not between 1 and 60 then return; end if;
  -- refresh / buka ulang dari perangkat yang sama dalam 2 menit dihitung sekali
  if ih is not null and exists (select 1 from kunjungan where slug = s and ip_hash = ih and created_at > now() - interval '2 minutes') then
    return;
  end if;
  -- rem untuk yang iseng: maks. 20 catatan per jaringan per 10 menit, 200 per menit untuk seluruh website
  if ih is not null and (select count(*) from kunjungan where ip_hash = ih and created_at > now() - interval '10 minutes') >= 20 then
    return;
  end if;
  if (select count(*) from kunjungan where created_at > now() - interval '1 minute') >= 200 then
    return;
  end if;
  insert into kunjungan (slug, ip_hash) values (s, ih);
end $$;
grant execute on function public.catat_buka(text) to anon, authenticated;

-- Atur PIN rekap. Hanya bisa dijalankan dari SQL Editor, tidak dari website:
--   select public.atur_pin_rekap('pin-rahasia-kamu');
create or replace function public.atur_pin_rekap(p_pin text)
returns text language plpgsql security definer set search_path = public as $$
begin
  if char_length(coalesce(p_pin, '')) < 6 then
    raise exception 'PIN minimal 6 karakter';
  end if;
  update pengaturan set rekap_pin = public._hash_pin(p_pin) where id = 1;
  return 'PIN rekap tersimpan';
end $$;
revoke execute on function public.atur_pin_rekap(text) from public, anon, authenticated;

-- Data halaman rekap: semua RSVP (termasuk yang disembunyikan) + berapa kali tiap link dibuka.
-- PIN salah tidak membuka apa pun; setelah 5 kali salah dari satu jaringan, dikunci 15 menit.
create or replace function public.rekap(p_pin text)
returns json language plpgsql security definer set search_path = public as $$
declare
  ih     text := coalesce(public._ip_hash(), 'tanpa-ip');
  stored text;
begin
  delete from rekap_log where created_at < now() - interval '1 day';
  if (select count(*) from rekap_log where ip_hash = ih and created_at > now() - interval '15 minutes') >= 5
     or (select count(*) from rekap_log where created_at > now() - interval '15 minutes') >= 50 then
    return json_build_object('error', 'rate');
  end if;

  select rekap_pin into stored from pengaturan where id = 1;
  if stored is null then
    return json_build_object('error', 'nopin');
  end if;
  if public._hash_pin(p_pin) <> stored then
    insert into rekap_log (ip_hash) values (ih);
    return json_build_object('error', 'pin');
  end if;

  return json_build_object(
    'tamu', coalesce((
      select json_agg(t order by t.terakhir desc nulls last, t.nama)
      from (
        select coalesce(g.slug, k.slug) as slug, g.name as nama, (g.slug is not null) as terdaftar,
               coalesce(k.dibuka, 0) as dibuka, coalesce(k.perangkat, 0) as perangkat, k.pertama, k.terakhir
        from public.guests g
        full join (
          select slug, count(*) as dibuka, count(distinct ip_hash) as perangkat,
                 min(created_at) as pertama, max(created_at) as terakhir
          from public.kunjungan group by slug
        ) k on k.slug = g.slug
      ) t
    ), '[]'::json),
    'rsvp', coalesce((
      select json_agg(r order by r.created_at desc)
      from (select nama, hadir, jumlah, pesan, tampil, guest_slug, created_at from public.rsvp) r
    ), '[]'::json)
  );
end $$;
grant execute on function public.rekap(text) to anon, authenticated;

-- 9) Contoh tamu
insert into public.guests (slug, name) values
  ('nova',  'Nova'),
  ('bnb',   'B&B'),
  ('oishi', 'OISHI')
on conflict (slug) do update set name = excluded.name;

-- =========================================================
--  Perintah yang berguna (jalankan kapan saja di SQL Editor)
-- =========================================================
-- Atur / ganti PIN halaman rekap (domainmu/rekap.html), minimal 6 karakter:
--   select public.atur_pin_rekap('pin-rahasia-kamu');
--
-- Hapus catatan buka link (misalnya setelah kamu sendiri mencoba-coba link tamu):
--   delete from public.kunjungan;
--
-- Rekap kehadiran lengkap (termasuk yang disembunyikan):
--   select hadir, count(*) as ucapan, sum(jumlah) as orang from public.rsvp group by hadir;
--
-- Ganti ke mode persetujuan (ucapan baru menunggu kamu centang "tampil"):
--   update public.pengaturan set langsung_tampil = false;
-- Kembali ke mode langsung tampil:
--   update public.pengaturan set langsung_tampil = true;
--
-- Lihat ucapan yang disembunyikan / menunggu persetujuan:
--   select nama, pesan, created_at from public.rsvp where not tampil order by created_at desc;
