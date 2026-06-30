-- LyricNote · Migration 007
-- Per-student linking. A teacher invites a real student account once;
-- afterwards all of the teacher's projects under that student-name are
-- automatically visible (and editable) to the linked student.
-- Student's own projects stay private unless they separately share them.

-- ─────────────────────────────────────────
-- 1. teacher_student table
-- ─────────────────────────────────────────
create table if not exists public.teacher_student (
    id            uuid primary key default gen_random_uuid(),
    teacher_id    uuid not null references auth.users(id) on delete cascade,
    student_label text not null,                    -- the studentName the teacher writes on projects
    invite_token  text unique,                      -- generated when teacher wants to invite
    student_id    uuid references auth.users(id) on delete cascade, -- filled in when student claims
    joined_at     timestamptz,
    created_at    timestamptz default now(),
    unique (teacher_id, student_label)
);

create index if not exists ts_teacher_idx   on public.teacher_student(teacher_id);
create index if not exists ts_student_idx   on public.teacher_student(student_id);
create index if not exists ts_invite_idx    on public.teacher_student(invite_token);

alter table public.teacher_student enable row level security;

drop policy if exists "ts teacher all"  on public.teacher_student;
create policy "ts teacher all" on public.teacher_student
    for all using (teacher_id = auth.uid()) with check (teacher_id = auth.uid());

drop policy if exists "ts student read" on public.teacher_student;
create policy "ts student read" on public.teacher_student
    for select using (student_id = auth.uid());

-- ─────────────────────────────────────────
-- 2. Extend projects RLS — student can read/update projects where they are linked under matching label
-- (Coexists with existing owner + per-project collaborator policies.)
-- ─────────────────────────────────────────
drop policy if exists "projects student linked select" on public.projects;
create policy "projects student linked select" on public.projects
    for select using (
        exists (
            select 1 from public.teacher_student ts
            where ts.teacher_id = projects.user_id
              and ts.student_id = auth.uid()
              and lower(trim(ts.student_label)) = lower(trim(coalesce(projects.data->>'studentName', '')))
        )
    );

drop policy if exists "projects student linked update" on public.projects;
create policy "projects student linked update" on public.projects
    for update using (
        exists (
            select 1 from public.teacher_student ts
            where ts.teacher_id = projects.user_id
              and ts.student_id = auth.uid()
              and lower(trim(ts.student_label)) = lower(trim(coalesce(projects.data->>'studentName', '')))
        )
    ) with check (
        exists (
            select 1 from public.teacher_student ts
            where ts.teacher_id = projects.user_id
              and ts.student_id = auth.uid()
              and lower(trim(ts.student_label)) = lower(trim(coalesce(projects.data->>'studentName', '')))
        )
    );

-- ─────────────────────────────────────────
-- 3. RPC: gen_or_get_student_invite(label) — teacher calls
-- Idempotent: returns existing token if one exists, otherwise creates row + token.
-- ─────────────────────────────────────────
create or replace function public.gen_or_get_student_invite(label text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    row_id uuid;
    tok    text;
begin
    if label is null or btrim(label) = '' then
        raise exception 'empty_label';
    end if;
    select id, invite_token into row_id, tok
      from public.teacher_student
     where teacher_id = auth.uid() and lower(trim(student_label)) = lower(trim(label))
     limit 1;
    if row_id is null then
        tok := encode(gen_random_bytes(12), 'hex');
        insert into public.teacher_student (teacher_id, student_label, invite_token)
        values (auth.uid(), label, tok);
        return tok;
    end if;
    if tok is null then
        tok := encode(gen_random_bytes(12), 'hex');
        update public.teacher_student set invite_token = tok where id = row_id;
    end if;
    return tok;
end;
$$;

grant execute on function public.gen_or_get_student_invite(text) to authenticated;

-- ─────────────────────────────────────────
-- 4. RPC: claim_student_invite(token) — student calls after registering
-- Sets student_id + joined_at. Returns teacher_id + student_label.
-- ─────────────────────────────────────────
create or replace function public.claim_student_invite(token text)
returns table(teacher_id uuid, student_label text, already_claimed boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
    row_id   uuid;
    t_id     uuid;
    s_label  text;
    s_id     uuid;
begin
    select ts.id, ts.teacher_id, ts.student_label, ts.student_id
      into row_id, t_id, s_label, s_id
      from public.teacher_student ts
     where ts.invite_token = token
     limit 1;
    if row_id is null then
        raise exception 'invalid_token' using errcode = 'P0001';
    end if;
    if s_id is not null then
        if s_id = auth.uid() then
            return query select t_id, s_label, true;
            return;
        end if;
        raise exception 'already_claimed_by_other' using errcode = 'P0001';
    end if;
    update public.teacher_student
       set student_id = auth.uid(), joined_at = now()
     where id = row_id;
    return query select t_id, s_label, false;
end;
$$;

grant execute on function public.claim_student_invite(text) to authenticated;

-- ─────────────────────────────────────────
-- 5. Realtime
-- ─────────────────────────────────────────
alter publication supabase_realtime add table public.teacher_student;
