-- LyricNote · Migration 020
-- Per-teacher reusable homework templates (e.g. "热身开嗓" / "打嘟基础").
-- When assigning homework the teacher picks templates and one-click adds them
-- into the new batch; the created homework row is independent of the template
-- afterwards (so deleting a template does not touch history).

create table if not exists public.homework_templates (
    id             uuid primary key default gen_random_uuid(),
    teacher_id     uuid not null references auth.users(id) on delete cascade,
    title          text not null,
    description    text,
    daily_minutes  int,
    category       text,
    sort_order     int  not null default 0,
    created_at     timestamptz not null default now()
);

create index if not exists hwt_teacher_idx on public.homework_templates(teacher_id, sort_order);

alter table public.homework_templates enable row level security;

drop policy if exists "hwt teacher all" on public.homework_templates;
create policy "hwt teacher all" on public.homework_templates
    for all using (teacher_id = auth.uid()) with check (teacher_id = auth.uid());
