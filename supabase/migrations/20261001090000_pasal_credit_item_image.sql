-- An optional picture of the item, stored in the private `kharcha-files`
-- bucket under the owner's own folder. Null for items without one, which is
-- every item created before this column existed.
--
-- Additive and nullable, so older app versions keep working: they neither
-- send nor read the column, and an upsert that omits it leaves it untouched.
alter table public.pasal_credit_items
  add column if not exists image_path text;

comment on column public.pasal_credit_items.image_path is
  'Storage path in the kharcha-files bucket (<user id>/pasal/<item id>.<ext>), or null.';
