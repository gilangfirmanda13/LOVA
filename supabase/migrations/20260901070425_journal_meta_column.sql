-- The app creates journal entries from 5 different flows (mood
-- check-in, emotion quiz, burnout check, obstacle report, free note),
-- each with its own extra fields (moodValues, summaryKey, question,
-- answer, pct...) beyond the common id/date/type/note/categories
-- shape. Rather than a column per flow, everything flow-specific
-- goes in `meta` and gets spread back onto the object on load.
alter table journal_entries add column meta jsonb not null default '{}';
