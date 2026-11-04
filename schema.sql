create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create or replace view public.public_profiles
with (security_barrier = true)
as
select id, display_name
from public.profiles;

grant select on public.public_profiles to anon, authenticated;
revoke insert, update, delete on public.public_profiles from anon, authenticated;

create table if not exists public.listings (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles (id) on delete cascade,
  seller_name text not null,
  title text not null check (char_length(title) between 3 and 120),
  description text not null check (char_length(description) between 20 and 5000),
  price numeric(12, 2) not null check (price > 0),
  city text not null,
  category text not null check (category in (
    'Autos', 'Immobilien', 'Elektronik', 'Möbel', 'Mode', 'Jobs',
    'Freizeit', 'Haustiere', 'Haus & Garten'
  )),
  image_paths text[] not null default '{}',
  status text not null default 'active' check (status in ('active', 'paused', 'removed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists listings_active_created_idx
  on public.listings (created_at desc) where status = 'active';
create index if not exists listings_seller_idx on public.listings (seller_id);
create index if not exists listings_category_city_idx on public.listings (category, city);

create or replace function public.touch_listing_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_listing_updated on public.listings;
create trigger on_listing_updated
  before update on public.listings
  for each row execute procedure public.touch_listing_updated_at();

create table if not exists public.favorites (
  user_id uuid not null references public.profiles (id) on delete cascade,
  listing_id uuid not null references public.listings (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, listing_id)
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  listing_id uuid references public.listings (id) on delete set null,
  reported_user_id uuid references public.profiles (id) on delete set null,
  reason text not null,
  description text not null check (char_length(description) between 10 and 3000),
  status text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists reports_status_created_idx on public.reports (status, created_at desc);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  buyer_id uuid not null references public.profiles (id) on delete cascade,
  seller_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  constraint conversations_distinct_participants check (buyer_id <> seller_id),
  constraint conversations_one_buyer_per_listing unique (listing_id, buyer_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 5000),
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists messages_conversation_created_idx
  on public.messages (conversation_id, created_at);

create or replace function public.touch_conversation_after_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversations
  set last_message_at = new.created_at
  where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists on_message_created on public.messages;
create trigger on_message_created
  after insert on public.messages
  for each row execute procedure public.touch_conversation_after_message();

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and is_admin
  );
$$;

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(new.email, '@', 1))
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.create_profile_for_new_user();

alter table public.profiles enable row level security;
alter table public.listings enable row level security;
alter table public.favorites enable row level security;
alter table public.reports enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;

drop policy if exists "Profiles are visible to signed-in users" on public.profiles;
drop policy if exists "Users can view public profile names" on public.profiles;
create policy "Users can view public profile names"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists "Users can update their own profile" on public.profiles;

drop policy if exists "Active listings are public" on public.listings;
create policy "Active listings are public"
  on public.listings for select to anon, authenticated
  using (status = 'active' or seller_id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists "Signed-in users can create listings" on public.listings;
create policy "Signed-in users can create listings"
  on public.listings for insert to authenticated
  with check (seller_id = (select auth.uid()) and status = 'active');

drop policy if exists "Owners can update their listings" on public.listings;
create policy "Owners can update their listings"
  on public.listings for update to authenticated
  using (seller_id = (select auth.uid()) or (select public.is_admin()))
  with check (seller_id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists "Owners can delete their listings" on public.listings;
create policy "Owners can delete their listings"
  on public.listings for delete to authenticated
  using (seller_id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists "Users manage their own favorites" on public.favorites;
create policy "Users manage their own favorites"
  on public.favorites for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.listings l where l.id = listing_id and l.status = 'active')
  );

drop policy if exists "Users can submit reports" on public.reports;
create policy "Users can submit reports"
  on public.reports for insert to authenticated
  with check (
    reporter_id = (select auth.uid())
    and (reported_user_id is null or reported_user_id <> (select auth.uid()))
    and status = 'open'
  );

drop policy if exists "Users can view their reports and admins can moderate" on public.reports;
create policy "Users can view their reports and admins can moderate"
  on public.reports for select to authenticated
  using (reporter_id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists "Admins can moderate reports" on public.reports;
create policy "Admins can moderate reports"
  on public.reports for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

drop policy if exists "Participants can view conversations" on public.conversations;
create policy "Participants can view conversations"
  on public.conversations for select to authenticated
  using (
    buyer_id = (select auth.uid())
    or seller_id = (select auth.uid())
    or (select public.is_admin())
  );

drop policy if exists "Buyers can start conversations for active listings" on public.conversations;
create policy "Buyers can start conversations for active listings"
  on public.conversations for insert to authenticated
  with check (
    buyer_id = (select auth.uid())
    and buyer_id <> seller_id
    and exists (
      select 1 from public.listings l
      where l.id = listing_id and l.seller_id = seller_id and l.status = 'active'
    )
  );

drop policy if exists "Participants can view messages" on public.messages;
create policy "Participants can view messages"
  on public.messages for select to authenticated
  using (
    exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and ((select auth.uid()) in (c.buyer_id, c.seller_id) or (select public.is_admin()))
    )
  );

drop policy if exists "Participants can send messages" on public.messages;
create policy "Participants can send messages"
  on public.messages for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (select auth.uid()) in (c.buyer_id, c.seller_id)
    )
  );

revoke update on public.messages from authenticated;
grant update (read_at) on public.messages to authenticated;

drop policy if exists "Recipients can mark incoming messages as read" on public.messages;
create policy "Recipients can mark incoming messages as read"
  on public.messages for update to authenticated
  using (
    sender_id <> (select auth.uid())
    and exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (select auth.uid()) in (c.buyer_id, c.seller_id)
    )
  )
  with check (
    sender_id <> (select auth.uid())
    and exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (select auth.uid()) in (c.buyer_id, c.seller_id)
    )
  );

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('listing-images', 'listing-images', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Listing images are publicly readable" on storage.objects;
create policy "Listing images are publicly readable"
  on storage.objects for select to anon, authenticated
  using (bucket_id = 'listing-images');

drop policy if exists "Users upload images to their own folder" on storage.objects;
create policy "Users upload images to their own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'listing-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Users delete images from their own folder" on storage.objects;
create policy "Users delete images from their own folder"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'listing-images'
    and ((storage.foldername(name))[1] = (select auth.uid())::text or (select public.is_admin()))
  );
