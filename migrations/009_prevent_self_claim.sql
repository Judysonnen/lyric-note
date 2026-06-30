-- LyricNote · Migration 009
-- Prevent a teacher from claiming their own student-invite link.
-- Also cleanup: undo any rows where teacher_id = student_id.

-- Clean up bad data
delete from public.teacher_student where student_id = teacher_id;

-- Fix RPC to reject self-claim
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
    if auth.uid() = t_id then
        raise exception 'cannot_self_claim' using errcode = 'P0001';
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
