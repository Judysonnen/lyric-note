-- LyricNote · Migration 003
-- Per-project sharing: owner generates a share token; anyone with token can join as editor.
-- Run after 001 + 002 (or standalone — only depends on `projects` table).

-- ─────────────────────────────────────────
-- 0. Clean up any half-created state from a failed prior run
-- ─────────────────────────────────────────
drop function if exists public.join_project_by_token(text);
drop table if exists public.project_collaborators cascade;

-- ─────────────────────────────────────────
-- 1. share_token on projects
-- ─────────────────────────────────────────
alter table public.projects
    add column if not exists share_token text unique;

create index if not exists projects_share_token_idx on public.projects(share_token);

-- ─────────────────────────────────────────
-- 2. project_collaborators table
-- ─────────────────────────────────────────
create table if not exists public.project_collaborators (
    id          uuid primary key default gen_random_uuid(),
    project_id  text not null references public.projects(id) on delete cascade,
    user_id     uuid not null references auth.users(id)       on delete cascade,
    role        text not null default 'editor' check (role in ('editor', 'viewer')),
    joined_at   timestamptz default now(),
    unique (project_id, user_id)
);

create index if not exists project_collab_user_idx    on public.project_collaborators(user_id);
create index if not exists project_collab_project_idx on public.project_collaborators(project_id);

alter table public.project_collaborators enable row level security;

-- Members can read their own collaborator row
drop policy if exists "collab self read" on public.project_collaborators;
create policy "collab self read" on public.project_collaborators
    for select using (user_id = auth.uid());

-- (Owner-side collaborator listing / removal goes through RPCs to avoid RLS recursion with projects)
drop policy if exists "collab owner read"   on public.project_collaborators;
drop policy if exists "collab owner delete" on public.project_collaborators;

-- Collaborator can leave themselves
drop policy if exists "collab self delete" on public.project_collaborators;
create policy "collab self delete" on public.project_collaborators
    for delete using (user_id = auth.uid());

-- Note: INSERT goes through the join_project_by_token RPC (security definer)

-- ─────────────────────────────────────────
-- 3. Update projects RLS so collaborators can read + write
-- ─────────────────────────────────────────
drop policy if exists "projects owner all"   on public.projects;
drop policy if exists "projects member read" on public.projects;
drop policy if exists "projects student read" on public.projects;
drop policy if exists "projects owner select" on public.projects;
drop policy if exists "projects owner update" on public.projects;
drop policy if exists "projects owner insert" on public.projects;
drop policy if exists "projects owner delete" on public.projects;
drop policy if exists "projects collab select" on public.projects;
drop policy if exists "projects collab update" on public.projects;

-- Owner can do everything on their projects
create policy "projects owner all" on public.projects
    for all using (user_id = auth.uid())
    with check  (user_id = auth.uid());

-- Collaborator can SELECT shared project
create policy "projects collab select" on public.projects
    for select using (
        exists (select 1 from public.project_collaborators c
                where c.project_id = projects.id and c.user_id = auth.uid())
    );

-- Collaborator can UPDATE shared project (editor role)
create policy "projects collab update" on public.projects
    for update using (
        exists (select 1 from public.project_collaborators c
                where c.project_id = projects.id and c.user_id = auth.uid() and c.role = 'editor')
    )
    with check (
        exists (select 1 from public.project_collaborators c
                where c.project_id = projects.id and c.user_id = auth.uid() and c.role = 'editor')
    );

-- (Collaborators cannot DELETE — only owner can)

-- ─────────────────────────────────────────
-- 4. RPC: join_project_by_token(token)
-- Inserts current user as collaborator on the matching project.
-- Returns the project row so client can immediately show it.
-- ─────────────────────────────────────────
create or replace function public.join_project_by_token(token text)
returns table(project_id text, name text, already_member boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
    p_id   text;
    p_owner uuid;
    p_name text;
    existing_id uuid;
begin
    -- Find the project
    select id, user_id, coalesce(data->>'name', data->>'songTitle', '未命名')
      into p_id, p_owner, p_name
      from public.projects
     where share_token = token
     limit 1;

    if p_id is null then
        raise exception 'invalid_token' using errcode = 'P0001';
    end if;

    -- If current user IS the owner, no-op
    if auth.uid() = p_owner then
        return query select p_id, p_name, true;
        return;
    end if;

    -- Check if already a collaborator
    select id into existing_id
      from public.project_collaborators
     where project_id = p_id and user_id = auth.uid()
     limit 1;

    if existing_id is not null then
        return query select p_id, p_name, true;
        return;
    end if;

    -- Insert as editor
    insert into public.project_collaborators (project_id, user_id, role)
    values (p_id, auth.uid(), 'editor');

    return query select p_id, p_name, false;
end;
$$;

grant execute on function public.join_project_by_token(text) to authenticated;
