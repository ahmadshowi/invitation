-- =========================================================
--  Undangan Raditya & Anindya — skema database Supabase
--  Jalankan sekali di: Supabase Dashboard → SQL Editor → New query → Run
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
  jumlah      int  not null default 1 check (jumlah between 0 and 5),
  pesan       text not null check (char_length(pesan) between 3 and 500),
  created_at  timestamptz not null default now()
);
create index if not exists rsvp_created_at_idx on public.rsvp (created_at desc);

-- 3) Keamanan (Row Level Security)
alter table public.guests enable row level security;
alter table public.rsvp   enable row level security;

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

-- Siapa pun boleh mengirim RSVP dan membaca ucapan; tidak ada yang bisa mengubah/menghapus dari halaman.
drop policy if exists "rsvp insert publik" on public.rsvp;
create policy "rsvp insert publik" on public.rsvp
  for insert to anon, authenticated with check (true);

drop policy if exists "rsvp baca publik" on public.rsvp;
create policy "rsvp baca publik" on public.rsvp
  for select to anon, authenticated using (true);

-- guest_slug yang tidak terdaftar disimpan sebagai NULL, bukan gagal
create or replace function public.rsvp_clean_slug()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.guest_slug is not null and not exists (select 1 from public.guests where slug = new.guest_slug) then
    new.guest_slug := null;
  end if;
  return new;
end $$;
drop trigger if exists rsvp_clean_slug on public.rsvp;
create trigger rsvp_clean_slug before insert on public.rsvp for each row execute function public.rsvp_clean_slug();

-- 4) Realtime: ucapan baru langsung muncul tanpa refresh
do $$ begin
  alter publication supabase_realtime add table public.rsvp;
exception when duplicate_object then null; end $$;

-- 5) Contoh tamu
insert into public.guests (slug, name) values
  ('nova',  'Nova'),
  ('bnb',   'B&B'),
  ('oishi', 'OISHI')
on conflict (slug) do update set name = excluded.name;

-- Rekap kehadiran (jalankan kapan saja di SQL Editor):
-- select hadir, count(*) as ucapan, sum(jumlah) as orang from public.rsvp group by hadir;
