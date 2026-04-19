-- Supabase schema for NeoSapien Transfer (Supabase-only backend)

create extension if not exists "pgcrypto";

create table if not exists public.users (
  uid text primary key,
  short_code text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.short_codes (
  code text primary key,
  uid text not null unique,
  reserved_at timestamptz not null default now(),
  constraint short_codes_uid_fkey foreign key (uid) references public.users(uid) on delete cascade
);

create table if not exists public.transfers (
  id uuid primary key default gen_random_uuid(),
  sender_uid text not null,
  receiver_uid text not null,
  status text not null,
  ttl_expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  total_bytes bigint not null default 0,
  completed_bytes bigint not null default 0,
  failure_code text null
);

create table if not exists public.transfer_files (
  id uuid primary key default gen_random_uuid(),
  transfer_id uuid not null references public.transfers(id) on delete cascade,
  name text not null,
  size bigint not null,
  sha256 text not null,
  storage_path text not null,
  local_saved_path text null,
  status text not null,
  bytes_transferred bigint not null default 0
);

alter table public.transfer_files
add column if not exists local_saved_path text null;

alter table public.users enable row level security;
alter table public.short_codes enable row level security;
alter table public.transfers enable row level security;
alter table public.transfer_files enable row level security;

drop policy if exists users_all_auth on public.users;
drop policy if exists users_select_own on public.users;
create policy users_select_own on public.users
for select to authenticated
using (auth.uid()::text = uid);

drop policy if exists users_insert_own on public.users;
create policy users_insert_own on public.users
for insert to authenticated
with check (auth.uid()::text = uid);

drop policy if exists users_update_own on public.users;
create policy users_update_own on public.users
for update to authenticated
using (auth.uid()::text = uid)
with check (auth.uid()::text = uid);

drop policy if exists short_codes_all_auth on public.short_codes;
drop policy if exists short_codes_select_auth on public.short_codes;
create policy short_codes_select_auth on public.short_codes
for select to authenticated
using (true);

drop policy if exists short_codes_insert_own on public.short_codes;
create policy short_codes_insert_own on public.short_codes
for insert to authenticated
with check (auth.uid()::text = uid);

drop policy if exists short_codes_update_own on public.short_codes;
create policy short_codes_update_own on public.short_codes
for update to authenticated
using (auth.uid()::text = uid)
with check (auth.uid()::text = uid);

drop policy if exists transfers_all_auth on public.transfers;
drop policy if exists transfers_select_participant on public.transfers;
create policy transfers_select_participant on public.transfers
for select to authenticated
using (auth.uid()::text = sender_uid or auth.uid()::text = receiver_uid);

drop policy if exists transfers_insert_sender on public.transfers;
create policy transfers_insert_sender on public.transfers
for insert to authenticated
with check (auth.uid()::text = sender_uid);

drop policy if exists transfers_update_participant on public.transfers;
create policy transfers_update_participant on public.transfers
for update to authenticated
using (auth.uid()::text = sender_uid or auth.uid()::text = receiver_uid)
with check (
  (auth.uid()::text = sender_uid or auth.uid()::text = receiver_uid)
  and sender_uid = (select sender_uid from public.transfers t where t.id = transfers.id)
  and receiver_uid = (select receiver_uid from public.transfers t where t.id = transfers.id)
);

drop policy if exists transfer_files_all_auth on public.transfer_files;
drop policy if exists transfer_files_select_participant on public.transfer_files;
create policy transfer_files_select_participant on public.transfer_files
for select to authenticated
using (
  exists (
    select 1 from public.transfers t
    where t.id = transfer_id
      and (t.sender_uid = auth.uid()::text or t.receiver_uid = auth.uid()::text)
  )
);

drop policy if exists transfer_files_insert_sender on public.transfer_files;
create policy transfer_files_insert_sender on public.transfer_files
for insert to authenticated
with check (
  exists (
    select 1 from public.transfers t
    where t.id = transfer_id
      and t.sender_uid = auth.uid()::text
  )
);

drop policy if exists transfer_files_update_participant on public.transfer_files;
create policy transfer_files_update_participant on public.transfer_files
for update to authenticated
using (
  exists (
    select 1 from public.transfers t
    where t.id = transfer_id
      and (t.sender_uid = auth.uid()::text or t.receiver_uid = auth.uid()::text)
  )
)
with check (
  exists (
    select 1 from public.transfers t
    where t.id = transfer_id
      and (t.sender_uid = auth.uid()::text or t.receiver_uid = auth.uid()::text)
  )
);

insert into storage.buckets (id, name, public)
values ('transfers', 'transfers', false)
on conflict (id) do nothing;

drop policy if exists transfers_insert_auth on storage.objects;
create policy transfers_insert_auth
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'transfers'
  and exists (
    select 1 from public.transfers t
    where t.id::text = split_part(name, '/', 1)
      and t.sender_uid = auth.uid()::text
  )
);

drop policy if exists transfers_select_auth on storage.objects;
create policy transfers_select_auth
on storage.objects
for select
to authenticated
using (
  bucket_id = 'transfers'
  and exists (
    select 1 from public.transfers t
    where t.id::text = split_part(name, '/', 1)
      and (t.sender_uid = auth.uid()::text or t.receiver_uid = auth.uid()::text)
  )
);

-- REPLICATION SETUP (Critical for Zero-Refresh Realtime)
-- 1. Enable full replication logic for these tables
ALTER TABLE public.transfers REPLICA IDENTITY FULL;
ALTER TABLE public.transfer_files REPLICA IDENTITY FULL;

-- 2. Ensure they are added to the supabase_realtime publication
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    -- Attempt to add; if already added, this may fail gracefully depending on PG version
    -- Using dynamic SQL to avoid parser errors if already present
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.transfers, public.transfer_files';
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- Likely already part of the publication, which is fine
  RAISE NOTICE 'Skipping publication add: %', SQLERRM;
END $$;
