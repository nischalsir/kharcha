-- Pictures sent with a notification from the Kharcha Push Console.
--
-- Public, because a phone fetches the picture with no credential when the
-- notification arrives. Nobody can add to it directly: there is no storage
-- policy, so the only way in is the one-time upload link the admin-push
-- function hands the signed-in operator.
--
-- 1 MB is the most Android will draw as a notification picture.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'push-pictures',
  'push-pictures',
  true,
  1048576,
  array['image/jpeg', 'image/png']
)
on conflict (id) do nothing;
