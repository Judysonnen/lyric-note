-- LyricNote · Migration 016
-- v3 renamed several stamp codes to their tiered equivalents. Existing rows
-- from v1/v2 still live in the table but the new client renderer keys off
-- the new codes, so those rows visually vanished. This migration renames
-- them in place so they show up again.

-- One-off codes → their tiered replacements at tier 1
update public.stamps set stamp_code = 'full_house' where stamp_code = 'full_house_1';
update public.stamps set stamp_code = 'new_song'   where stamp_code = 'new_song_1';
update public.stamps set stamp_code = 'week_full'  where stamp_code = 'week_full_1';
update public.stamps set stamp_code = 'month_full' where stamp_code = 'month_full_1';
update public.stamps set stamp_code = 'weekend'    where stamp_code = 'weekend_1';
update public.stamps set stamp_code = 'early_bird' where stamp_code = 'early_bird_5';
update public.stamps set stamp_code = 'night_owl'  where stamp_code = 'night_owl_5';
update public.stamps set stamp_code = 'both_time'  where stamp_code = 'both_time_3';

-- comeback_3 was a distinct "3 comebacks" stamp in v2; in v3 that maps to
-- tier 2 of the tiered comeback stamp. Promote the tier so it doesn't
-- collide with any existing (user, 'comeback', 1) row.
update public.stamps set stamp_code = 'comeback', tier = 2 where stamp_code = 'comeback_3';

-- week_streak_4 became tier 2 of the tiered week_full stamp. Same treatment.
update public.stamps set stamp_code = 'week_full', tier = 2 where stamp_code = 'week_streak_4';
