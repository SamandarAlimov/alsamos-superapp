-- Migration: Fix Posts Schema — views_count + post_views (ROBUST)
BEGIN;

-- posts.views_count
ALTER TABLE posts ADD COLUMN IF NOT EXISTS views_count INTEGER DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_posts_views_count_desc ON posts(views_count DESC)
  WHERE visibility = 'public' AND moderation_status = 'approved';

-- post_views (jadval MAVJUD bo'lishi mumkin — ustunlarni kafolatlaymiz)
CREATE TABLE IF NOT EXISTS post_views (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  viewer_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  viewed_at TIMESTAMPTZ DEFAULT now(),
  ip_address INET,
  user_agent TEXT,
  UNIQUE(post_id, viewer_id)
);
ALTER TABLE post_views
  ADD COLUMN IF NOT EXISTS post_id UUID,
  ADD COLUMN IF NOT EXISTS viewer_id UUID,
  ADD COLUMN IF NOT EXISTS viewed_at TIMESTAMPTZ DEFAULT now(),
  ADD COLUMN IF NOT EXISTS ip_address INET,
  ADD COLUMN IF NOT EXISTS user_agent TEXT;

CREATE INDEX IF NOT EXISTS idx_post_views_post ON post_views(post_id, viewed_at DESC);
CREATE INDEX IF NOT EXISTS idx_post_views_viewer ON post_views(viewer_id, viewed_at DESC) WHERE viewer_id IS NOT NULL;

ALTER TABLE post_views ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS post_views_insert ON post_views;
CREATE POLICY post_views_insert ON post_views FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS post_views_select_own ON post_views;
CREATE POLICY post_views_select_own ON post_views FOR SELECT USING (viewer_id = auth.uid() OR viewer_id IS NULL);
DROP POLICY IF EXISTS post_views_select_author ON post_views;
CREATE POLICY post_views_select_author ON post_views FOR SELECT USING (
  EXISTS (SELECT 1 FROM posts WHERE posts.id = post_views.post_id AND posts.user_id = auth.uid())
);

-- views_count trigger
CREATE OR REPLACE FUNCTION update_post_views_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE posts SET views_count = COALESCE(views_count,0) + 1 WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE posts SET views_count = GREATEST(COALESCE(views_count,0) - 1, 0) WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS update_post_views_count_trigger ON post_views;
CREATE TRIGGER update_post_views_count_trigger AFTER INSERT OR DELETE ON post_views
  FOR EACH ROW EXECUTE FUNCTION update_post_views_count();

-- Backfill
UPDATE posts
SET views_count = COALESCE((SELECT COUNT(*) FROM post_views WHERE post_views.post_id = posts.id), 0)
WHERE views_count = 0;

COMMENT ON COLUMN posts.views_count IS 'Total unique views (tracked via post_views)';
COMMENT ON TABLE post_views IS 'Unique post views per user/IP for analytics/trending';

COMMIT;

NOTIFY pgrst, 'reload schema';