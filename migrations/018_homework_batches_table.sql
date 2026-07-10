-- LyricNote · Migration 018
-- Promote homework batches from "just a client-generated UUID on each homework
-- row" into a real table so we can attach a label, a shared time period, a
-- copied-from link, and a single archive timestamp. Backfill from existing
-- homework rows so nothing already assigned goes missing.

-- ── homework_batches table ──────────────────────────────────────
create table if not exists public.homework_batches (
    id                     uuid primary key,
    teacher_id             uuid not null references auth.users(id) on delete cascade,
    student_id             uuid not null references auth.users(id) on delete cascade,
    -- label is what the teacher sees in listings. Null / empty means
    -- "auto-render from start_date and end_date on the client".
    label                  text,
    start_date             date not null,
    end_date               date not null,
    archived_at            timestamptz,
    copied_from_batch_id   uuid references public.homework_batches(id) on delete set null,
    created_at             timestamptz not null default now()
);

create index if not exists hwb_teacher_idx  on public.homework_batches(teacher_id);
create index if not exists hwb_student_idx  on public.homework_batches(student_id);
create index if not exists hwb_archived_idx on public.homework_batches(archived_at);

alter table public.homework_batches enable row level security;

drop policy if exists "hwb teacher all" on public.homework_batches;
create policy "hwb teacher all" on public.homework_batches
    for all using (teacher_id = auth.uid()) with check (teacher_id = auth.uid());

drop policy if exists "hwb student read" on public.homework_batches;
create policy "hwb student read" on public.homework_batches
    for select using (student_id = auth.uid());

alter publication supabase_realtime add table public.homework_batches;

-- ── backfill from existing homework rows ────────────────────────
-- Every distinct batch_id in homework becomes one homework_batches row. Label
-- stays null on purpose so the client renders the auto date-range label; if
-- the teacher later customizes it we save the override into label.
-- archived_at is set only if *every* row in the batch was already archived
-- (the previous per-row model), so a batch with mixed rows stays active.
insert into public.homework_batches
    (id, teacher_id, student_id, label, start_date, end_date, archived_at, created_at)
select
    h.batch_id,
    h.teacher_id,
    h.student_id,
    null,
    min(h.start_date),
    max(h.end_date),
    case when bool_and(h.archived_at is not null) then max(h.archived_at) else null end,
    min(h.created_at)
from public.homework h
where h.batch_id is not null
group by h.batch_id, h.teacher_id, h.student_id
on conflict (id) do nothing;

-- ── add FK on homework.batch_id ─────────────────────────────────
-- Now that every non-null batch_id has a matching batches row, we can promote
-- the column into a proper FK. Keep on delete cascade so removing a batch
-- also nukes its homework rows (matches how the UI treats a batch as the unit).
do $$
begin
    if not exists (
        select 1 from pg_constraint where conname = 'homework_batch_id_fkey'
    ) then
        alter table public.homework
            add constraint homework_batch_id_fkey
            foreign key (batch_id)
            references public.homework_batches(id)
            on delete cascade;
    end if;
end $$;
