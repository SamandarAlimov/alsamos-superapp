-- Migration: View History for Watch/View Content Tracking
-- Date: 2026-07-12
-- Purpose: Track user view history for videos, posts, products, channels, and other content

BEGIN;

-- Create view_history table
CREATE TABLE IF NOT EXISTS view_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  content_type TEXT NOT NULL CHECK (content_type IN ('video', 'post', 'product', 'channel', 'article', 'story')),
  content_id UUID NOT NULL,
  progress NUMERIC, -- For videos: 0-1 (percentage) or seconds; NULL for other types
  viewed_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT unique_user_content UNIQUE (user_id, content_type, content_id)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_view_history_user_viewed ON view_history(user_id, viewed_at DESC);
CREATE INDEX IF NOT EXISTS idx_view_history_content ON view_history(content_type, content_id);
CREATE INDEX IF NOT EXISTS idx_view_history_user_type ON view_history(user_id, content_type, viewed_at DESC);

-- Enable RLS
ALTER TABLE view_history ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS "Users can read own history" ON view_history;
CREATE POLICY "Users can read own history" ON view_history
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own history" ON view_history;
CREATE POLICY "Users can insert own history" ON view_history
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own history" ON view_history;
CREATE POLICY "Users can update own history" ON view_history
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own history" ON view_history;
CREATE POLICY "Users can delete own history" ON view_history
  FOR DELETE USING (auth.uid() = user_id);

-- Create user_preferences table for history settings (if not exists)
CREATE TABLE IF NOT EXISTS user_preferences (
  user_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  history_paused BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own preferences" ON user_preferences;
CREATE POLICY "Users can read own preferences" ON user_preferences
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own preferences" ON user_preferences;
CREATE POLICY "Users can insert own preferences" ON user_preferences
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own preferences" ON user_preferences;
CREATE POLICY "Users can update own preferences" ON user_preferences
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Comments for documentation
COMMENT ON TABLE view_history IS 'User content view history - YouTube/Instagram style watch history';
COMMENT ON COLUMN view_history.content_type IS 'Type of content: video, post, product, channel, article, story';
COMMENT ON COLUMN view_history.progress IS 'For videos: playback position (0-1 or seconds); NULL for other content';
COMMENT ON COLUMN view_history.viewed_at IS 'Timestamp of view (updated on re-view to move to top)';

COMMENT ON TABLE user_preferences IS 'User preferences including history pause state';
COMMENT ON COLUMN user_preferences.history_paused IS 'When true, stop recording view history';

COMMIT;
