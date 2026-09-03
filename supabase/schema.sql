-- Dawn — Supabase setup
--
-- Run this once in the SQL editor of your Supabase project.
-- It creates the profile table Dawn writes to, locks it down with RLS, and
-- adds the `delete_account` function the app calls from the Account screen.

-- 1. Profiles ---------------------------------------------------------------

create table if not exists public.profiles (
    id          uuid primary key references auth.users (id) on delete cascade,
    email       text,
    full_name   text,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- A user can only ever see or touch their own row.
drop policy if exists "profiles are self-service" on public.profiles;
create policy "profiles are self-service"
    on public.profiles
    for all
    using (auth.uid() = id)
    with check (auth.uid() = id);

-- 2. Create a profile automatically on sign-up ------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id, email, full_name)
    values (
        new.id,
        new.email,
        new.raw_user_meta_data ->> 'full_name'
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row
    execute function public.handle_new_user();

-- 3. Account deletion -------------------------------------------------------
--
-- The client SDK cannot delete an auth user — that needs the service role key,
-- which must never ship inside an app. This function runs as its owner and
-- deletes only the *caller's* row, so an authenticated user can remove
-- themselves and nobody else.
--
-- Apple requires in-app account deletion for any app that offers account
-- creation (App Review Guideline 5.1.1(v)), so this is not optional.

create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
begin
    if caller is null then
        raise exception 'Not authenticated';
    end if;

    delete from public.profiles where id = caller;
    delete from auth.users where id = caller;
end;
$$;

revoke all on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

-- 4. Encrypted journal backup ----------------------------------------------
--
-- Everything below stores CIPHERTEXT ONLY. The server never sees a key, and
-- neither do we: the data encryption key (DEK) is generated on-device and is
-- uploaded only after being wrapped with a key derived from the user's
-- recovery code, which never leaves their phone.
--
-- That means a lost recovery code on a device with no keychain copy is
-- unrecoverable. That is the point of the design, not a bug in it, and the
-- recovery-code screen has to say so plainly.

-- 4a. The wrapped data key --------------------------------------------------

create table if not exists public.encryption_keys (
    user_id     uuid primary key references auth.users (id) on delete cascade,
    -- base64 AES-GCM box: the DEK, sealed under the recovery-code key.
    wrapped_dek text not null,
    -- base64 salt for the HKDF step. Random per user.
    kdf_salt    text not null,
    kdf         text not null default 'hkdf-sha256',
    version     int  not null default 1,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

alter table public.encryption_keys enable row level security;

drop policy if exists "keys are self-service" on public.encryption_keys;
create policy "keys are self-service"
    on public.encryption_keys
    for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- 4b. The entries themselves ------------------------------------------------
--
-- One row per user per day, matching the app's one-entry-per-day rule so the
-- primary key can do the deduplication for us.
--
-- `day` is deliberately left in the clear: it is the sync key, and without it
-- the client would have to download and decrypt everything to find one entry.
-- The tradeoff is that the server learns WHICH DAYS a user wrote, but never a
-- single word of WHAT they wrote. Mood, prompts and text all live inside the
-- ciphertext blob.

create table if not exists public.journal_entries (
    user_id     uuid not null references auth.users (id) on delete cascade,
    day         date not null,
    -- base64 AES-GCM box: nonce + ciphertext + tag, sealed under the DEK.
    ciphertext  text not null,
    -- Bumped by the client on every write; drives last-write-wins on sync.
    updated_at  timestamptz not null default now(),
    primary key (user_id, day)
);

alter table public.journal_entries enable row level security;

drop policy if exists "entries are self-service" on public.journal_entries;
create policy "entries are self-service"
    on public.journal_entries
    for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create index if not exists journal_entries_sync_idx
    on public.journal_entries (user_id, updated_at desc);

-- 4c. Fold the new tables into account deletion -----------------------------
--
-- The cascade from auth.users already covers these, but deleting them first
-- keeps the function honest about everything it removes.

create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
begin
    if caller is null then
        raise exception 'Not authenticated';
    end if;

    delete from public.journal_entries where user_id = caller;
    delete from public.encryption_keys  where user_id = caller;
    delete from public.profiles         where id = caller;
    delete from auth.users              where id = caller;
end;
$$;

revoke all on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

-- 5. Encrypted settings backup ----------------------------------------------
--
-- Prompts and preferences, in one encrypted blob. Ciphertext only, same as
-- entries: a reworded prompt is as personal as the answer to it.
--
-- One row per user rather than one per prompt. They're small, they're always
-- read and written together, and there is no reason to let the server learn
-- how many prompts someone keeps.

create table if not exists public.user_settings (
    user_id     uuid primary key references auth.users (id) on delete cascade,
    ciphertext  text not null,
    updated_at  timestamptz not null default now()
);

alter table public.user_settings enable row level security;

drop policy if exists "settings are self-service" on public.user_settings;
create policy "settings are self-service"
    on public.user_settings
    for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Fold into account deletion alongside the rest.
create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
begin
    if caller is null then
        raise exception 'Not authenticated';
    end if;

    delete from public.journal_entries where user_id = caller;
    delete from public.user_settings   where user_id = caller;
    delete from public.encryption_keys where user_id = caller;
    delete from public.profiles        where id = caller;
    delete from auth.users             where id = caller;
end;
$$;

revoke all on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
