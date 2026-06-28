-- LyricNote · Migration 005
-- Fix ambiguous `project_id` reference inside join_project_by_token
-- (was clashing with the RETURNS TABLE column of the same name).

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
    select p.id, p.user_id, coalesce(p.data->>'name', p.data->>'songTitle', '未命名')
      into p_id, p_owner, p_name
      from public.projects p
     where p.share_token = token
     limit 1;

    if p_id is null then
        raise exception 'invalid_token' using errcode = 'P0001';
    end if;

    if auth.uid() = p_owner then
        return query select p_id, p_name, true;
        return;
    end if;

    select pc.id into existing_id
      from public.project_collaborators pc
     where pc.project_id = p_id and pc.user_id = auth.uid()
     limit 1;

    if existing_id is not null then
        return query select p_id, p_name, true;
        return;
    end if;

    insert into public.project_collaborators (project_id, user_id, role)
    values (p_id, auth.uid(), 'editor');

    return query select p_id, p_name, false;
end;
$$;

grant execute on function public.join_project_by_token(text) to authenticated;
