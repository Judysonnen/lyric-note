-- LyricNote · Migration 006
-- Homework / daily check-in / audio submissions / teacher comments.
-- A "student" of a teacher = a user who is a collaborator on any project that teacher owns.

-- ─────────────────────────────────────────
-- 1. homework table
-- ─────────────────────────────────────────
create table if not exists public.homework (
    id          uuid primary key default gen_random_uuid(),
    teacher_id  uuid not null references auth.users(id) on delete cascade,
    student_id  uuid not null references auth.users(id) on delete cascade,
    title       text not null,
    description text,
    start_date  date not null,
    end_date    date not null,
    created_at  timestamptz default now()
);

create index if not exists homework_teacher_idx on public.homework(teacher_id);
create index if not exists homework_student_idx on public.homework(student_id);

alter table public.homework enable row level security;

drop policy if exists "hw teacher all" on public.homework;
create policy "hw teacher all" on public.homework
    for all using (teacher_id = auth.uid()) with check (teacher_id = auth.uid());

drop policy if exists "hw student read" on public.homework;
create policy "hw student read" on public.homework
    for select using (student_id = auth.uid());

-- ─────────────────────────────────────────
-- 2. homework_check table (one row per day per homework)
-- ─────────────────────────────────────────
create table if not exists public.homework_check (
    id              uuid primary key default gen_random_uuid(),
    homework_id     uuid not null references public.homework(id) on delete cascade,
    check_date      date not null,
    completed       boolean default false,
    student_note    text,
    audio_path      text,
    teacher_comment text,
    completed_at    timestamptz,
    updated_at      timestamptz default now(),
    unique (homework_id, check_date)
);

create index if not exists hwc_homework_idx on public.homework_check(homework_id);

alter table public.homework_check enable row level security;

-- Student: full CRUD on her own check-ins (via homework.student_id)
drop policy if exists "hwc student all" on public.homework_check;
create policy "hwc student all" on public.homework_check
    for all using (
        exists (select 1 from public.homework h
                where h.id = homework_check.homework_id and h.student_id = auth.uid())
    ) with check (
        exists (select 1 from public.homework h
                where h.id = homework_check.homework_id and h.student_id = auth.uid())
    );

-- Teacher: full CRUD (for comments + visibility)
drop policy if exists "hwc teacher all" on public.homework_check;
create policy "hwc teacher all" on public.homework_check
    for all using (
        exists (select 1 from public.homework h
                where h.id = homework_check.homework_id and h.teacher_id = auth.uid())
    ) with check (
        exists (select 1 from public.homework h
                where h.id = homework_check.homework_id and h.teacher_id = auth.uid())
    );

-- ─────────────────────────────────────────
-- 3. Storage bucket for audio
-- ─────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('homework-audio', 'homework-audio', false)
on conflict (id) do nothing;

-- Any authenticated user can read/write/delete in this bucket; finer-grained
-- access is enforced at the application layer (we store paths in
-- homework_check, and only the rightful student/teacher can see the row).
drop policy if exists "hwa read"   on storage.objects;
drop policy if exists "hwa upload" on storage.objects;
drop policy if exists "hwa update" on storage.objects;
drop policy if exists "hwa delete" on storage.objects;

create policy "hwa read"   on storage.objects for select using (bucket_id = 'homework-audio' and auth.uid() is not null);
create policy "hwa upload" on storage.objects for insert with check (bucket_id = 'homework-audio' and auth.uid() is not null);
create policy "hwa update" on storage.objects for update using (bucket_id = 'homework-audio' and auth.uid() is not null);
create policy "hwa delete" on storage.objects for delete using (bucket_id = 'homework-audio' and auth.uid() is not null);

-- ─────────────────────────────────────────
-- 4. Realtime so check-offs sync
-- ─────────────────────────────────────────
alter publication supabase_realtime add table public.homework;
alter publication supabase_realtime add table public.homework_check;

-- ─────────────────────────────────────────
-- 5. RPC: list_my_students()
-- Returns the user_ids who are collaborators on any of my owned projects.
-- ─────────────────────────────────────────
create or replace function public.list_my_students()
returns table(student_id uuid)
language sql
security definer
set search_path = public
as $$
    select distinct c.user_id
      from public.project_collaborators c
      join public.projects p on p.id = c.project_id
     where p.user_id = auth.uid() and c.user_id <> auth.uid();
$$;

grant execute on function public.list_my_students() to authenticated;

-- ─────────────────────────────────────────
-- 6. RPC: lookup_username_by_id(uuid) — best-effort label for display
-- We synthesize emails as <name>@lyricnote.app (or u_<hex>@lyricnote.app for
-- non-ASCII names) on signup, so we can decode them here.
-- ─────────────────────────────────────────
create or replace function public.lookup_username_by_id(uid uuid)
returns text
language sql
security definer
set search_path = public, auth
as $$
    select coalesce(
        regexp_replace(au.email, '@lyricnote\.app$', ''),
        au.email
    )
      from auth.users au
     where au.id = uid;
$$;

grant execute on function public.lookup_username_by_id(uuid) to authenticated;
