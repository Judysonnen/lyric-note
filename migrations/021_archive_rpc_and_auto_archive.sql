-- LyricNote · Migration 021
-- Shift archive as source of truth from homework.archived_at to
-- homework_batches.archived_at, and add a single atomic RPC that creates a
-- new batch + its homework rows and auto-archives the student's previous
-- unarchived batches in one transaction. This is how "上完课布置下一组"
-- automatically closes the last group.

-- ── rewrite archive/unarchive to hit batches ────────────────────
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
    update public.homework_batches
       set archived_at = now()
     where id = batch
       and teacher_id = auth.uid()
       and archived_at is null;
    get diagnostics n = row_count;
    return n;
end;
$$;

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
    update public.homework_batches
       set archived_at = null
     where id = batch
       and teacher_id = auth.uid();
    get diagnostics n = row_count;
    return n;
end;
$$;

grant execute on function public.archive_homework_batch(uuid) to authenticated;
grant execute on function public.unarchive_homework_batch(uuid) to authenticated;

-- ── create batch + rows, auto-archive previous ──────────────────
-- p_batch is the batch row (id, student_id, label, start_date, end_date,
-- copied_from_batch_id). p_rows is an array of homework row payloads
-- (title, description, daily_minutes, parent_homework_id, version). All
-- created rows share the new batch_id and inherit teacher_id from auth.uid().
create or replace function public.create_batch_and_archive_prev(
    p_batch jsonb,
    p_rows  jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_batch_id           uuid;
    v_student_id         uuid;
    v_teacher_id         uuid := auth.uid();
    v_label              text;
    v_start              date;
    v_end                date;
    v_copied_from        uuid;
    v_row                jsonb;
    v_archived_count     integer;
begin
    if v_teacher_id is null then
        raise exception 'not_authenticated';
    end if;

    v_batch_id    := coalesce((p_batch->>'id')::uuid, gen_random_uuid());
    v_student_id  := (p_batch->>'student_id')::uuid;
    v_label       := nullif(p_batch->>'label', '');
    v_start       := (p_batch->>'start_date')::date;
    v_end         := (p_batch->>'end_date')::date;
    v_copied_from := nullif(p_batch->>'copied_from_batch_id', '')::uuid;

    if v_student_id is null or v_start is null or v_end is null then
        raise exception 'bad_batch_payload';
    end if;

    -- Auto-archive every previous unarchived batch this teacher has for this
    -- student. This is the "上完课，布置下一组，上一组自动进归档" behavior.
    update public.homework_batches
       set archived_at = now()
     where teacher_id = v_teacher_id
       and student_id = v_student_id
       and archived_at is null;
    get diagnostics v_archived_count = row_count;

    insert into public.homework_batches
        (id, teacher_id, student_id, label, start_date, end_date, copied_from_batch_id)
    values
        (v_batch_id, v_teacher_id, v_student_id, v_label, v_start, v_end, v_copied_from);

    -- Insert every homework row from the payload attached to the new batch.
    for v_row in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
    loop
        insert into public.homework
            (teacher_id, student_id, title, description, start_date, end_date,
             daily_minutes, batch_id, parent_homework_id, version)
        values (
            v_teacher_id,
            v_student_id,
            coalesce(v_row->>'title', ''),
            nullif(v_row->>'description', ''),
            v_start,
            v_end,
            nullif(v_row->>'daily_minutes', '')::int,
            v_batch_id,
            nullif(v_row->>'parent_homework_id', '')::uuid,
            coalesce(nullif(v_row->>'version', '')::int, 1)
        );
    end loop;

    return v_batch_id;
end;
$$;

grant execute on function public.create_batch_and_archive_prev(jsonb, jsonb) to authenticated;

-- ── mark_homework_mastery: one-call verdict setter ──────────────
-- Lets the teacher flip a homework row's mastery_state and optionally
-- attach a short note. Runs security definer so RLS on the join table
-- (teacher owns the row) is the check.
create or replace function public.mark_homework_mastery(
    p_homework_id uuid,
    p_state       text,
    p_note        text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if p_state not in ('active', 'mastered', 'keep_practicing') then
        raise exception 'bad_state';
    end if;
    update public.homework
       set mastery_state     = p_state,
           mastery_marked_at = case when p_state = 'active' then null else now() end,
           mastery_note      = nullif(p_note, '')
     where id = p_homework_id
       and teacher_id = auth.uid();
end;
$$;

grant execute on function public.mark_homework_mastery(uuid, text, text) to authenticated;
