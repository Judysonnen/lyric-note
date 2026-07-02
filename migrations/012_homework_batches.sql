-- LyricNote · Migration 012
-- Group homework rows submitted together (batch_id) and support archiving
-- an entire batch even if not all check-ins are done.

alter table public.homework
    add column if not exists batch_id uuid,
    add column if not exists archived_at timestamptz;

create index if not exists idx_homework_batch on public.homework(batch_id);
create index if not exists idx_homework_archived on public.homework(archived_at);

-- Archive all homework rows in a batch. Only the teacher who owns them
-- can archive. Idempotent: re-archiving is a no-op timestamp refresh.
create or replace function public.archive_homework_batch(batch uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    n integer;
begin
    if batch is null then
        raise exception 'missing_batch';
    end if;
    update public.homework
       set archived_at = now()
     where batch_id = batch
       and teacher_id = auth.uid();
    get diagnostics n = row_count;
    return n;
end;
$$;

grant execute on function public.archive_homework_batch(uuid) to authenticated;

-- Undo archive: reset archived_at back to null.
create or replace function public.unarchive_homework_batch(batch uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    n integer;
begin
    if batch is null then
        raise exception 'missing_batch';
    end if;
    update public.homework
       set archived_at = null
     where batch_id = batch
       and teacher_id = auth.uid();
    get diagnostics n = row_count;
    return n;
end;
$$;

grant execute on function public.unarchive_homework_batch(uuid) to authenticated;
