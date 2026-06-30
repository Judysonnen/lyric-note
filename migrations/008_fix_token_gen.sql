-- LyricNote · Migration 008
-- Replace gen_random_bytes (pgcrypto) with a md5-based token so we don't
-- depend on the extension.

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
        tok := substr(md5(random()::text || clock_timestamp()::text || auth.uid()::text || label), 1, 24);
        insert into public.teacher_student (teacher_id, student_label, invite_token)
        values (auth.uid(), label, tok);
        return tok;
    end if;
    if tok is null then
        tok := substr(md5(random()::text || clock_timestamp()::text || auth.uid()::text || label), 1, 24);
        update public.teacher_student set invite_token = tok where id = row_id;
    end if;
    return tok;
end;
$$;

grant execute on function public.gen_or_get_student_invite(text) to authenticated;
