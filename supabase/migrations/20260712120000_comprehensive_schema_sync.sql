-- Comprehensive Schema Sync Migration
-- Adds all missing columns found in client code audit
-- Project: mbhjganbihamoiqmankv.supabase.co
-- Date: 2026-07-12

-- ============================================================================
-- conversation_participants: Add mute_until column
-- ============================================================================
ALTER TABLE conversation_participants 
ADD COLUMN IF NOT EXISTS mute_until timestamptz;

COMMENT ON COLUMN conversation_participants.mute_until IS 'Timestamp when mute expires (null = not muted or muted indefinitely)';

-- ============================================================================
-- posts: Add all missing columns for repost/share/discovery features
-- ============================================================================

-- Source columns (for reposts from groups/channels)
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS source_type text CHECK (source_type IN ('user', 'group', 'channel', 'repost'));

ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS source_id uuid;

ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS source_title text;

ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS source_avatar_url text;

ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS source_message_id uuid;

-- Discovery & rich content columns
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS poll_data jsonb;

ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS location text;

ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS mentioned_users uuid[];

ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS tags text[];

ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS thumbnail_url text;

ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS video_duration integer;

-- Content moderation columns
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS moderation_status text CHECK (moderation_status IN ('pending', 'approved', 'rejected', 'flagged'));

ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS maturity_rating text CHECK (maturity_rating IN ('general', 'teen', 'mature', 'explicit'));

-- Set defaults for existing rows
UPDATE posts SET source_type = 'user' WHERE source_type IS NULL;
UPDATE posts SET moderation_status = 'approved' WHERE moderation_status IS NULL;
UPDATE posts SET maturity_rating = 'general' WHERE maturity_rating IS NULL;

-- Add column comments
COMMENT ON COLUMN posts.source_type IS 'Type of content source: user (original), group, channel, or repost';
COMMENT ON COLUMN posts.source_id IS 'ID of source group/channel if reposted';
COMMENT ON COLUMN posts.source_title IS 'Title of source group/channel';
COMMENT ON COLUMN posts.source_avatar_url IS 'Avatar of source group/channel';
COMMENT ON COLUMN posts.source_message_id IS 'Original message ID if reposted from group/channel';
COMMENT ON COLUMN posts.poll_data IS 'JSON data for polls: {question, options: [{text, votes}], expires_at}';
COMMENT ON COLUMN posts.location IS 'Geographic location text or coordinates';
COMMENT ON COLUMN posts.mentioned_users IS 'Array of user IDs mentioned in post';
COMMENT ON COLUMN posts.tags IS 'Array of hashtags extracted from content';
COMMENT ON COLUMN posts.thumbnail_url IS 'Video thumbnail URL (for video posts)';
COMMENT ON COLUMN posts.video_duration IS 'Video duration in seconds';
COMMENT ON COLUMN posts.moderation_status IS 'Content moderation status';
COMMENT ON COLUMN posts.maturity_rating IS 'Age-appropriateness rating';

-- ============================================================================
-- user_preferences: Add history_paused column
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_preferences (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  history_paused boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- RLS for user_preferences
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own preferences" ON user_preferences;
CREATE POLICY "Users can view own preferences" 
ON user_preferences FOR SELECT 
TO authenticated 
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own preferences" ON user_preferences;
CREATE POLICY "Users can update own preferences" 
ON user_preferences FOR ALL 
TO authenticated 
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

COMMENT ON TABLE user_preferences IS 'User-specific preferences and settings';
COMMENT ON COLUMN user_preferences.history_paused IS 'Whether view history recording is paused';

-- ============================================================================
-- Indexes for performance
-- ============================================================================

-- Posts indexes for new columns
CREATE INDEX IF NOT EXISTS idx_posts_source_type ON posts(source_type) WHERE source_type IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_posts_source_id ON posts(source_id) WHERE source_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_posts_tags ON posts USING GIN(tags) WHERE tags IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_posts_mentioned_users ON posts USING GIN(mentioned_users) WHERE mentioned_users IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_posts_moderation_status ON posts(moderation_status);

-- conversation_participants index for mute_until
CREATE INDEX IF NOT EXISTS idx_conversation_participants_mute_until 
ON conversation_participants(mute_until) 
WHERE mute_until IS NOT NULL;

-- ============================================================================
-- Reload API schema cache
-- ============================================================================
NOTIFY pgrst, 'reload schema';
