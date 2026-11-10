-- Run this once in Supabase SQL Editor for the two file-transfer tabs.
-- Uses a public bucket with UUID-only object paths; only the code lookup reveals a path.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('file-transfers','file-transfers',true,15728640,array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true,file_size_limit=15728640,allowed_mime_types=excluded.allowed_mime_types;

create table if not exists public.file_transfers (
 id uuid primary key default gen_random_uuid(),
 direction text not null check (direction in ('incoming','outgoing')),
 customer_name text,
 customer_phone text,
 file_path text not null unique,
 file_name text not null,
 mime_type text not null,
 file_size bigint not null,
 download_code text unique,
 expires_at timestamptz,
 created_at timestamptz not null default now()
);
alter table public.file_transfers enable row level security;

drop policy if exists "Public can submit incoming file records" on public.file_transfers;
create policy "Public can submit incoming file records" on public.file_transfers
for insert to anon, authenticated
with check (direction='incoming' and download_code is null);

drop policy if exists "Admins can manage file transfers" on public.file_transfers;
create policy "Admins can manage file transfers" on public.file_transfers
for all to authenticated
using (exists(select 1 from public.admin_users a where a.user_id=auth.uid()))
with check (exists(select 1 from public.admin_users a where a.user_id=auth.uid()));

drop policy if exists "Customers upload incoming files" on storage.objects;
create policy "Customers upload incoming files" on storage.objects
for insert to anon, authenticated
with check (bucket_id='file-transfers' and name like 'customer-inbox/%');

drop policy if exists "Admins upload outgoing files" on storage.objects;
create policy "Admins upload outgoing files" on storage.objects
for insert to authenticated
with check (bucket_id='file-transfers' and name like 'shop-outgoing/%' and exists(select 1 from public.admin_users a where a.user_id=auth.uid()));

create or replace function public.lookup_file_by_code(p_code text)
returns table(file_path text,file_name text)
language plpgsql
security definer
set search_path = public
as $$
begin
 return query
 update public.file_transfers t
 set expires_at=t.expires_at
 where t.direction='outgoing'
   and t.download_code=upper(trim(p_code))
   and t.expires_at > now()
 returning t.file_path,t.file_name;
end;
$$;
revoke all on function public.lookup_file_by_code(text) from public;
grant execute on function public.lookup_file_by_code(text) to anon, authenticated;
