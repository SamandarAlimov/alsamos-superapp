-- Social Map Features Migration
-- Check-ins, Reviews, Location Posts, Meet Here, Circles, Groups

-- ============================================================================
-- CHECK-INS
-- ============================================================================

CREATE TABLE IF NOT EXISTS check_ins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  place_id TEXT NOT NULL, -- OSM place_id or custom place identifier
  place_name TEXT NOT NULL,
  place_category TEXT, -- restaurant, cafe, hotel, park, etc.
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  feeling TEXT, -- happy, excited, tired, hungry, etc.
  note TEXT,
  visibility TEXT NOT NULL DEFAULT 'friends', -- public, followers, friends, private
  photo_urls TEXT[], -- Array of photo URLs
  tagged_users UUID[], -- Array of user IDs tagged in check-in
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_check_ins_user_id ON check_ins(user_id);
CREATE INDEX IF NOT EXISTS idx_check_ins_place_id ON check_ins(place_id);
CREATE INDEX IF NOT EXISTS idx_check_ins_created_at ON check_ins(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_check_ins_location ON check_ins USING gist(ll_to_earth(latitude, longitude));

-- RLS Policies
ALTER TABLE check_ins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can create their own check-ins" ON check_ins;
CREATE POLICY "Users can create their own check-ins"
  ON check_ins FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own check-ins" ON check_ins;
CREATE POLICY "Users can view their own check-ins"
  ON check_ins FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view public check-ins" ON check_ins;
CREATE POLICY "Users can view public check-ins"
  ON check_ins FOR SELECT
  USING (visibility = 'public');

DROP POLICY IF EXISTS "Users can view friends' check-ins" ON check_ins;
CREATE POLICY "Users can view friends' check-ins"
  ON check_ins FOR SELECT
  USING (
    visibility IN ('friends', 'followers') AND
    EXISTS (
      SELECT 1 FROM follows
      WHERE follower_id = auth.uid() AND followed_id = user_id
    )
  );

DROP POLICY IF EXISTS "Users can update their own check-ins" ON check_ins;
CREATE POLICY "Users can update their own check-ins"
  ON check_ins FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own check-ins" ON check_ins;
CREATE POLICY "Users can delete their own check-ins"
  ON check_ins FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================================================
-- PLACE REVIEWS
-- ============================================================================

CREATE TABLE IF NOT EXISTS place_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  place_id TEXT NOT NULL,
  place_name TEXT NOT NULL,
  rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  review_text TEXT,
  categories TEXT[], -- food, service, ambiance, cleanliness, etc.
  category_ratings JSONB, -- {"food": 5, "service": 4, "ambiance": 5}
  photo_urls TEXT[],
  helpful_count INTEGER NOT NULL DEFAULT 0,
  visit_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, place_id) -- One review per user per place
);

CREATE INDEX IF NOT EXISTS idx_place_reviews_user_id ON place_reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_place_reviews_place_id ON place_reviews(place_id);
CREATE INDEX IF NOT EXISTS idx_place_reviews_rating ON place_reviews(rating DESC);
CREATE INDEX IF NOT EXISTS idx_place_reviews_created_at ON place_reviews(created_at DESC);

-- RLS Policies
ALTER TABLE place_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view reviews" ON place_reviews;
CREATE POLICY "Anyone can view reviews"
  ON place_reviews FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Users can create their own reviews" ON place_reviews;
CREATE POLICY "Users can create their own reviews"
  ON place_reviews FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own reviews" ON place_reviews;
CREATE POLICY "Users can update their own reviews"
  ON place_reviews FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own reviews" ON place_reviews;
CREATE POLICY "Users can delete their own reviews"
  ON place_reviews FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================================================
-- REVIEW HELPFUL VOTES
-- ============================================================================

CREATE TABLE IF NOT EXISTS review_helpful_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id UUID NOT NULL REFERENCES place_reviews(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(review_id, user_id) -- One vote per user per review
);

CREATE INDEX IF NOT EXISTS idx_review_helpful_votes_review_id ON review_helpful_votes(review_id);
CREATE INDEX IF NOT EXISTS idx_review_helpful_votes_user_id ON review_helpful_votes(user_id);

-- RLS Policies
ALTER TABLE review_helpful_votes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can vote reviews helpful" ON review_helpful_votes;
CREATE POLICY "Users can vote reviews helpful"
  ON review_helpful_votes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can remove their votes" ON review_helpful_votes;
CREATE POLICY "Users can remove their votes"
  ON review_helpful_votes FOR DELETE
  USING (auth.uid() = user_id);

-- Trigger to update helpful_count
CREATE OR REPLACE FUNCTION update_review_helpful_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE place_reviews
    SET helpful_count = helpful_count + 1
    WHERE id = NEW.review_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE place_reviews
    SET helpful_count = GREATEST(0, helpful_count - 1)
    WHERE id = OLD.review_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_review_helpful_count ON review_helpful_votes;
CREATE TRIGGER trigger_update_review_helpful_count
AFTER INSERT OR DELETE ON review_helpful_votes
FOR EACH ROW EXECUTE FUNCTION update_review_helpful_count();

-- ============================================================================
-- MEET HERE INVITATIONS
-- ============================================================================

CREATE TABLE IF NOT EXISTS meet_here_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  place_id TEXT NOT NULL,
  place_name TEXT NOT NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  meeting_time TIMESTAMPTZ,
  message TEXT,
  invited_users UUID[] NOT NULL DEFAULT '{}',
  accepted_users UUID[] NOT NULL DEFAULT '{}',
  declined_users UUID[] NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'pending', -- pending, confirmed, cancelled, completed
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_meet_here_creator_id ON meet_here_invitations(creator_id);
CREATE INDEX IF NOT EXISTS idx_meet_here_invited_users ON meet_here_invitations USING gin(invited_users);
CREATE INDEX IF NOT EXISTS idx_meet_here_status ON meet_here_invitations(status);
CREATE INDEX IF NOT EXISTS idx_meet_here_meeting_time ON meet_here_invitations(meeting_time);

-- RLS Policies
ALTER TABLE meet_here_invitations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can create invitations" ON meet_here_invitations;
CREATE POLICY "Users can create invitations"
  ON meet_here_invitations FOR INSERT
  WITH CHECK (auth.uid() = creator_id);

DROP POLICY IF EXISTS "Users can view their invitations" ON meet_here_invitations;
CREATE POLICY "Users can view their invitations"
  ON meet_here_invitations FOR SELECT
  USING (
    auth.uid() = creator_id OR
    auth.uid() = ANY(invited_users)
  );

DROP POLICY IF EXISTS "Creator can update invitations" ON meet_here_invitations;
CREATE POLICY "Creator can update invitations"
  ON meet_here_invitations FOR UPDATE
  USING (auth.uid() = creator_id);

DROP POLICY IF EXISTS "Invited users can respond" ON meet_here_invitations;
CREATE POLICY "Invited users can respond"
  ON meet_here_invitations FOR UPDATE
  USING (auth.uid() = ANY(invited_users));

-- ============================================================================
-- FAMILY CIRCLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS family_circles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  creator_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  member_ids UUID[] NOT NULL DEFAULT '{}',
  admin_ids UUID[] NOT NULL DEFAULT '{}',
  settings JSONB NOT NULL DEFAULT '{"auto_share_location": true, "show_battery": true, "show_driving_status": true}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_family_circles_creator_id ON family_circles(creator_id);
CREATE INDEX IF NOT EXISTS idx_family_circles_member_ids ON family_circles USING gin(member_ids);

-- RLS Policies
ALTER TABLE family_circles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can create circles" ON family_circles;
CREATE POLICY "Users can create circles"
  ON family_circles FOR INSERT
  WITH CHECK (auth.uid() = creator_id);

DROP POLICY IF EXISTS "Members can view their circles" ON family_circles;
CREATE POLICY "Members can view their circles"
  ON family_circles FOR SELECT
  USING (
    auth.uid() = creator_id OR
    auth.uid() = ANY(member_ids)
  );

DROP POLICY IF EXISTS "Admins can update circles" ON family_circles;
CREATE POLICY "Admins can update circles"
  ON family_circles FOR UPDATE
  USING (
    auth.uid() = creator_id OR
    auth.uid() = ANY(admin_ids)
  );

DROP POLICY IF EXISTS "Creator can delete circles" ON family_circles;
CREATE POLICY "Creator can delete circles"
  ON family_circles FOR DELETE
  USING (auth.uid() = creator_id);

-- ============================================================================
-- CIRCLE INVITATIONS
-- ============================================================================

CREATE TABLE IF NOT EXISTS circle_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id UUID NOT NULL REFERENCES family_circles(id) ON DELETE CASCADE,
  invited_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invited_by_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending', -- pending, accepted, declined
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(circle_id, invited_user_id)
);

CREATE INDEX IF NOT EXISTS idx_circle_invitations_circle_id ON circle_invitations(circle_id);
CREATE INDEX IF NOT EXISTS idx_circle_invitations_invited_user_id ON circle_invitations(invited_user_id);
CREATE INDEX IF NOT EXISTS idx_circle_invitations_status ON circle_invitations(status);

-- RLS Policies
ALTER TABLE circle_invitations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can create invitations" ON circle_invitations;
CREATE POLICY "Admins can create invitations"
  ON circle_invitations FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM family_circles
      WHERE id = circle_id AND (
        creator_id = auth.uid() OR
        auth.uid() = ANY(admin_ids)
      )
    )
  );

DROP POLICY IF EXISTS "Users can view their invitations" ON circle_invitations;
CREATE POLICY "Users can view their invitations"
  ON circle_invitations FOR SELECT
  USING (
    auth.uid() = invited_user_id OR
    auth.uid() = invited_by_id OR
    EXISTS (
      SELECT 1 FROM family_circles
      WHERE id = circle_id AND (
        creator_id = auth.uid() OR
        auth.uid() = ANY(admin_ids)
      )
    )
  );

DROP POLICY IF EXISTS "Invited users can respond" ON circle_invitations;
CREATE POLICY "Invited users can respond"
  ON circle_invitations FOR UPDATE
  USING (auth.uid() = invited_user_id);

-- ============================================================================
-- PLACE STATISTICS (Materialized for performance)
-- ============================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS place_statistics AS
SELECT
  place_id,
  place_name,
  COUNT(DISTINCT check_ins.user_id) as check_in_count,
  COUNT(DISTINCT place_reviews.user_id) as review_count,
  COALESCE(AVG(place_reviews.rating), 0) as average_rating,
  MAX(check_ins.created_at) as last_check_in,
  MAX(place_reviews.created_at) as last_review
FROM check_ins
LEFT JOIN place_reviews USING (place_id)
GROUP BY place_id, place_name;

CREATE UNIQUE INDEX IF NOT EXISTS idx_place_statistics_place_id ON place_statistics(place_id);

-- Refresh function (call periodically via cron or edge function)
CREATE OR REPLACE FUNCTION refresh_place_statistics()
RETURNS void AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY place_statistics;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- REALTIME SUBSCRIPTIONS
-- ============================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE check_ins;
ALTER PUBLICATION supabase_realtime ADD TABLE place_reviews;
ALTER PUBLICATION supabase_realtime ADD TABLE meet_here_invitations;
ALTER PUBLICATION supabase_realtime ADD TABLE family_circles;
ALTER PUBLICATION supabase_realtime ADD TABLE circle_invitations;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Get nearby check-ins
CREATE OR REPLACE FUNCTION get_nearby_check_ins(
  lat DOUBLE PRECISION,
  lon DOUBLE PRECISION,
  radius_km DOUBLE PRECISION DEFAULT 5.0,
  limit_count INTEGER DEFAULT 50
)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  place_name TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  feeling TEXT,
  note TEXT,
  distance_km DOUBLE PRECISION,
  created_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.id,
    c.user_id,
    c.place_name,
    c.latitude,
    c.longitude,
    c.feeling,
    c.note,
    earth_distance(ll_to_earth(lat, lon), ll_to_earth(c.latitude, c.longitude)) / 1000.0 as distance_km,
    c.created_at
  FROM check_ins c
  WHERE
    earth_box(ll_to_earth(lat, lon), radius_km * 1000) @> ll_to_earth(c.latitude, c.longitude)
    AND (
      c.visibility = 'public' OR
      (c.visibility IN ('friends', 'followers') AND EXISTS (
        SELECT 1 FROM follows
        WHERE follower_id = auth.uid() AND followed_id = c.user_id
      )) OR
      c.user_id = auth.uid()
    )
  ORDER BY earth_distance(ll_to_earth(lat, lon), ll_to_earth(c.latitude, c.longitude))
  LIMIT limit_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get place reviews with user info
CREATE OR REPLACE FUNCTION get_place_reviews(place_id_param TEXT, limit_count INTEGER DEFAULT 20)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  rating INTEGER,
  review_text TEXT,
  category_ratings JSONB,
  photo_urls TEXT[],
  helpful_count INTEGER,
  visit_date DATE,
  created_at TIMESTAMPTZ,
  user_has_voted BOOLEAN
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    pr.id,
    pr.user_id,
    pr.rating,
    pr.review_text,
    pr.category_ratings,
    pr.photo_urls,
    pr.helpful_count,
    pr.visit_date,
    pr.created_at,
    EXISTS(
      SELECT 1 FROM review_helpful_votes
      WHERE review_id = pr.id AND user_id = auth.uid()
    ) as user_has_voted
  FROM place_reviews pr
  WHERE pr.place_id = place_id_param
  ORDER BY pr.helpful_count DESC, pr.created_at DESC
  LIMIT limit_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- NOTIFICATIONS
-- ============================================================================

NOTIFY pgrst, 'reload schema';
