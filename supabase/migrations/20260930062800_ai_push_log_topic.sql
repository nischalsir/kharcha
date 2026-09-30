-- Separates "what the push was about" from "how it was delivered".
--
-- `category` was being filled with the model's own topic label ("budget",
-- "saving"), which is a different taxonomy from the app's push categories
-- ("ai_content", "budget_warnings"). Two things went wrong because of that:
-- the Android channel could not be resolved from it, so every AI push fell
-- back to the general channel instead of the insights channel; and the column
-- claimed to record a push category while holding something that was not one.
--
-- `topic` now records what the insight was about, and is what the per-topic
-- cooldown reasons over. `category` becomes the delivery category, which is
-- always `ai_content` for AI pushes.

alter table public.ai_notification_log
  add column if not exists topic text;

comment on column public.ai_notification_log.topic is
  'What the insight was about, in the model''s vocabulary (spending|saving|budget|income|general).';
comment on column public.ai_notification_log.category is
  'The app push category it was delivered as, used to resolve the Android channel.';
