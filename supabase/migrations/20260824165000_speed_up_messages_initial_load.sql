BEGIN;

-- The Flutter chat opens the newest messages in a conversation:
--   WHERE conversation_id = ?
--   ORDER BY created_at DESC
--   LIMIT 50/100
-- Without this exact index, large conversations can timeout before the UI gets
-- even a small initial page.
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created_desc
  ON public.messages(conversation_id, created_at DESC);

-- Keeps the common non-deleted/latest-message path fast as conversations grow.
CREATE INDEX IF NOT EXISTS idx_messages_conversation_visible_created_desc
  ON public.messages(conversation_id, created_at DESC)
  WHERE is_deleted = false OR is_deleted IS NULL;

-- Helps participant lookups used by chat list queries and RLS predicates on
-- databases that do not already have the original UNIQUE(conversation_id,user_id)
-- index in place.
CREATE INDEX IF NOT EXISTS idx_conversation_participants_conversation_user
  ON public.conversation_participants(conversation_id, user_id);

COMMIT;

NOTIFY pgrst, 'reload schema';
