# ⚡ Quick Fix for "search_safe_mode does not exist" Error

## 🔴 Problem
Global search tab shows: `column user_settings.search_safe_mode does not exist`

## ✅ Solution (2 minutes)

### 1️⃣ Apply Database Migration

Open Supabase SQL Editor and run:

```sql
-- Add search columns to user_settings
ALTER TABLE user_settings 
ADD COLUMN IF NOT EXISTS search_safe_mode TEXT DEFAULT 'moderate',
ADD COLUMN IF NOT EXISTS search_region TEXT DEFAULT 'uz',
ADD COLUMN IF NOT EXISTS search_language TEXT DEFAULT 'uz';

-- Create search_history table
CREATE TABLE IF NOT EXISTS search_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  query TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Create search_cache table
CREATE TABLE IF NOT EXISTS search_cache (
  cache_key TEXT PRIMARY KEY,
  results JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_search_history_user_id ON search_history(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_search_history_created ON search_history(created_at);
CREATE INDEX IF NOT EXISTS idx_search_cache_created ON search_cache(created_at);

-- Enable RLS
ALTER TABLE search_history ENABLE ROW LEVEL SECURITY;

-- Create RLS policy
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'search_history' 
    AND policyname = 'search_history_user_policy'
  ) THEN
    CREATE POLICY search_history_user_policy ON search_history
      FOR ALL
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- Grant permissions
GRANT SELECT, INSERT, DELETE ON search_history TO authenticated;
GRANT SELECT, INSERT, UPDATE ON search_cache TO service_role;
```

### 2️⃣ Reload API Cache

**Dashboard:** Settings → API → "Restart API Server"

**OR run in SQL Editor:**
```sql
NOTIFY pgrst, 'reload schema';
```

### 3️⃣ Restart Flutter App

```bash
# Stop app, then:
flutter run -d windows
```

## ✅ Verify

- Navigate to Search → Global tab
- Should show "Web qidiruvi" card (no error)
- Type query → see results

## 📄 Full Details

See `FIX_SEARCH_ERROR.md` for detailed troubleshooting.
