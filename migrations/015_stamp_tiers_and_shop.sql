-- LyricNote · Migration 015
-- Extend the stamps system to support multi-tier stamps (each stamp can be
-- earned repeatedly at higher tiers), a manual-claim step that awards 宝
-- (the in-app currency), and a 印肆 shop where users spend 宝 to unlock
-- decorative items. Folds in the teacher-read policy from planned 014 so
-- everything ships together.

-- ── stamps table upgrade ─────────────────────────────────────────
-- Previously a stamp was uniquely (user_id, stamp_code). Now every tier
-- earns its own row. Existing rows are treated as tier 1 already claimed.
alter table public.stamps
    drop constraint if exists stamps_user_id_stamp_code_key;
alter table public.stamps
    add column if not exists tier int not null default 1,
    add column if not exists claimed_at timestamptz,
    add column if not exists xp_earned int not null default 0;

-- Treat every row that existed before this migration as already claimed with
-- zero payout: pre-tier stamps have no meaningful 宝 attached, and forcing
-- users to click through a chain of empty claims would be pointless.
update public.stamps
   set claimed_at = coalesce(claimed_at, awarded_at)
 where claimed_at is null;

do $$
begin
    if not exists (
        select 1 from pg_constraint where conname = 'stamps_user_stamp_tier_uniq'
    ) then
        alter table public.stamps
            add constraint stamps_user_stamp_tier_uniq unique (user_id, stamp_code, tier);
    end if;
end $$;

create index if not exists stamps_unclaimed_idx
    on public.stamps(user_id)
 where claimed_at is null;

-- Teacher-read policy (was planned as 014, folded here so this migration is
-- self-contained). A teacher can select stamps for any student she's linked to.
drop policy if exists "stamps teacher read linked" on public.stamps;
create policy "stamps teacher read linked" on public.stamps
    for select using (
        exists (
            select 1 from public.teacher_student ts
             where ts.teacher_id = auth.uid()
               and ts.student_id = stamps.user_id
        )
    );

-- ── shop_purchases table ─────────────────────────────────────────
create table if not exists public.shop_purchases (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null references auth.users(id) on delete cascade,
    item_code    text not null,
    cost         int not null,
    purchased_at timestamptz not null default now(),
    meta         jsonb not null default '{}'::jsonb,
    unique (user_id, item_code)
);

create index if not exists shop_purchases_user_idx on public.shop_purchases(user_id);

alter table public.shop_purchases enable row level security;

drop policy if exists "shop_purchases owner all" on public.shop_purchases;
create policy "shop_purchases owner all" on public.shop_purchases
    for all using (user_id = auth.uid()) with check (user_id = auth.uid());
