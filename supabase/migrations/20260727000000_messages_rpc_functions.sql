BEGIN;

-- RPC: get_conversation_unreads
-- Returns unread count, mention count, and last message content per conversation
CREATE OR REPLACE FUNCTION public.get_conversation_unreads(
  p_user_id uuid,
  p_conversation_ids uuid[]
)
RETURNS TABLE(
  conversation_id uuid,
  unread_count bigint,
  mention_count bigint,
  last_message_content text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH participant_reads AS (
    SELECT
      cp.conversation_id AS conv_id,
      cp.last_read_at
    FROM conversation_participants cp
    WHERE cp.user_id = p_user_id
      AND cp.conversation_id = ANY(p_conversation_ids)
  ),
  unreads AS (
    SELECT
      m.conversation_id AS conv_id,
      count(*) AS cnt,
      count(*) FILTER (
        WHERE m.content ILIKE '%@%'
      ) AS mention_cnt
    FROM messages m
    JOIN participant_reads pr ON pr.conv_id = m.conversation_id
    WHERE m.conversation_id = ANY(p_conversation_ids)
      AND m.sender_id != p_user_id
      AND m.created_at > COALESCE(pr.last_read_at, '1970-01-01'::timestamptz)
      AND m.is_deleted = false
    GROUP BY m.conversation_id
  ),
  last_msgs AS (
    SELECT DISTINCT ON (m.conversation_id)
      m.conversation_id AS conv_id,
      m.content
    FROM messages m
    WHERE m.conversation_id = ANY(p_conversation_ids)
      AND m.is_deleted = false
    ORDER BY m.conversation_id, m.created_at DESC
  )
  SELECT
    cid.id AS conversation_id,
    COALESCE(u.cnt, 0) AS unread_count,
    COALESCE(u.mention_cnt, 0) AS mention_count,
    lm.content AS last_message_content
  FROM unnest(p_conversation_ids) AS cid(id)
  LEFT JOIN unreads u ON u.conv_id = cid.id
  LEFT JOIN last_msgs lm ON lm.conv_id = cid.id;
END;
$$;

COMMENT ON FUNCTION public.get_conversation_unreads(uuid, uuid[]) IS
  'Returns unread counts and last message for each conversation';

-- RPC: get_last_messages
-- Returns the most recent message content per conversation
CREATE OR REPLACE FUNCTION public.get_last_messages(
  p_conversation_ids uuid[]
)
RETURNS TABLE(
  conversation_id uuid,
  content text,
  sender_id uuid,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT ON (m.conversation_id)
    m.conversation_id,
    m.content,
    m.sender_id,
    m.created_at
  FROM messages m
  WHERE m.conversation_id = ANY(p_conversation_ids)
    AND m.is_deleted = false
  ORDER BY m.conversation_id, m.created_at DESC;
END;
$$;

COMMENT ON FUNCTION public.get_last_messages(uuid[]) IS
  'Returns the latest non-deleted message per conversation';

GRANT EXECUTE ON FUNCTION public.get_conversation_unreads(uuid, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_last_messages(uuid[]) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
