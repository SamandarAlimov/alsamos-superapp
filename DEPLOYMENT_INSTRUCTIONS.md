# Alsamos Global Web Search - Deployment Instructions

## Prerequisites

1. Supabase project (https://supabase.com)
2. Supabase CLI installed: https://supabase.com/docs/guides/cli
3. SearXNG instance URL (public instance or self-hosted)
4. Optional: Brave Search API key (fallback provider)

## Step 1: Link Supabase Project

```bash
# Login to Supabase
supabase login

# Link your project (interactive)
supabase link --project-ref YOUR_PROJECT_REF

# Or link with direct connection string
supabase link --db-url postgresql://postgres:[password]@[host]:[port]/postgres
```

To find your project ref:
- Go to https://supabase.com/dashboard
- Select your project
- Click Settings → General
- Copy "Reference ID"

## Step 2: Deploy Database Migration

```bash
# Push migration to remote database
supabase db push

# This will create:
# - search_history table
# - search_cache table
# - user_settings columns (search_safe_mode, search_region, search_language)
# - RLS policies and indexes
# - Cleanup functions
```

## Step 3: Deploy Edge Function

```bash
# Deploy the global-search Edge Function
supabase functions deploy global-search --no-verify-jwt

# Note: --no-verify-jwt is only needed if you're testing without full auth setup
# For production, remove this flag
```

## Step 4: Set Environment Variables

In your Supabase dashboard:

1. Go to Project Settings → Edge Functions
2. Add these secrets:

```bash
# Required: SearXNG instance URL (primary provider)
SEARXNG_URL=https://searx.be
# Or use your self-hosted instance:
# SEARXNG_URL=https://your-searxng.example.com

# Optional: Brave Search API key (fallback provider)
BRAVE_API_KEY=your_brave_api_key_here
```

Alternative via CLI:

```bash
# Set SearXNG URL
supabase secrets set SEARXNG_URL=https://searx.be

# Set Brave API key (optional)
supabase secrets set BRAVE_API_KEY=your_brave_api_key_here
```

To get a Brave Search API key:
- Visit https://brave.com/search/api/
- Sign up for free tier (2,000 queries/month)
- Copy your API key

## Step 5: Verify Deployment

Test the Edge Function:

```bash
# Test with curl (replace with your actual tokens)
curl -X POST https://YOUR_PROJECT_REF.supabase.co/functions/v1/global-search \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "flutter riverpod", "page": 1, "safeSearch": "moderate"}'
```

Expected response:
```json
{
  "results": [
    {
      "title": "Riverpod | Flutter Package",
      "url": "https://pub.dev/packages/riverpod",
      "displayUrl": "pub.dev",
      "snippet": "A reactive caching and data-binding framework...",
      "faviconUrl": "https://www.google.com/s2/favicons?domain=pub.dev&sz=32",
      "source": "pub.dev"
    }
  ],
  "page": 1,
  "hasMore": true,
  "provider": "SearXNG",
  "query": "flutter riverpod"
}
```

## Step 6: Update Flutter Client

Ensure `lib/app/config/supabase_config.dart` has your correct Supabase URL and anon key:

```dart
const supabaseUrl = 'https://YOUR_PROJECT_REF.supabase.co';
const supabaseAnonKey = 'YOUR_ANON_KEY';
```

## Testing in Flutter App

1. Build and run the app:
   ```bash
   flutter run -d windows
   ```

2. Navigate to Search page → Global tab

3. Type a query (e.g., "flutter tutorial")

4. Verify:
   - ✅ Search returns real web results
   - ✅ Results display with title, URL, snippet
   - ✅ Tapping a result opens in-app browser
   - ✅ Pagination works (scroll to bottom loads more)
   - ✅ Recent searches show when empty query
   - ✅ Clear history button works

## Troubleshooting

### "Unauthorized" error
- Check that `Authorization` header is being sent from Flutter client
- Verify `supabase_flutter` is properly initialized in `main.dart`
- Ensure user is logged in

### "Rate limit exceeded"
- Default: 30 searches per minute per user
- Adjust `RATE_LIMIT_PER_MINUTE` in `supabase/functions/global-search/index.ts`
- Redeploy: `supabase functions deploy global-search`

### SearXNG returns empty results
- Try a different SearXNG instance (see list: https://searx.space/)
- Check if your IP is rate-limited by the instance
- Enable Brave fallback (add `BRAVE_API_KEY`)

### Cache not working
- Cache TTL is 5 minutes (300 seconds)
- Adjust `CACHE_TTL_SECONDS` in Edge Function if needed
- Check `search_cache` table in Supabase SQL Editor

### Migration fails with "table already exists"
- If you already ran the migration, it's safe to ignore
- Or drop tables manually and re-run:
  ```sql
  DROP TABLE IF EXISTS search_history CASCADE;
  DROP TABLE IF EXISTS search_cache CASCADE;
  ALTER TABLE user_settings DROP COLUMN IF EXISTS search_safe_mode;
  ALTER TABLE user_settings DROP COLUMN IF EXISTS search_region;
  ALTER TABLE user_settings DROP COLUMN IF EXISTS search_language;
  ```

## SearXNG Self-Hosting (Optional)

For production, consider hosting your own SearXNG instance:

1. **Docker Compose:**
   ```bash
   git clone https://github.com/searxng/searxng-docker
   cd searxng-docker
   docker-compose up -d
   ```

2. **Update URL:**
   ```bash
   supabase secrets set SEARXNG_URL=https://your-searxng.example.com
   ```

Benefits:
- No rate limits
- Full control over search engines
- Custom filtering and ranking
- Privacy (no third-party requests)

Docs: https://docs.searxng.org/

## Cost Estimation

### Supabase Edge Functions
- **Free tier:** 500,000 invocations/month
- **Pro tier:** $25/month → 2M invocations, then $2 per additional 1M

### Database Storage
- **search_history:** ~100 bytes per query
  - 10K users × 10 queries/day = 100K queries/day
  - Monthly: ~300MB
- **search_cache:** ~2KB per cached query
  - 5-minute TTL → ~1000 cached queries active
  - Storage: ~2MB (negligible)

### SearXNG (self-hosted)
- **Server:** $5-10/month (1 vCPU, 1GB RAM sufficient)
- **Bandwidth:** Usually included in hosting

### Brave Search API (fallback)
- **Free tier:** 2,000 queries/month
- **Paid:** $5/month per 1,000 queries

**Recommendation:** Use public SearXNG + Brave free tier for MVP, migrate to self-hosted SearXNG for scale.

## Security Notes

1. **Never commit API keys** to Git
2. **Use RLS policies** (already enabled in migration)
3. **Rate limiting** prevents abuse (30/min default)
4. **Input validation** in Edge Function (max 500 chars)
5. **Cache poisoning prevention:** Cache keys include user intent (safeSearch/language/region)

## Production Checklist

- [ ] Supabase project linked
- [ ] Migration deployed (`supabase db push`)
- [ ] Edge Function deployed (`supabase functions deploy global-search`)
- [ ] Environment variables set (SEARXNG_URL, optional BRAVE_API_KEY)
- [ ] Test search in production app
- [ ] Verify RLS policies in Supabase dashboard
- [ ] Monitor Edge Function logs (Project Settings → Edge Functions → Logs)
- [ ] Set up Supabase alerts for rate limits/errors

## Maintenance

### Cleanup old data

Run periodically (or set up cron job):

```sql
-- Clean old search history (older than 30 days)
SELECT cleanup_old_search_history();

-- Clean old cache (older than 1 hour)
SELECT cleanup_old_search_cache();
```

Or create a pg_cron job:
```sql
SELECT cron.schedule(
  'cleanup-search-data',
  '0 2 * * *', -- Daily at 2 AM
  $$SELECT cleanup_old_search_history(); SELECT cleanup_old_search_cache();$$
);
```

### Monitor usage

```sql
-- Search volume per day
SELECT DATE(created_at) as date, COUNT(*) as searches
FROM search_history
GROUP BY DATE(created_at)
ORDER BY date DESC
LIMIT 30;

-- Top queries
SELECT query, COUNT(*) as count
FROM search_history
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY query
ORDER BY count DESC
LIMIT 20;

-- Cache hit rate
SELECT 
  COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '5 minutes') as cached_queries
FROM search_cache;
```

---

**Questions?** Check Supabase docs: https://supabase.com/docs
