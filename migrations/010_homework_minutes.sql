-- LyricNote · Migration 010
-- Add optional "daily_minutes" hint for teacher to suggest practice time.

alter table public.homework
    add column if not exists daily_minutes integer;
