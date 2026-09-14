-- SECURITY FIX: the avatars bucket was created with no file_size_limit or
-- allowed_mime_types, so the storage-level policy allowed uploading any
-- file type/size to a bucket that is publicly readable (avatars: public
-- read). Restrict it server-side to actual images, capped at 5MB -- the
-- client already sends only image/* via the file picker, but that's a UI
-- hint only and was trivially bypassable via a direct API call.
update storage.buckets
set file_size_limit = 5242880, -- 5MB
    allowed_mime_types = array['image/png','image/jpeg','image/webp','image/gif']
where id = 'avatars';
