-- LyricNote · Migration 004
-- Enable Postgres realtime on projects so subscribed clients receive UPDATE events.

alter publication supabase_realtime add table public.projects;
