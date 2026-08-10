-- Migration: Marketplace — user addresses & store profiles (FIXED)

-- user_addresses
CREATE TABLE IF NOT EXISTS user_addresses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  full_name TEXT,
  phone TEXT,
  address_line TEXT NOT NULL,
  city TEXT,
  state TEXT,
  postal_code TEXT,
  is_default BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- user_stores
CREATE TABLE IF NOT EXISTS user_stores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  store_name TEXT NOT NULL,
  tagline TEXT,
  description TEXT,
  logo_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_user_addresses_user_id ON user_addresses(user_id);
CREATE INDEX IF NOT EXISTS idx_user_addresses_default ON user_addresses(user_id, is_default) WHERE is_default = true;
CREATE INDEX IF NOT EXISTS idx_user_stores_user_id    ON user_stores(user_id);

-- RLS
ALTER TABLE user_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_stores    ENABLE ROW LEVEL SECURITY;

-- FIX 1: policies via DROP + CREATE (CREATE POLICY IF NOT EXISTS o'rniga)
DROP POLICY IF EXISTS user_addresses_policy ON user_addresses;
CREATE POLICY user_addresses_policy ON user_addresses
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS user_stores_policy ON user_stores;
CREATE POLICY user_stores_policy ON user_stores
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

-- FIX 2: triggers idempotent (DROP + CREATE)
DROP TRIGGER IF EXISTS update_user_addresses_updated_at ON user_addresses;
CREATE TRIGGER update_user_addresses_updated_at
  BEFORE UPDATE ON user_addresses
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_user_stores_updated_at ON user_stores;
CREATE TRIGGER update_user_stores_updated_at
  BEFORE UPDATE ON user_stores
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON user_addresses TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON user_stores    TO authenticated;

-- Comments
COMMENT ON TABLE  user_addresses IS 'Shipping addresses for marketplace orders';
COMMENT ON TABLE  user_stores    IS 'Seller store profiles for marketplace';
COMMENT ON COLUMN user_addresses.is_default IS 'Only one address per user can be default';
COMMENT ON COLUMN user_stores.logo_url IS 'Uploaded to Supabase Storage public bucket';

-- Reload API cache
NOTIFY pgrst, 'reload schema';