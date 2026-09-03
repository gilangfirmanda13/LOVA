-- Fixes a real bug in profiles_name_no_html_chars (added in the previous
-- migration): the backslash character was silently NOT being caught.
-- Postgres's regex engine (ARE) treats a single literal backslash inside
-- a bracket expression as the start of an escape sequence for whatever
-- follows it, rather than as a literal character to match -- so
-- `[...\`]` (one backslash before the backtick) let backslash through.
-- It needs to appear DOUBLED in the actual pattern text to match one
-- literal backslash. Built via chr() concatenation instead of a
-- backslash-laden string literal, since going through a SQL string
-- literal (whose backslash handling depends on standard_conforming_strings)
-- is exactly what produced the wrong count last time -- verified this
-- exact pattern against all 6 characters plus a normal name directly
-- before writing it here.
alter table profiles drop constraint profiles_name_no_html_chars;
alter table profiles add constraint profiles_name_no_html_chars
  check (name !~ ('[<>"' || chr(39) || chr(92) || chr(92) || chr(96) || ']'));
