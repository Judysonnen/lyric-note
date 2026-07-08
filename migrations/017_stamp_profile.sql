-- LyricNote · Migration 017
-- Store per-user 印谱 wardrobe choices: which paper skin to render, which
-- font family to use for seal glyphs, whether sound is on. One row per
-- user, upserted on change.

create table if not exists public.stamp_profile (
    user_id      uuid primary key references auth.users(id) on delete cascade,
    paper        text not null default 'default',   -- default | sangpi | saijin
    seal_font    text not null default 'song',      -- song | kaishu
    sound_on     boolean not null default true,
    updated_at   timestamptz not null default now()
);

alter table public.stamp_profile enable row level security;

drop policy if exists "stamp_profile owner all" on public.stamp_profile;
create policy "stamp_profile owner all" on public.stamp_profile
    for all using (user_id = auth.uid()) with check (user_id = auth.uid());
