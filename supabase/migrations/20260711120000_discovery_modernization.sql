-- Migration: Discovery Modernization (SCHEMA-ALIGNED to live DB)
BEGIN;

-- 1) posts: add columns needed by discovery + feed function (no-op if already present)
ALTER TABLE posts
  ADD COLUMN IF NOT EXISTS poll_data JSONB,
  ADD COLUMN IF NOT EXISTS location TEXT,
  ADD COLUMN IF NOT EXISTS mentioned_users UUID[],
  ADD COLUMN IF NOT EXISTS tags TEXT[],
  ADD COLUMN IF NOT EXISTS moderation_status TEXT DEFAULT 'approved',
  ADD COLUMN IF NOT EXISTS maturity_rating TEXT DEFAULT 'general',
  ADD COLUMN IF NOT EXISTS is_hidden BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS visibility TEXT DEFAULT 'public',
  ADD COLUMN IF NOT EXISTS likes_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS comments_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS shares_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS views_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS media_urls TEXT[],
  ADD COLUMN IF NOT EXISTS media_type TEXT,
  ADD COLUMN IF NOT EXISTS source_type TEXT DEFAULT 'user',
  ADD COLUMN IF NOT EXISTS source_id TEXT,
  ADD COLUMN IF NOT EXISTS source_title TEXT,
  ADD COLUMN IF NOT EXISTS source_avatar_url TEXT,
  ADD COLUMN IF NOT EXISTS source_message_id TEXT;

CREATE INDEX IF NOT EXISTS idx_posts_moderation_status ON posts(moderation_status) WHERE moderation_status != 'rejected';
CREATE INDEX IF NOT EXISTS idx_posts_visibility_created ON posts(visibility, created_at DESC) WHERE visibility = 'public' AND moderation_status = 'approved';
CREATE INDEX IF NOT EXISTS idx_posts_tags ON posts USING GIN(tags) WHERE tags IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_posts_likes_count_desc ON posts(likes_count DESC) WHERE visibility = 'public' AND moderation_status = 'approved';

-- 2) stories: table EXISTS — add missing columns (this fixes the 42703 error)
ALTER TABLE stories
  ADD COLUMN IF NOT EXISTS duration INTEGER DEFAULT 5,
  ADD COLUMN IF NOT EXISTS text_overlay TEXT,
  ADD COLUMN IF NOT EXISTS background_color TEXT,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;
CREATE INDEX IF NOT EXISTS idx_stories_user_active ON stories(user_id, is_active, created_at DESC) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_stories_expires ON stories(expires_at) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_stories_active_created ON stories(created_at DESC) WHERE is_active = TRUE;
ALTER TABLE stories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS stories_select_public ON stories;
CREATE POLICY stories_select_public ON stories FOR SELECT USING (is_active = TRUE AND expires_at > now());
DROP POLICY IF EXISTS stories_insert_own ON stories;
CREATE POLICY stories_insert_own ON stories FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS stories_update_own ON stories;
CREATE POLICY stories_update_own ON stories FOR UPDATE USING (auth.uid() = user_id);
DROP POLICY IF EXISTS stories_delete_own ON stories;
CREATE POLICY stories_delete_own ON stories FOR DELETE USING (auth.uid() = user_id);

-- 3) story_views: EXISTS — just ensure RLS/policies
ALTER TABLE story_views ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS story_views_select_own_or_story_owner ON story_views;
CREATE POLICY story_views_select_own_or_story_owner ON story_views FOR SELECT USING (
  auth.uid() = viewer_id OR auth.uid() IN (SELECT user_id FROM stories WHERE stories.id = story_views.story_id)
);
DROP POLICY IF EXISTS story_views_insert_own ON story_views;
CREATE POLICY story_views_insert_own ON story_views FOR INSERT WITH CHECK (auth.uid() = viewer_id);

-- 4) blocked_users: EXISTS — ensure RLS/policies
ALTER TABLE blocked_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS blocked_users_select ON blocked_users;
CREATE POLICY blocked_users_select ON blocked_users FOR SELECT USING (auth.uid() = blocker_id);
DROP POLICY IF EXISTS blocked_users_insert ON blocked_users;
CREATE POLICY blocked_users_insert ON blocked_users FOR INSERT WITH CHECK (auth.uid() = blocker_id);
DROP POLICY IF EXISTS blocked_users_delete ON blocked_users;
CREATE POLICY blocked_users_delete ON blocked_users FOR DELETE USING (auth.uid() = blocker_id);

-- 5) muted_users: NEW
CREATE TABLE IF NOT EXISTS muted_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  muter_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  muted_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(muter_id, muted_id)
);
CREATE INDEX IF NOT EXISTS idx_muted_users_muter ON muted_users(muter_id);
CREATE INDEX IF NOT EXISTS idx_muted_users_muted ON muted_users(muted_id);
ALTER TABLE muted_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS muted_users_select ON muted_users;
CREATE POLICY muted_users_select ON muted_users FOR SELECT USING (auth.uid() = muter_id);
DROP POLICY IF EXISTS muted_users_insert ON muted_users;
CREATE POLICY muted_users_insert ON muted_users FOR INSERT WITH CHECK (auth.uid() = muter_id);
DROP POLICY IF EXISTS muted_users_delete ON muted_users;
CREATE POLICY muted_users_delete ON muted_users FOR DELETE USING (auth.uid() = muter_id);

-- 6) hidden_posts: NEW
CREATE TABLE IF NOT EXISTS hidden_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  hidden_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, post_id)
);
CREATE INDEX IF NOT EXISTS idx_hidden_posts_user ON hidden_posts(user_id);
CREATE INDEX IF NOT EXISTS idx_hidden_posts_post ON hidden_posts(post_id);
ALTER TABLE hidden_posts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS hidden_posts_select ON hidden_posts;
CREATE POLICY hidden_posts_select ON hidden_posts FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS hidden_posts_insert ON hidden_posts;
CREATE POLICY hidden_posts_insert ON hidden_posts FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS hidden_posts_delete ON hidden_posts;
CREATE POLICY hidden_posts_delete ON hidden_posts FOR DELETE USING (auth.uid() = user_id);

-- 7) categories: NEW
CREATE TABLE IF NOT EXISTS categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  name_uz TEXT, name_en TEXT, name_ru TEXT,
  icon TEXT, color TEXT,
  display_order INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_categories_active_order ON categories(is_active, display_order) WHERE is_active = TRUE;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS categories_select_active ON categories;
CREATE POLICY categories_select_active ON categories FOR SELECT USING (is_active = TRUE);
INSERT INTO categories (name, name_uz, name_en, name_ru, icon, color, display_order) VALUES
  ('all','Hammasi','All','Все','grid','#6366f1',0),
  ('sport','Sport','Sport','Спорт','trophy','#ef4444',1),
  ('music','Musiqa','Music','Музыка','music','#f59e0b',2),
  ('tech','Texnologiya','Technology','Технология','cpu','#3b82f6',3),
  ('fashion','Moda','Fashion','Мода','shirt','#ec4899',4),
  ('food','Ovqat','Food','Еда','utensils','#10b981',5),
  ('travel','Sayohat','Travel','Путешествия','plane','#8b5cf6',6),
  ('gaming','O''yinlar','Gaming','Игры','gamepad2','#6366f1',7),
  ('art','San''at','Art','Искусство','palette','#f97316',8),
  ('education','Ta''lim','Education','Образование','graduationCap','#14b8a6',9),
  ('business','Biznes','Business','Бизнес','briefcase','#64748b',10),
  ('health','Salomatlik','Health','Здоровье','heart','#f43f5e',11)
ON CONFLICT (name) DO NOTHING;

-- 8) user_interests: NEW
CREATE TABLE IF NOT EXISTS user_interests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  weight FLOAT DEFAULT 1.0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, category_id)
);
CREATE INDEX IF NOT EXISTS idx_user_interests_user ON user_interests(user_id);
CREATE INDEX IF NOT EXISTS idx_user_interests_category ON user_interests(category_id);
ALTER TABLE user_interests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_interests_select_own ON user_interests;
CREATE POLICY user_interests_select_own ON user_interests FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS user_interests_insert_own ON user_interests;
CREATE POLICY user_interests_insert_own ON user_interests FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS user_interests_update_own ON user_interests;
CREATE POLICY user_interests_update_own ON user_interests FOR UPDATE USING (auth.uid() = user_id);
DROP POLICY IF EXISTS user_interests_delete_own ON user_interests;
CREATE POLICY user_interests_delete_own ON user_interests FOR DELETE USING (auth.uid() = user_id);

-- 9) bookmarks: NEW
CREATE TABLE IF NOT EXISTS bookmarks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, post_id)
);
CREATE INDEX IF NOT EXISTS idx_bookmarks_user_created ON bookmarks(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bookmarks_post ON bookmarks(post_id);
ALTER TABLE bookmarks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bookmarks_select_own ON bookmarks;
CREATE POLICY bookmarks_select_own ON bookmarks FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS bookmarks_insert_own ON bookmarks;
CREATE POLICY bookmarks_insert_own ON bookmarks FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS bookmarks_delete_own ON bookmarks;
CREATE POLICY bookmarks_delete_own ON bookmarks FOR DELETE USING (auth.uid() = user_id);

-- 10) reports: NEW
CREATE TABLE IF NOT EXISTS reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  reason TEXT NOT NULL CHECK (reason IN ('spam','inappropriate','nsfw','harassment','violence','misinformation','copyright','other')),
  description TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending','reviewing','resolved','dismissed')),
  created_at TIMESTAMPTZ DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES profiles(id),
  CONSTRAINT reports_target_check CHECK ((post_id IS NOT NULL) OR (user_id IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reports_post ON reports(post_id) WHERE post_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reports_user ON reports(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reports_reporter ON reports(reporter_id, created_at DESC);
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS reports_select_own ON reports;
CREATE POLICY reports_select_own ON reports FOR SELECT USING (auth.uid() = reporter_id);
DROP POLICY IF EXISTS reports_insert_authenticated ON reports;
CREATE POLICY reports_insert_authenticated ON reports FOR INSERT WITH CHECK (auth.uid() = reporter_id);
DROP POLICY IF EXISTS reports_select_admin ON reports;
CREATE POLICY reports_select_admin ON reports FOR SELECT USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = TRUE)
);

-- 11) content_hides: NEW
CREATE TABLE IF NOT EXISTS content_hides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, post_id)
);
CREATE INDEX IF NOT EXISTS idx_content_hides_user ON content_hides(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_content_hides_post ON content_hides(post_id);
ALTER TABLE content_hides ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS content_hides_select_own ON content_hides;
CREATE POLICY content_hides_select_own ON content_hides FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS content_hides_insert_own ON content_hides;
CREATE POLICY content_hides_insert_own ON content_hides FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS content_hides_delete_own ON content_hides;
CREATE POLICY content_hides_delete_own ON content_hides FOR DELETE USING (auth.uid() = user_id);

-- 12) cleanup function for expired stories
CREATE OR REPLACE FUNCTION cleanup_expired_stories()
RETURNS void AS $$
BEGIN
  UPDATE stories SET is_active = FALSE WHERE is_active = TRUE AND expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

COMMIT;

NOTIFY pgrst, 'reload schema';