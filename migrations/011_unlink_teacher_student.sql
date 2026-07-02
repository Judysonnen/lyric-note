-- LyricNote · Migration 011
-- Allow either side (teacher or student) to unilaterally unlink.
-- Silent for the other side: we just delete the row; their UI recomputes.
-- Teacher's songs / homework rows stay in their own account (only the
-- cross-visibility via teacher_student goes away).

create or replace function public.unlink_teacher_student(row_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    t_id uuid;
    s_id uuid;
begin
    select teacher_id, student_id
      into t_id, s_id
      from public.teacher_student
     where id = row_id;
    if t_id is null then
        raise exception 'link_not_found' using errcode = 'P0001';
    end if;
    if auth.uid() <> t_id and auth.uid() <> coalesce(s_id, '00000000-0000-0000-0000-000000000000'::uuid) then
        raise exception 'not_authorized' using errcode = 'P0001';
    end if;
    delete from public.teacher_student where id = row_id;
end;
$$;

grant execute on function public.unlink_teacher_student(uuid) to authenticated;

-- Convenience for the student side: they only know teacher_id.
create or replace function public.unlink_teacher_as_student(t_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    delete from public.teacher_student
     where teacher_id = t_id and student_id = auth.uid();
end;
$$;

grant execute on function public.unlink_teacher_as_student(uuid) to authenticated;
