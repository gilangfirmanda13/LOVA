-- Storage bucket for profile photos. Public read (avatars need to be
-- visible to teammates viewing someone else's Team Member profile,
-- which -- unlike journal_entries -- was never meant to be private),
-- but writes are restricted to a user's own folder (avatars/<uid>/...)
-- so nobody can overwrite another member's photo.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

create policy "avatars: public read"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "avatars: owner can upload"
  on storage.objects for insert
  with check (bucket_id = 'avatars' and (select auth.uid())::text = (storage.foldername(name))[1]);

create policy "avatars: owner can update"
  on storage.objects for update
  using (bucket_id = 'avatars' and (select auth.uid())::text = (storage.foldername(name))[1]);

create policy "avatars: owner can delete"
  on storage.objects for delete
  using (bucket_id = 'avatars' and (select auth.uid())::text = (storage.foldername(name))[1]);
