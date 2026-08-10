-- Migration: Backend persistence columns for Map, AI, Marketplace settings (FIXED)

-- Map settings
ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS map_share_location BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS map_style TEXT DEFAULT 'standard';

-- AI settings
ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS ai_model TEXT DEFAULT 'gpt-4',
  ADD COLUMN IF NOT EXISTS ai_personalization BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS ai_data_sharing BOOLEAN DEFAULT false;

-- Marketplace settings
ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS marketplace_order_notifications BOOLEAN DEFAULT true;

-- Messages settings
ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS msg_enter_to_send BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS msg_auto_download_images BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS msg_auto_download_videos BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS msg_text_size DOUBLE PRECISION DEFAULT 16.0;

-- Index
CREATE INDEX IF NOT EXISTS idx_user_settings_user_id ON user_settings(user_id);

-- Comments
COMMENT ON COLUMN user_settings.map_share_location IS 'Allow sharing user location on map';
COMMENT ON COLUMN user_settings.map_style IS 'Map display style: standard, satellite, or terrain';
COMMENT ON COLUMN user_settings.ai_model IS 'Selected AI model: gpt-4 or gpt-3.5';
COMMENT ON COLUMN user_settings.ai_personalization IS 'Enable AI personalized responses';
COMMENT ON COLUMN user_settings.ai_data_sharing IS 'Consent to use data for AI improvement';
COMMENT ON COLUMN user_settings.marketplace_order_notifications IS 'Enable order status notifications';
COMMENT ON COLUMN user_settings.msg_enter_to_send IS 'Use Enter key to send messages';
COMMENT ON COLUMN user_settings.msg_auto_download_images IS 'Auto-download images on WiFi and mobile';
COMMENT ON COLUMN user_settings.msg_auto_download_videos IS 'Auto-download videos on WiFi only';
COMMENT ON COLUMN user_settings.msg_text_size IS 'Message text size in pixels';

-- ai_chat_messages table
CREATE TABLE IF NOT EXISTS ai_chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  metadata JSONB DEFAULT '{}'::jsonb
);

-- Index
CREATE INDEX IF NOT EXISTS idx_ai_chat_messages_user_id ON ai_chat_messages(user_id, created_at DESC);

-- RLS
ALTER TABLE ai_chat_messages ENABLE ROW LEVEL SECURITY;

-- FIX: DROP + CREATE (CREATE POLICY IF NOT EXISTS o'rniga)
DROP POLICY IF EXISTS ai_chat_messages_user_policy ON ai_chat_messages;
CREATE POLICY ai_chat_messages_user_policy ON ai_chat_messages
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Grant
GRANT SELECT, INSERT, UPDATE, DELETE ON ai_chat_messages TO authenticated;

-- Reload API cache
NOTIFY pgrst, 'reload schema';