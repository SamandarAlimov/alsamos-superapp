-- Messages + Map Integration
-- Live location sharing, location messages, check-in sharing in chats

-- ============================================================================
-- LIVE LOCATION SHARES (Telegram/WhatsApp style)
-- ============================================================================

CREATE TABLE IF NOT EXISTS message_live_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  current_latitude DOUBLE PRECISION NOT NULL,
  current_longitude DOUBLE PRECISION NOT NULL,
  destination_latitude DOUBLE PRECISION,
  destination_longitude DOUBLE PRECISION,
  destination_name TEXT,
  expires_at TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  update_interval_seconds INTEGER NOT NULL DEFAULT 30,
  last_updated TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_message_live_locations_message_id ON message_live_locations(message_id);
CREATE INDEX IF NOT EXISTS idx_message_live_locations_conversation_id ON message_live_locations(conversation_id);
CREATE INDEX IF NOT EXISTS idx_message_live_locations_sender_id ON message_live_locations(sender_id);
CREATE INDEX IF NOT EXISTS idx_message_live_locations_expires_at ON message_live_locations(expires_at);
CREATE INDEX IF NOT EXISTS idx_message_live_locations_is_active ON message_live_locations(is_active) WHERE is_active = true;

-- RLS Policies
ALTER TABLE message_live_locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can create live location shares" ON message_live_locations;
CREATE POLICY "Users can create live location shares"
  ON message_live_locations FOR INSERT
  WITH CHECK (auth.uid() = sender_id);

DROP POLICY IF EXISTS "Conversation members can view live locations" ON message_live_locations;
CREATE POLICY "Conversation members can view live locations"
  ON message_live_locations FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM conversation_participants
      WHERE conversation_id = message_live_locations.conversation_id
      AND user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Sender can update their live location" ON message_live_locations;
CREATE POLICY "Sender can update their live location"
  ON message_live_locations FOR UPDATE
  USING (auth.uid() = sender_id);

DROP POLICY IF EXISTS "Sender can delete their live location" ON message_live_locations;
CREATE POLICY "Sender can delete their live location"
  ON message_live_locations FOR DELETE
  USING (auth.uid() = sender_id);

-- ============================================================================
-- LOCATION UPDATE HISTORY (for live location tracking)
-- ============================================================================

CREATE TABLE IF NOT EXISTS live_location_updates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  live_location_id UUID NOT NULL REFERENCES message_live_locations(id) ON DELETE CASCADE,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  accuracy DOUBLE PRECISION,
  speed DOUBLE PRECISION,
  heading DOUBLE PRECISION,
  battery_level INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_live_location_updates_live_location_id ON live_location_updates(live_location_id);
CREATE INDEX IF NOT EXISTS idx_live_location_updates_created_at ON live_location_updates(created_at DESC);

-- RLS Policies
ALTER TABLE live_location_updates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Sender can insert updates" ON live_location_updates;
CREATE POLICY "Sender can insert updates"
  ON live_location_updates FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM message_live_locations
      WHERE id = live_location_id AND sender_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Conversation members can view updates" ON live_location_updates;
CREATE POLICY "Conversation members can view updates"
  ON live_location_updates FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM message_live_locations mll
      JOIN conversation_participants cp ON cp.conversation_id = mll.conversation_id
      WHERE mll.id = live_location_id AND cp.user_id = auth.uid()
    )
  );

-- ============================================================================
-- MESSAGE LOCATION METADATA HELPER FUNCTION
-- ============================================================================

-- Function to extract location from message metadata
CREATE OR REPLACE FUNCTION get_message_location(msg_metadata JSONB)
RETURNS TABLE (
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  location_name TEXT,
  location_type TEXT
) AS $$
BEGIN
  RETURN QUERY SELECT
    (msg_metadata->>'location_lat')::DOUBLE PRECISION,
    (msg_metadata->>'location_lon')::DOUBLE PRECISION,
    msg_metadata->>'location_name',
    msg_metadata->>'location_type';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- SHARED CHECK-INS IN MESSAGES
-- ============================================================================

-- No separate table needed - check-ins are shared via metadata:
-- metadata: {
--   "shared_checkin_id": "uuid",
--   "location_lat": 39.6270,
--   "location_lon": 66.9750,
--   "location_name": "Platan Restaurant",
--   "location_type": "checkin"
-- }

-- ============================================================================
-- SHARED PLACES IN MESSAGES
-- ============================================================================

-- Places shared via metadata:
-- metadata: {
--   "location_lat": 39.6270,
--   "location_lon": 66.9750,
--   "location_name": "Registan Square",
--   "location_address": "Samarkand, Uzbekistan",
--   "location_type": "place",
--   "place_id": "osm_12345",
--   "place_category": "landmark"
-- }

-- ============================================================================
-- AUTO-EXPIRE LIVE LOCATIONS
-- ============================================================================

-- Function to auto-deactivate expired live locations
CREATE OR REPLACE FUNCTION deactivate_expired_live_locations()
RETURNS void AS $$
BEGIN
  UPDATE message_live_locations
  SET is_active = false
  WHERE is_active = true AND expires_at < now();
END;
$$ LANGUAGE plpgsql;

-- This should be called periodically via cron or edge function
-- Example: SELECT cron.schedule('deactivate-expired-locations', '*/1 * * * *', 'SELECT deactivate_expired_live_locations();');

-- ============================================================================
-- GET ACTIVE LIVE LOCATIONS IN CONVERSATION
-- ============================================================================

CREATE OR REPLACE FUNCTION get_conversation_live_locations(conv_id UUID)
RETURNS TABLE (
  id UUID,
  message_id UUID,
  sender_id UUID,
  current_latitude DOUBLE PRECISION,
  current_longitude DOUBLE PRECISION,
  destination_latitude DOUBLE PRECISION,
  destination_longitude DOUBLE PRECISION,
  destination_name TEXT,
  expires_at TIMESTAMPTZ,
  last_updated TIMESTAMPTZ,
  sender_name TEXT,
  sender_avatar TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    mll.id,
    mll.message_id,
    mll.sender_id,
    mll.current_latitude,
    mll.current_longitude,
    mll.destination_latitude,
    mll.destination_longitude,
    mll.destination_name,
    mll.expires_at,
    mll.last_updated,
    p.display_name as sender_name,
    p.avatar_url as sender_avatar
  FROM message_live_locations mll
  JOIN profiles p ON p.id = mll.sender_id
  WHERE
    mll.conversation_id = conv_id
    AND mll.is_active = true
    AND mll.expires_at > now()
    AND EXISTS (
      SELECT 1 FROM conversation_participants
      WHERE conversation_id = conv_id AND user_id = auth.uid()
    )
  ORDER BY mll.last_updated DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- UPDATE LIVE LOCATION POSITION
-- ============================================================================

CREATE OR REPLACE FUNCTION update_live_location_position(
  live_loc_id UUID,
  new_lat DOUBLE PRECISION,
  new_lon DOUBLE PRECISION,
  new_accuracy DOUBLE PRECISION DEFAULT NULL,
  new_speed DOUBLE PRECISION DEFAULT NULL,
  new_heading DOUBLE PRECISION DEFAULT NULL,
  new_battery INTEGER DEFAULT NULL
)
RETURNS void AS $$
BEGIN
  -- Check permission
  IF NOT EXISTS (
    SELECT 1 FROM message_live_locations
    WHERE id = live_loc_id AND sender_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not authorized to update this live location';
  END IF;

  -- Update current position in main table
  UPDATE message_live_locations
  SET
    current_latitude = new_lat,
    current_longitude = new_lon,
    last_updated = now()
  WHERE id = live_loc_id;

  -- Insert update history
  INSERT INTO live_location_updates (
    live_location_id,
    latitude,
    longitude,
    accuracy,
    speed,
    heading,
    battery_level
  ) VALUES (
    live_loc_id,
    new_lat,
    new_lon,
    new_accuracy,
    new_speed,
    new_heading,
    new_battery
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- STOP LIVE LOCATION SHARING
-- ============================================================================

CREATE OR REPLACE FUNCTION stop_live_location_sharing(live_loc_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE message_live_locations
  SET is_active = false
  WHERE id = live_loc_id AND sender_id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- REALTIME SUBSCRIPTIONS
-- ============================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE message_live_locations;
ALTER PUBLICATION supabase_realtime ADD TABLE live_location_updates;

-- ============================================================================
-- NOTIFICATIONS
-- ============================================================================

NOTIFY pgrst, 'reload schema';
