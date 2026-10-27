-- =====================================================================
--  PRESENSI GTK - SMP NEGERI 1 BANDAR LAMPUNG  |  SETUP SUPABASE
--  Jalankan SELURUH isi file ini sekali di: Supabase > SQL Editor > Run
--  Aman dijalankan ulang (idempotent).
-- =====================================================================

-- Semua objek aplikasi ini ditaruh di schema khusus "gtk" agar tidak bentrok
-- dengan tabel/fungsi aplikasi lain di project Supabase yang sama.
create schema if not exists gtk;
set search_path to gtk, public;

-- ---------- TABEL ----------
create table if not exists pengaturan(kunci text primary key, nilai text not null default '');

create table if not exists pegawai(
  id text primary key default substr(replace(gen_random_uuid()::text,'-',''),1,10),
  nip text not null default '', nuptk text not null default '', nama text not null,
  jenis_kelamin text not null default 'L' check (jenis_kelamin in ('L','P')),
  tempat_lahir text not null default '', tanggal_lahir text not null default '',
  status_kepegawaian text not null check (status_kepegawaian in ('PNS','PPPK','PPPK Paruh Waktu','Guru Honor Sekolah','Tenaga Honor Sekolah')),
  jenis_ptk text not null check (jenis_ptk in ('Kepala Sekolah','Guru','Tenaga Kependidikan','Tenaga Kependidikan 2','Tenaga Kependidikan 3')),
  username text not null, password text not null default '123456',
  face jsonb, foto_wajah text not null default '',
  aktif boolean not null default true, dibuat_pada timestamptz not null default now());
create unique index if not exists pegawai_user_uq  on pegawai(lower(username));
create unique index if not exists pegawai_nip_uq   on pegawai(nip)   where nip<>'';
create unique index if not exists pegawai_nuptk_uq on pegawai(nuptk) where nuptk<>'';
-- Jenis PTK: Kepala Sekolah, Guru, Tenaga Kependidikan 1-3 (aman untuk database yang sudah ada)
alter table pegawai drop constraint if exists pegawai_jenis_ptk_check;
alter table pegawai add constraint pegawai_jenis_ptk_check check (jenis_ptk in ('Kepala Sekolah','Guru','Tenaga Kependidikan','Tenaga Kependidikan 2','Tenaga Kependidikan 3'));

create table if not exists presensi(
  id text primary key default substr(replace(gen_random_uuid()::text,'-',''),1,10),
  tanggal date not null, pegawai_id text not null, nip text not null default '', nama text not null default '',
  jam_masuk text, status_masuk text, menit_terlambat int, lat_masuk float8, lng_masuk float8, jarak_masuk int, foto_masuk text,
  jam_pulang text, status_pulang text, menit_awal int, lat_pulang float8, lng_pulang float8, jarak_pulang int, foto_pulang text,
  keterangan text, unique(tanggal,pegawai_id));
create index if not exists presensi_tgl_idx on presensi(tanggal);

create table if not exists izin(
  id text primary key default substr(replace(gen_random_uuid()::text,'-',''),1,10),
  tanggal date not null, pegawai_id text not null, nip text not null default '', nama text not null default '',
  jenis text not null check (jenis in ('Izin','Sakit','Dinas Luar')), keterangan text not null default '',
  dibuat_oleh text not null default 'Admin', dibuat_pada timestamptz not null default now(), unique(pegawai_id,tanggal));
-- lampiran surat (URL file di Storage bucket gtk-surat)
alter table izin add column if not exists lampiran_url text not null default '';
alter table izin add column if not exists lampiran_tipe text not null default '';

create table if not exists libur(
  id text primary key default substr(replace(gen_random_uuid()::text,'-',''),1,10),
  tanggal date not null unique, keterangan text not null);

create table if not exists sesi(
  token uuid primary key default gen_random_uuid(), pegawai_id text not null,
  kadaluarsa timestamptz not null default now()+interval '30 days');

-- ---------- KEAMANAN (RLS) ----------
-- Semua tabel TERKUNCI untuk akses langsung (anon/authenticated). Seluruh akses data
-- lewat fungsi api() di bawah: admin = Supabase Auth (auth.uid()), pegawai = token sesi
-- hasil login username/password dari tabel pegawai (BUKAN Supabase Auth).
alter table pengaturan enable row level security;
alter table pegawai    enable row level security;
alter table presensi   enable row level security;
alter table izin       enable row level security;
alter table libur      enable row level security;
alter table sesi       enable row level security;

-- ---------- PENGATURAN AWAL ----------
insert into pengaturan(kunci,nilai) values
 ('NamaSekolah','SMP Negeri 1 Bandar Lampung'),('Alamat','Bandar Lampung, Provinsi Lampung'),
 ('LogoURL','https://lh3.googleusercontent.com/d/1GDe6aqXyF_RR6kL3jMCy0vWqaO83jgyp'),
 ('TahunAjaran','2026/2027'),('Semester','1 (Ganjil)'),('JamMasuk','07:00'),('JamPulang','15:00'),
 ('ToleransiJam','3'),('HariKerja','1,2,3,4,5'),('Latitude','-5.4294'),('Longitude','105.2625'),
 ('RadiusMeter','150'),('KepalaSekolah','Nama Kepala Sekolah, M.Pd'),('NIPKepsek','-'),('Kota','Bandar Lampung')
on conflict (kunci) do nothing;

-- jam masuk/pulang per Jenis PTK (awalnya disalin dari jam umum; selanjutnya diatur admin di Pengaturan)
insert into pengaturan(kunci,nilai)
select 'Jam'||j.t||'_'||s.k,(select nilai from pengaturan where kunci='Jam'||j.t)
from (values ('Masuk'),('Pulang')) j(t), (values ('KS'),('Guru'),('Tendik'),('Tendik2'),('Tendik3')) s(k)
on conflict (kunci) do nothing;

-- ---------- STORAGE FOTO (pengganti Google Drive) ----------
insert into storage.buckets(id,name,public) values('gtk-foto','gtk-foto',true)
  on conflict (id) do update set public=true;
drop policy if exists gtk_foto_upload on storage.objects;
create policy gtk_foto_upload on storage.objects for insert to anon, authenticated with check (bucket_id='gtk-foto');

-- ---------- STORAGE LAMPIRAN SURAT IZIN/SAKIT/DL (maks 500 KB per file) ----------
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
  values('gtk-surat','gtk-surat',true,512000,array['application/pdf','image/jpeg','image/png','image/webp'])
  on conflict (id) do update set public=true,file_size_limit=512000,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists gtk_surat_upload on storage.objects;
create policy gtk_surat_upload on storage.objects for insert to anon, authenticated with check (bucket_id='gtk-surat');

-- ---------- FUNGSI BANTU ----------
create or replace function _cfg(k text) returns text language sql stable as $$ select nilai from pengaturan where kunci=k $$;
create or replace function _jam(ptk text, tipe text) returns text language sql stable as $$
  select coalesce(nullif(_cfg('Jam'||tipe||'_'||case ptk when 'Kepala Sekolah' then 'KS' when 'Guru' then 'Guru' when 'Tenaga Kependidikan' then 'Tendik' when 'Tenaga Kependidikan 2' then 'Tendik2' when 'Tenaga Kependidikan 3' then 'Tendik3' else '' end),''),_cfg('Jam'||tipe)) $$;
create or replace function _tomin(t text) returns int language sql immutable as $$ select split_part(t,':',1)::int*60+split_part(t,':',2)::int $$;
create or replace function _hm(m int) returns text language sql immutable as $$ select lpad((m/60)::text,2,'0')||':'||lpad((m%60)::text,2,'0') $$;
create or replace function _work(d date) returns boolean language sql stable as $$
  select extract(dow from d)::int::text = any(string_to_array(_cfg('HariKerja'),',')) and not exists(select 1 from libur where tanggal=d) $$;
create or replace function _d(s text) returns date language plpgsql immutable as $$
begin
  if s is null or s !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Rentang tanggal tidak valid'; end if;
  return s::date;
exception when others then raise exception 'Rentang tanggal tidak valid';
end $$;
create or replace function _hav(a float8,b float8,c float8,d float8) returns float8 language sql immutable as $$
  select 2*6371000*asin(sqrt(power(sin(radians(c-a)/2),2)+cos(radians(a))*cos(radians(c))*power(sin(radians(d-b)/2),2))) $$;
create or replace function _set() returns jsonb language sql stable as $$
  select coalesce(jsonb_object_agg(kunci,nilai),'{}'::jsonb) from pengaturan
  where kunci in ('NamaSekolah','Alamat','LogoURL','TahunAjaran','Semester','JamMasuk','JamPulang','ToleransiJam','HariKerja','Latitude','Longitude','RadiusMeter','KepalaSekolah','NIPKepsek','Kota')
     or kunci ~ '^Jam(Masuk|Pulang)_(KS|Guru|Tendik|Tendik2|Tendik3)$' $$;
create or replace function _uobj(r pegawai) returns jsonb language sql stable as $$
  select jsonb_build_object('id',r.id,'nama',r.nama,'username',r.username,'role','Pegawai','jenisPTK',r.jenis_ptk,'status',r.status_kepegawaian,'nip',r.nip,'face',r.face is not null) $$;
create or replace function _pobj(r pegawai) returns jsonb language sql stable as $$
  select jsonb_build_object('id',r.id,'nip',r.nip,'nuptk',r.nuptk,'nama',r.nama,'jk',r.jenis_kelamin,'tempat',r.tempat_lahir,'tgl',r.tanggal_lahir,
    'status',r.status_kepegawaian,'ptk',r.jenis_ptk,'username',r.username,'password',r.password,'face',r.face is not null,'aktif',r.aktif) $$;
create or replace function _pres(r presensi) returns jsonb language sql stable as $$
  select jsonb_build_object('id',r.id,'tgl',r.tanggal::text,'pid',r.pegawai_id,'nip',r.nip,'nama',r.nama,
    'masuk',coalesce(r.jam_masuk,''),'stMasuk',coalesce(r.status_masuk,''),'telat',coalesce(r.menit_terlambat,0),'jarakMasuk',r.jarak_masuk,'fotoMasuk',coalesce(r.foto_masuk,''),
    'pulang',coalesce(r.jam_pulang,''),'stPulang',coalesce(r.status_pulang,''),'awal',coalesce(r.menit_awal,0),'jarakPulang',r.jarak_pulang,'fotoPulang',coalesce(r.foto_pulang,''),
    'ket',coalesce(r.keterangan,'')) $$;

-- baris rekap per pegawai per hari (hari kerja, tidak libur, <= hari ini)
create or replace function _rows(f date, t date, ids text[]) returns jsonb language sql stable as $$
  with td as (select (now() at time zone 'Asia/Jakarta')::date d)
  select coalesce(jsonb_agg(jsonb_build_object(
    'tgl',g.x::date::text,'pid',p.id,'nip',p.nip,'nama',p.nama,'ptk',p.jenis_ptk,'status',p.status_kepegawaian,
    'masuk',coalesce(r.jam_masuk,''),'stMasuk',coalesce(r.status_masuk,''),'telat',coalesce(r.menit_terlambat,0),
    'pulang',coalesce(r.jam_pulang,''),'stPulang',coalesce(r.status_pulang,''),'awal',coalesce(r.menit_awal,0),
    'ket',case when r.id is not null then coalesce(r.keterangan,'') else coalesce(z.keterangan,'') end,
    'st',case when r.id is not null then 'Hadir' when z.id is not null then z.jenis when g.x::date=td.d then 'Belum' else 'Alpa' end,
    'recId',coalesce(r.id,''),'fotoMasuk',coalesce(r.foto_masuk,''),'fotoPulang',coalesce(r.foto_pulang,''))),'[]'::jsonb)
  from td, generate_series(f::timestamp, least(t,td.d)::timestamp, interval '1 day') g(x)
  cross join pegawai p
  left join presensi r on r.tanggal=g.x::date and r.pegawai_id=p.id
  left join izin z on z.tanggal=g.x::date and z.pegawai_id=p.id
  where p.id=any(ids) and (r.id is not null or z.id is not null or _work(g.x::date)) $$;

create or replace function _cnt(r jsonb) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'hadir',count(*) filter (where e->>'st'='Hadir'),'tepat',count(*) filter (where e->>'stMasuk'='Tepat Waktu'),
    'telat',count(*) filter (where e->>'stMasuk'='Terlambat'),'izin',count(*) filter (where e->>'st'='Izin'),
    'sakit',count(*) filter (where e->>'st'='Sakit'),'dl',count(*) filter (where e->>'st'='Dinas Luar'),
    'belum',count(*) filter (where e->>'st'='Belum'),'alpa',count(*) filter (where e->>'st'='Alpa'))
  from jsonb_array_elements(r) e $$;

-- ---------- FUNGSI UTAMA: api(aksi, parameter) ----------
create or replace function api(a text, p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path=gtk, public as $$
declare
  adm boolean := auth.uid() is not null;
  td date := (now() at time zone 'Asia/Jakarta')::date;
  nw text := to_char(now() at time zone 'Asia/Jakarta','HH24:MI');
  u pegawai; x pegawai; ex pegawai; ex2 pegawai; r presensi; z izin;
  ids text[]; o jsonb; w jsonb; tw jsonb; c jsonb; rec jsonb;
  wl jsonb:='[]'; wt jsonb:='[]'; wtl jsonb:='[]'; wi jsonb:='[]'; fail jsonb:='[]';
  f date; t date; d date; n int; i int; tok uuid; k text; v text; un text; pid text; msg text;
  tol int; jm int; jp int; nm int; ds float8; fd float8; added int:=0; upd int:=0; newids text[]:='{}'; lm text:=''; lt text:='';
begin
  -- autentikasi: admin (Supabase Auth) atau pegawai (token sesi)
  if a not in ('publicSettings','login') and not adm then
    select pg.* into u from sesi s join pegawai pg on pg.id=s.pegawai_id
      where s.token::text=coalesce(p->>'token','') and s.kadaluarsa>now() and pg.aktif;
    if not found then raise exception 'AUTH'; end if;
  end if;
  if a in ('listPegawai','savePegawai','deletePegawai','resetFace','importPegawai','saveSettings','saveLibur','deleteLibur','saveRekap') and not adm then
    raise exception 'Akses ditolak: khusus admin'; end if;
  if a in ('myToday','enrollFace','submitPresensi','changePassword') and adm then
    raise exception 'Fitur ini hanya untuk akun pegawai'; end if;

  if a='publicSettings' then
    return coalesce((select jsonb_object_agg(kunci,nilai) from pengaturan where kunci in ('NamaSekolah','Alamat','LogoURL','TahunAjaran','Semester')),'{}');

  elsif a='login' then
    select * into u from pegawai where lower(username)=lower(trim(coalesce(p->>'username',''))) and password=coalesce(p->>'password','');
    if not found then raise exception 'Username atau password salah'; end if;
    if not u.aktif then raise exception 'Akun tidak aktif. Hubungi admin.'; end if;
    delete from sesi where kadaluarsa<now();
    insert into sesi(pegawai_id) values(u.id) returning token into tok;
    return jsonb_build_object('token',tok,'user',_uobj(u));

  elsif a='bootstrap' then
    return jsonb_build_object(
      'user',case when adm then jsonb_build_object('id','admin','nama','Administrator','username',coalesce(auth.jwt()->>'email','admin'),'role','Admin','jenisPTK','','status','','nip','','face',false) else _uobj(u) end,
      'settings',_set(),'serverMs',(extract(epoch from now())*1000)::bigint);

  elsif a='changePassword' then
    if u.password<>coalesce(p->>'old','') then raise exception 'Password lama salah'; end if;
    if length(coalesce(p->>'new',''))<4 then raise exception 'Password baru minimal 4 karakter'; end if;
    update pegawai set password=p->>'new' where id=u.id;
    return to_jsonb(true);

  -- ===== DATA PEGAWAI =====
  elsif a='listPegawai' then
    return coalesce((select jsonb_agg(_pobj(g) order by g.nama) from pegawai g),'[]');

  elsif a='savePegawai' then
    o:=coalesce(p->'p','{}'); v:=trim(coalesce(o->>'nama',''));
    if v='' then raise exception 'Nama wajib diisi'; end if;
    if coalesce(o->>'nip','')<>'' and o->>'nip' !~ '^\d+$' then raise exception 'NIP harus berupa angka'; end if;
    if coalesce(o->>'nuptk','')<>'' and o->>'nuptk' !~ '^\d+$' then raise exception 'NUPTK harus berupa angka'; end if;
    if coalesce(o->>'jk','') not in ('L','P') then raise exception 'Jenis kelamin harus L atau P'; end if;
    if coalesce(o->>'status','') not in ('PNS','PPPK','PPPK Paruh Waktu','Guru Honor Sekolah','Tenaga Honor Sekolah') then raise exception 'Status kepegawaian tidak valid'; end if;
    if coalesce(o->>'ptk','') not in ('Kepala Sekolah','Guru','Tenaga Kependidikan','Tenaga Kependidikan 2','Tenaga Kependidikan 3') then raise exception 'Jenis PTK tidak valid'; end if;
    if coalesce(o->>'tgl','')<>'' and o->>'tgl' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Format tanggal lahir salah'; end if;
    pid:=nullif(o->>'id','');
    if pid is not null and not exists(select 1 from pegawai where id=pid) then raise exception 'Data pegawai tidak ditemukan'; end if;
    select * into ex from pegawai where nip=coalesce(o->>'nip','') and nip<>'' and id is distinct from pid;
    if found then raise exception 'NIP sudah terdaftar atas nama %',ex.nama; end if;
    select * into ex from pegawai where nuptk=coalesce(o->>'nuptk','') and nuptk<>'' and id is distinct from pid;
    if found then raise exception 'NUPTK sudah terdaftar atas nama %',ex.nama; end if;
    un:=coalesce(nullif(trim(o->>'username'),''),nullif(o->>'nip',''),nullif(o->>'nuptk',''),nullif(lower(regexp_replace(v,'[^a-zA-Z0-9]','','g')),''),'pegawai');
    if exists(select 1 from pegawai where lower(username)=lower(un) and id is distinct from pid) then
      raise exception 'Username "%" sudah dipakai. Gunakan username lain.',un; end if;
    if pid is null then
      insert into pegawai(nip,nuptk,nama,jenis_kelamin,tempat_lahir,tanggal_lahir,status_kepegawaian,jenis_ptk,username,password,aktif)
      values(coalesce(o->>'nip',''),coalesce(o->>'nuptk',''),v,o->>'jk',coalesce(trim(o->>'tempat'),''),coalesce(o->>'tgl',''),o->>'status',o->>'ptk',un,
             coalesce(nullif(trim(o->>'password'),''),'123456'),coalesce((o->>'aktif')::boolean,true)) returning * into x;
    else
      update pegawai set nip=coalesce(o->>'nip',''),nuptk=coalesce(o->>'nuptk',''),nama=v,jenis_kelamin=o->>'jk',tempat_lahir=coalesce(trim(o->>'tempat'),''),
        tanggal_lahir=coalesce(o->>'tgl',''),status_kepegawaian=o->>'status',jenis_ptk=o->>'ptk',username=un,
        password=coalesce(nullif(trim(o->>'password'),''),password),aktif=coalesce((o->>'aktif')::boolean,true)
      where id=pid returning * into x;
    end if;
    return _pobj(x);

  elsif a='deletePegawai' then
    pid:=p->>'id'; delete from pegawai where id=pid;
    if not found then raise exception 'Data pegawai tidak ditemukan'; end if;
    delete from sesi where pegawai_id=pid; return to_jsonb(true);

  elsif a='resetFace' then
    update pegawai set face=null, foto_wajah='' where id=p->>'id';
    if not found then raise exception 'Data pegawai tidak ditemukan'; end if;
    return to_jsonb(true);

  elsif a='importPegawai' then
    if jsonb_array_length(coalesce(p->'rows','[]'))=0 then raise exception 'Tidak ada data untuk diimport'; end if;
    if jsonb_array_length(p->'rows')>1000 then raise exception 'Maksimal 1000 baris per import'; end if;
    for o in select e from jsonb_array_elements(p->'rows') e loop
      i:=coalesce((o->>'_r')::int,0); ex:=null; ex2:=null;
      if nullif(o->>'nip','') is not null then select * into ex from pegawai where nip=o->>'nip'; end if;
      if nullif(o->>'nuptk','') is not null then select * into ex2 from pegawai where nuptk=o->>'nuptk'; end if;
      if ex.id is null then ex:=ex2;
      elsif ex2.id is not null and ex2.id<>ex.id then
        fail:=fail||jsonb_build_object('row',i,'msg','NIP dan NUPTK terdaftar pada dua pegawai berbeda'); continue;
      end if;
      if ex.id is not null and ex.id=any(newids) then
        fail:=fail||jsonb_build_object('row',i,'msg','NIP/NUPTK duplikat di dalam file import'); continue; end if;
      v:=nullif(trim(o->>'username'),'');
      un:=coalesce(v,nullif(o->>'nip',''),nullif(o->>'nuptk',''),nullif(lower(regexp_replace(o->>'nama','[^a-zA-Z0-9]','','g')),''),'pegawai');
      if exists(select 1 from pegawai where lower(username)=lower(un) and id is distinct from ex.id) then
        if v is not null then fail:=fail||jsonb_build_object('row',i,'msg','Username "'||un||'" sudah dipakai'); continue; end if;
        n:=2; while exists(select 1 from pegawai where lower(username)=lower(un||n)) loop n:=n+1; end loop; un:=un||n;
      end if;
      if ex.id is not null then
        update pegawai set nip=coalesce(nullif(o->>'nip',''),nip),nuptk=coalesce(nullif(o->>'nuptk',''),nuptk),nama=o->>'nama',jenis_kelamin=o->>'jk',
          tempat_lahir=coalesce(o->>'tempat',''),tanggal_lahir=coalesce(o->>'tgl',''),status_kepegawaian=o->>'status',jenis_ptk=o->>'ptk',
          username=case when v is not null then un else username end,password=coalesce(nullif(o->>'password',''),password)
        where id=ex.id;
        upd:=upd+1;
      else
        insert into pegawai(nip,nuptk,nama,jenis_kelamin,tempat_lahir,tanggal_lahir,status_kepegawaian,jenis_ptk,username,password)
        values(coalesce(o->>'nip',''),coalesce(o->>'nuptk',''),o->>'nama',o->>'jk',coalesce(o->>'tempat',''),coalesce(o->>'tgl',''),o->>'status',o->>'ptk',un,
               coalesce(nullif(o->>'password',''),'123456')) returning id into pid;
        newids:=newids||pid; added:=added+1;
      end if;
    end loop;
    return jsonb_build_object('added',added,'updated',upd,'failed',fail);

  -- ===== PENGATURAN & LIBUR =====
  elsif a='saveSettings' then
    o:=coalesce(p->'s','{}');
    if o ? 'NamaSekolah' and trim(o->>'NamaSekolah')='' then raise exception 'Nama sekolah wajib diisi'; end if;
    if o ? 'JamMasuk' and o->>'JamMasuk' !~ '^([01]\d|2[0-3]):[0-5]\d$' then raise exception 'Format jam masuk salah'; end if;
    if o ? 'JamPulang' and o->>'JamPulang' !~ '^([01]\d|2[0-3]):[0-5]\d$' then raise exception 'Format jam pulang salah'; end if;
    if o ? 'ToleransiJam' and not coalesce(case when o->>'ToleransiJam' ~ '^\d+(\.\d+)?$' then (o->>'ToleransiJam')::numeric<=6 end,false) then raise exception 'Batas jam antara 0 - 6'; end if;
    if o ? 'HariKerja' and o->>'HariKerja' !~ '^[0-6](,[0-6])*$' then raise exception 'Hari kerja tidak valid'; end if;
    if o ? 'Latitude' and not coalesce(case when o->>'Latitude' ~ '^-?\d+(\.\d+)?$' then abs((o->>'Latitude')::float8)<=90 end,false) then raise exception 'Latitude tidak valid'; end if;
    if o ? 'Longitude' and not coalesce(case when o->>'Longitude' ~ '^-?\d+(\.\d+)?$' then abs((o->>'Longitude')::float8)<=180 end,false) then raise exception 'Longitude tidak valid'; end if;
    if o ? 'RadiusMeter' and not coalesce(case when o->>'RadiusMeter' ~ '^\d+(\.\d+)?$' then (o->>'RadiusMeter')::float8>=10 end,false) then raise exception 'Radius minimal 10 meter'; end if;
    for k in select jsonb_object_keys(o) loop
      if k ~ '^Jam(Masuk|Pulang)_(KS|Guru|Tendik|Tendik2|Tendik3)$' and o->>k !~ '^([01]\d|2[0-3]):[0-5]\d$' then raise exception 'Format jam salah'; end if;
    end loop;
    for k in select jsonb_object_keys(o) loop
      if k ~ '^Jam(Masuk|Pulang)_(KS|Guru|Tendik|Tendik2|Tendik3)$' or k = any(array['NamaSekolah','Alamat','LogoURL','TahunAjaran','Semester','JamMasuk','JamPulang','ToleransiJam','HariKerja','Latitude','Longitude','RadiusMeter','KepalaSekolah','NIPKepsek','Kota']) then
        insert into pengaturan(kunci,nilai) values(k,trim(coalesce(o->>k,''))) on conflict (kunci) do update set nilai=excluded.nilai;
      end if;
    end loop;
    return _set();

  elsif a='listLibur' then
    return coalesce((select jsonb_agg(jsonb_build_object('id',id,'tgl',tanggal::text,'ket',keterangan) order by tanggal) from libur),'[]');

  elsif a='saveLibur' then
    f:=_d(p->>'from'); t:=_d(p->>'to');
    if f>t then raise exception 'Rentang tanggal tidak valid'; end if;
    if t-f>120 then raise exception 'Maksimal 120 hari sekali input'; end if;
    if trim(coalesce(p->>'ket',''))='' then raise exception 'Keterangan wajib diisi'; end if;
    insert into libur(tanggal,keterangan) select g::date,trim(p->>'ket') from generate_series(f::timestamp,t::timestamp,interval '1 day') g on conflict (tanggal) do nothing;
    return to_jsonb(true);

  elsif a='deleteLibur' then
    delete from libur where id=p->>'id';
    if not found then raise exception 'Data tidak ditemukan'; end if;
    return to_jsonb(true);

  -- ===== PRESENSI PEGAWAI =====
  elsif a='myToday' then
    select * into r from presensi where pegawai_id=u.id and tanggal=td;
    select * into z from izin where pegawai_id=u.id and tanggal=td;
    return jsonb_build_object('rec',case when r.id is null then null else _pres(r) end,
      'izin',case when z.id is null then null else jsonb_build_object('jenis',z.jenis,'ket',z.keterangan) end,
      'libur',coalesce((select keterangan from libur where tanggal=td),''),'workday',_work(td));

  elsif a='enrollFace' then
    if u.face is not null then raise exception 'Wajah sudah terdaftar. Hubungi admin untuk mereset data wajah.'; end if;
    if coalesce(jsonb_typeof(p->'desc'),'')<>'array' or jsonb_array_length(p->'desc')<>128 then
      raise exception 'Wajah tidak terdeteksi. Pastikan kamera aktif dan wajah terlihat jelas.'; end if;
    update pegawai set face=p->'desc', foto_wajah=coalesce(nullif(p->>'photo',''),foto_wajah) where id=u.id;
    return to_jsonb(true);

  elsif a='submitPresensi' then
    k:=p->>'type';
    if k not in ('masuk','pulang') then raise exception 'Jenis presensi tidak valid'; end if;
    if not _work(td) then
      raise exception '%',coalesce('Hari ini libur: '||(select keterangan from libur where tanggal=td),'Hari ini bukan hari kerja'); end if;
    select * into z from izin where pegawai_id=u.id and tanggal=td;
    if found then raise exception 'Hari ini Anda tercatat: %',z.jenis; end if;
    if p->>'lat' is null or p->>'lng' is null then raise exception 'Lokasi GPS tidak terbaca. Aktifkan GPS dan izinkan akses lokasi.'; end if;
    ds:=_hav((p->>'lat')::float8,(p->>'lng')::float8,_cfg('Latitude')::float8,_cfg('Longitude')::float8);
    if ds>_cfg('RadiusMeter')::float8 then
      raise exception 'Di luar jangkauan: % m dari titik lokasi (maks % m)',round(ds),_cfg('RadiusMeter'); end if;
    select * into x from pegawai where id=u.id;
    if x.face is null then raise exception 'Wajah belum terdaftar. Daftarkan wajah terlebih dahulu.'; end if;
    if coalesce(jsonb_typeof(p->'desc'),'')<>'array' or jsonb_array_length(p->'desc')<>128 then
      raise exception 'Wajah tidak terdeteksi. Hadapkan wajah ke kamera.'; end if;
    select sqrt(sum(power(a1.val::float8-a2.val::float8,2))) into fd
      from jsonb_array_elements_text(x.face) with ordinality a1(val,ord)
      join jsonb_array_elements_text(p->'desc') with ordinality a2(val,ord) using (ord);
    if fd>0.55 then raise exception 'Wajah tidak cocok dengan data yang terdaftar.'; end if;
    tol:=(_cfg('ToleransiJam')::numeric*60)::int; jm:=_tomin(_jam(x.jenis_ptk,'Masuk')); jp:=_tomin(_jam(x.jenis_ptk,'Pulang')); nm:=_tomin(nw);
    insert into presensi(tanggal,pegawai_id,nip,nama) values(td,u.id,u.nip,u.nama) on conflict (tanggal,pegawai_id) do nothing;
    select * into r from presensi where tanggal=td and pegawai_id=u.id for update;
    if k='masuk' then
      if r.jam_masuk is not null then raise exception 'Anda sudah presensi masuk hari ini'; end if;
      if nm<jm-tol or nm>jm+tol then raise exception 'Presensi masuk dibuka pukul % - % WIB',_hm(jm-tol),_hm(jm+tol); end if;
      update presensi set jam_masuk=nw,status_masuk=case when nm>jm then 'Terlambat' else 'Tepat Waktu' end,menit_terlambat=greatest(0,nm-jm),
        lat_masuk=(p->>'lat')::float8,lng_masuk=(p->>'lng')::float8,jarak_masuk=round(ds),foto_masuk=coalesce(p->>'photo','') where id=r.id returning * into r;
      msg:='Presensi masuk berhasil pukul '||nw||' ('||r.status_masuk||')';
    else
      if r.jam_pulang is not null then raise exception 'Anda sudah presensi pulang hari ini'; end if;
      if nm<jp-tol or nm>jp+tol then raise exception 'Presensi pulang dibuka pukul % - % WIB',_hm(jp-tol),_hm(jp+tol); end if;
      update presensi set jam_pulang=nw,status_pulang=case when nm<jp then 'Pulang Lebih Awal' else 'Tepat Waktu' end,menit_awal=greatest(0,jp-nm),
        lat_pulang=(p->>'lat')::float8,lng_pulang=(p->>'lng')::float8,jarak_pulang=round(ds),foto_pulang=coalesce(p->>'photo','') where id=r.id returning * into r;
      msg:='Presensi pulang berhasil pukul '||nw||' ('||r.status_pulang||')';
    end if;
    return jsonb_build_object('msg',msg,'rec',_pres(r));

  -- ===== REKAP & KOREKSI =====
  elsif a='rekap' then
    f:=_d(p->>'from'); t:=_d(p->>'to');
    if f>t then raise exception 'Rentang tanggal tidak valid'; end if;
    if t-f>92 then raise exception 'Maksimal rentang 92 hari'; end if;
    if adm then
      ids:=array(select id from pegawai where aktif and (coalesce(p->>'ptk','')='' or jenis_ptk=p->>'ptk')
        and (coalesce(p->>'status','')='' or status_kepegawaian=p->>'status') and (coalesce(p->>'pid','')='' or id=p->>'pid'));
    else ids:=array[u.id]; end if;
    return jsonb_build_object('rows',_rows(f,t,ids));

  elsif a='saveRekap' then
    select * into x from pegawai where id=p->>'pid';
    if not found then raise exception 'Pegawai tidak ditemukan'; end if;
    d:=_d(p->>'tgl'); k:=p->>'st';
    if k not in ('Hadir','Izin','Sakit','Dinas Luar','Alpa') then raise exception 'Status tidak valid'; end if;
    if coalesce(p->>'masuk','')<>'' and p->>'masuk' !~ '^([01]\d|2[0-3]):[0-5]\d$' then raise exception 'Format jam masuk salah'; end if;
    if coalesce(p->>'pulang','')<>'' and p->>'pulang' !~ '^([01]\d|2[0-3]):[0-5]\d$' then raise exception 'Format jam pulang salah'; end if;
    if k='Hadir' and coalesce(p->>'masuk','')='' and coalesce(p->>'pulang','')='' then raise exception 'Isi minimal salah satu jam (masuk/pulang)'; end if;
    select lampiran_url,lampiran_tipe into lm,lt from izin where pegawai_id=x.id and tanggal=d;
    delete from presensi where pegawai_id=x.id and tanggal=d;
    delete from izin where pegawai_id=x.id and tanggal=d;
    v:=trim(coalesce(p->>'ket',''));
    if k='Hadir' then
      jm:=_tomin(_jam(x.jenis_ptk,'Masuk')); jp:=_tomin(_jam(x.jenis_ptk,'Pulang'));
      nm:=case when coalesce(p->>'masuk','')<>'' then _tomin(p->>'masuk') end; tol:=case when coalesce(p->>'pulang','')<>'' then _tomin(p->>'pulang') end;
      insert into presensi(tanggal,pegawai_id,nip,nama,jam_masuk,status_masuk,menit_terlambat,jam_pulang,status_pulang,menit_awal,keterangan)
      values(d,x.id,x.nip,x.nama,nullif(p->>'masuk',''),case when nm is null then null when nm>jm then 'Terlambat' else 'Tepat Waktu' end,case when nm is null then null else greatest(0,nm-jm) end,
             nullif(p->>'pulang',''),case when tol is null then null when tol<jp then 'Pulang Lebih Awal' else 'Tepat Waktu' end,case when tol is null then null else greatest(0,jp-tol) end,
             coalesce(nullif(v,''),'Koreksi admin'));
    elsif k<>'Alpa' then
      insert into izin(tanggal,pegawai_id,nip,nama,jenis,keterangan,dibuat_oleh,lampiran_url,lampiran_tipe) values(d,x.id,x.nip,x.nama,k,v,'Admin',coalesce(lm,''),coalesce(lt,''));
    end if;
    return to_jsonb(true);

  -- ===== DASHBOARD =====
  elsif a='dashboard' then
    ids:=case when adm then array(select id from pegawai where aktif) else array[u.id] end;
    w:=_rows(td-6,td,ids);
    for n in reverse 6..0 loop
      d:=td-n;
      c:=_cnt(coalesce((select jsonb_agg(e) from jsonb_array_elements(w) e where e->>'tgl'=d::text),'[]'));
      wl:=wl||to_jsonb((array['Min','Sen','Sel','Rab','Kam','Jum','Sab'])[extract(dow from d)::int+1]||' '||to_char(d,'DD'));
      wt:=wt||(c->'tepat'); wtl:=wtl||(c->'telat'); wi:=wi||to_jsonb((c->>'izin')::int+(c->>'sakit')::int+(c->>'dl')::int);
    end loop;
    select coalesce(jsonb_agg(jsonb_build_object('tgl',q.tgl::text,'jam',q.jam,'nama',q.nama,'aksi',q.aksi) order by q.tgl desc,q.jam desc),'[]') into rec from (
      select * from (
        select tanggal tgl,jam_masuk jam,nama,'masuk' aksi from presensi where tanggal>=td-14 and (adm or pegawai_id=u.id) and jam_masuk is not null
        union all
        select tanggal,jam_pulang,nama,'pulang' from presensi where tanggal>=td-14 and (adm or pegawai_id=u.id) and jam_pulang is not null) y
      order by tgl desc,jam desc limit 6) q;
    o:=jsonb_build_object('workday',_work(td),'liburKet',coalesce((select keterangan from libur where tanggal=td),''),
       'week',jsonb_build_object('labels',wl,'tepat',wt,'telat',wtl,'izin',wi),'recent',rec);
    if adm then
      tw:=coalesce((select jsonb_agg(e) from jsonb_array_elements(w) e where e->>'tgl'=td::text),'[]'); c:=_cnt(tw);
      return o||jsonb_build_object('total',cardinality(ids),
        'guru',(select count(*) from pegawai where aktif and jenis_ptk='Guru'),'ks',(select count(*) from pegawai where aktif and jenis_ptk='Kepala Sekolah'),'tendik',(select count(*) from pegawai where aktif and jenis_ptk like 'Tenaga%'),
        'hadir',c->'hadir','tepat',c->'tepat','telat',c->'telat','izin',c->'izin','sakit',c->'sakit','dl',c->'dl','belum',c->'belum',
        'pie',jsonb_build_array(c->'tepat',c->'telat',c->'izin',c->'sakit',c->'dl',c->'belum'),
        'ptk',(select jsonb_agg(jsonb_build_object('l',s.l,'h',s.h,'t',s.t) order by s.l) from (
               select g.l,count(e.val) filter (where e.val->>'st'='Hadir') h,count(e.val) t
               from unnest(array['Kepala Sekolah','Guru','Tenaga Kependidikan','Tenaga Kependidikan 2','Tenaga Kependidikan 3']) g(l) left join jsonb_array_elements(tw) e(val) on e.val->>'ptk'=g.l group by g.l) s));
    end if;
    c:=_cnt(_rows(date_trunc('month',td)::date,td,ids));
    select * into r from presensi where pegawai_id=u.id and tanggal=td;
    select * into z from izin where pegawai_id=u.id and tanggal=td;
    return o||jsonb_build_object(
      'me',jsonb_build_object('rec',case when r.id is null then null else _pres(r) end,
        'izin',case when z.id is null then null else jsonb_build_object('jenis',z.jenis,'ket',z.keterangan) end,
        'bulan',jsonb_build_object('hadir',c->'hadir','tepat',c->'tepat','telat',c->'telat','izin',c->'izin','sakit',c->'sakit','dl',c->'dl','alpa',c->'alpa')),
      'pie',jsonb_build_array(c->'tepat',c->'telat',c->'izin',c->'sakit',c->'dl',c->'alpa'));

  -- ===== IZIN / SAKIT / DINAS LUAR =====
  elsif a='listIzin' then
    f:=_d(p->>'from'); t:=_d(p->>'to');
    return coalesce((select jsonb_agg(jsonb_build_object('id',id,'tgl',tanggal::text,'pid',pegawai_id,'nip',nip,'nama',nama,'jenis',jenis,'ket',keterangan,'oleh',dibuat_oleh,'lamp',lampiran_url,'lampTipe',lampiran_tipe) order by tanggal desc,nama)
      from izin where tanggal between f and t
        and case when adm then (coalesce(p->>'pid','')='' or pegawai_id=p->>'pid') else pegawai_id=u.id end),'[]');

  elsif a='saveIzin' then
    pid:=case when adm then p->>'pid' else u.id end;
    select * into x from pegawai where id=pid;
    if not found then raise exception 'Pegawai tidak ditemukan'; end if;
    if coalesce(p->>'jenis','') not in ('Izin','Sakit','Dinas Luar') then raise exception 'Jenis tidak valid'; end if;
    f:=_d(p->>'from'); t:=_d(p->>'to');
    if f>t then raise exception 'Rentang tanggal tidak valid'; end if;
    if t-f>92 then raise exception 'Maksimal 92 hari sekali input'; end if;
    k:=coalesce(p->>'lamp',''); v:=coalesce(p->>'lampTipe','');
    if k<>'' and (k !~ '^https://[^ ]+/storage/v1/object/public/gtk-surat/[^ ]+$' or v not in ('application/pdf','image/jpeg','image/png','image/webp')) then raise exception 'Lampiran tidak valid'; end if;
    if k='' then v:=''; end if;
    n:=0;
    for d in select g::date from generate_series(f::timestamp,t::timestamp,interval '1 day') g loop
      if not _work(d) or exists(select 1 from presensi where pegawai_id=pid and tanggal=d) then continue; end if;
      insert into izin(tanggal,pegawai_id,nip,nama,jenis,keterangan,dibuat_oleh,lampiran_url,lampiran_tipe)
      values(d,pid,x.nip,x.nama,p->>'jenis',trim(coalesce(p->>'ket','')),case when adm then 'Admin' else 'Pegawai' end,k,v)
      on conflict (pegawai_id,tanggal) do update set jenis=excluded.jenis,keterangan=excluded.keterangan,dibuat_oleh=excluded.dibuat_oleh,dibuat_pada=now(),
        lampiran_url=case when excluded.lampiran_url<>'' then excluded.lampiran_url else izin.lampiran_url end,
        lampiran_tipe=case when excluded.lampiran_url<>'' then excluded.lampiran_tipe else izin.lampiran_tipe end;
      n:=n+1;
    end loop;
    if n=0 then raise exception 'Tidak ada hari kerja yang dapat dicatat pada rentang tersebut (libur / sudah ada presensi)'; end if;
    return jsonb_build_object('count',n);

  elsif a='deleteIzin' then
    delete from izin where id=p->>'id' and (adm or pegawai_id=u.id);
    if not found then raise exception 'Data tidak ditemukan'; end if;
    return to_jsonb(true);
  end if;

  raise exception 'Aksi tidak dikenal: %',a;
end $$;

-- ---------- HAK AKSES ----------
-- Fungsi di schema gtk memakai search_path gtk,public dan tidak bisa dipanggil langsung.
do $$ declare r record; begin
  for r in select p.proname, pg_get_function_identity_arguments(p.oid) args from pg_proc p where p.pronamespace='gtk'::regnamespace loop
    execute 'alter function gtk.'||r.proname||'('||r.args||') set search_path=gtk, public';
    execute 'revoke all on function gtk.'||r.proname||'('||r.args||') from public, anon, authenticated';
  end loop;
end $$;

-- Satu-satunya pintu masuk dari aplikasi (tidak mengubah fungsi lain di schema public)
create or replace function public.gtk_api(a text, p jsonb default '{}'::jsonb) returns jsonb
language sql security definer set search_path=gtk, public as $$ select gtk.api(a,p) $$;
revoke all on function public.gtk_api(text,jsonb) from public;
grant execute on function public.gtk_api(text,jsonb) to anon, authenticated;
