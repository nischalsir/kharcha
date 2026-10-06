-- The payment QR of a shop or a friend: a picture of the code a wallet app
-- scans to pay them, stored in the private `kharcha-files` bucket under the
-- owner's own folder. Null where none was added, which is every row made
-- before this column existed.
--
-- Additive and nullable, so older app versions keep working: they neither
-- send nor read the column, and an upsert that omits it leaves it untouched.
alter table public.pasals
  add column if not exists qr_path text;

alter table public.friends
  add column if not exists qr_path text;

comment on column public.pasals.qr_path is
  'Storage path in the kharcha-files bucket (<user id>/qr/pasal-<id>-<time>.jpg), or null.';

comment on column public.friends.qr_path is
  'Storage path in the kharcha-files bucket (<user id>/qr/friend-<id>-<time>.jpg), or null.';
