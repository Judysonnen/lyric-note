-- LyricNote · Migration 019
-- Two per-homework-row concepts: mastery (teacher's per-item verdict) and
-- versioning (a homework item that's a tweaked continuation of a previous
-- one, so "副歌高音处理 v2" links back to v1).

alter table public.homework
    add column if not exists mastery_state      text        not null default 'active',
    add column if not exists mastery_marked_at  timestamptz,
    add column if not exists mastery_note       text,
    add column if not exists parent_homework_id uuid        references public.homework(id) on delete set null,
    add column if not exists version            int         not null default 1;

do $$
begin
    if not exists (
        select 1 from pg_constraint where conname = 'homework_mastery_state_check'
    ) then
        alter table public.homework
            add constraint homework_mastery_state_check
            check (mastery_state in ('active', 'mastered', 'keep_practicing'));
    end if;
end $$;

create index if not exists homework_mastery_idx
    on public.homework(student_id, mastery_state);

create index if not exists homework_parent_idx
    on public.homework(parent_homework_id)
    where parent_homework_id is not null;
