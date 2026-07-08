-- LyricNote · Migration 013
-- Practice stamps (印章): the seal-album reward system. Each row records
-- one earned stamp for a user. Stamp catalog + trigger rules live in the
-- client (JS constant); the DB just stores what was earned and when.

create table if not exists public.stamps (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null references auth.users(id) on delete cascade,
    stamp_code   text not null,
    awarded_at   timestamptz not null default now(),
    -- Optional context: which homework/song triggered it, a teacher's note, etc.
    meta         jsonb not null default '{}'::jsonb,
    unique (user_id, stamp_code)
);

create index if not exists stamps_user_idx on public.stamps(user_id, awarded_at desc);

alter table public.stamps enable row level security;

-- A user reads and writes their own stamps. Teacher-gifted stamps come in v3
-- via a security-definer RPC; the simple RLS below is enough for v1.
drop policy if exists "stamps owner all" on public.stamps;
create policy "stamps owner all" on public.stamps
    for all using (user_id = auth.uid()) with check (user_id = auth.uid());
