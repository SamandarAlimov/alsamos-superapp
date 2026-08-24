# Testing Telegram-Style Animated Stickers

## Prerequisites
✅ All code committed (commit 2208161)
✅ Migration file ready: `supabase/migrations/20260716000000_telegram_stickers.sql`
✅ Seed data ready: `supabase/seed_stickers.sql`
✅ Lottie dependency added to pubspec.yaml

## Setup Steps

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Run Database Migration
Option A - Using Supabase CLI:
```bash
supabase db push
```

Option B - Manual SQL execution:
```sql
-- Connect to your Supabase database and run:
-- d:\Alsamos\alsamos-superapp\supabase\migrations\20260716000000_telegram_stickers.sql
```

### 3. Seed Sample Data
```bash
# Connect to your database and run:
psql [your-connection-string] < supabase/seed_stickers.sql
```

Or manually execute the SQL in Supabase Dashboard → SQL Editor.

### 4. Install Default Pack for Test User
```sql
-- Replace 'YOUR_USER_ID' with your actual user ID from auth.users
INSERT INTO user_sticker_packs (user_id, pack_id)
VALUES ('YOUR_USER_ID', '00000000-0000-0000-0000-000000000001');
```

## Testing Checklist

### ✅ Basic Functionality
- [ ] Open any chat conversation
- [ ] Look for sticker button (🎟️) next to emoji button in composer
- [ ] Tap sticker button → picker opens as bottom sheet
- [ ] Verify picker shows:
  - [ ] Header with "Stikerlar" title
  - [ ] Search bar
  - [ ] Tab bar with recent (clock icon) and pack tabs
  - [ ] Grid view with 4 columns
- [ ] Tap a sticker → HapticFeedback → picker closes
- [ ] Verify sticker sent as message
- [ ] Verify sticker displays in message bubble

### ✅ Static Stickers
- [ ] Select an emoji sticker from "Default Smiles" pack
- [ ] Verify it displays correctly in chat
- [ ] Verify it loads quickly (cached)

### ✅ Animated Stickers
- [ ] Switch to "Animated Pack" tab
- [ ] Verify Lottie animations DON'T auto-play in picker grid (performance)
- [ ] Select an animated sticker
- [ ] Verify animation plays in message bubble after sending
- [ ] Verify animation loops continuously

### ✅ Recent Stickers
- [ ] Send a few stickers
- [ ] Switch to recent tab (clock icon)
- [ ] Verify recently sent stickers appear
- [ ] Verify most recent is first

### ✅ Search
- [ ] Type "😀" in search bar
- [ ] Verify only matching emoji stickers show
- [ ] Clear search → verify all stickers return

### ✅ Error Handling
- [ ] Try with no internet → verify emoji fallback displays
- [ ] Try invalid Lottie URL → verify emoji fallback

### ✅ Performance
- [ ] Open picker with 50+ stickers
- [ ] Verify smooth scrolling
- [ ] Verify no lag when switching tabs
- [ ] Verify animations don't cause frame drops

## Expected Behavior

### Sticker Picker
- Opens as DraggableScrollableSheet (0.65 initial size)
- Can be dragged up to 0.9 or down to 0.4
- Tab bar dynamically updates based on installed packs
- Recent tab only shows if user has recent stickers
- Grid scrolls smoothly with 4 columns
- Search filters by emoji text

### Message Display
- Static stickers: 150x150px, cached via CachedNetworkImage
- Animated stickers: 140px, Lottie animation plays on loop
- Video stickers: Shows thumbnail (full playback TODO)
- Fallback: Emoji text if URL fails to load

### Database
After sending stickers, verify in Supabase:
```sql
-- Check recent stickers
SELECT * FROM recent_stickers WHERE user_id = 'YOUR_USER_ID';

-- Check installed packs
SELECT * FROM user_sticker_packs WHERE user_id = 'YOUR_USER_ID';

-- Check sticker messages
SELECT id, media_type, media_url, metadata 
FROM messages 
WHERE media_type = 'sticker' 
ORDER BY created_at DESC 
LIMIT 5;
```

## Known Limitations
- Video stickers show thumbnail only (playback TODO)
- Sticker store page not implemented (tap + button shows TODO)
- Pack creation UI not implemented
- No sound effects (some animated stickers have audio in Telegram)

## Troubleshooting

### Picker doesn't open
- Check import: `import '../widgets/telegram_sticker_picker.dart';`
- Verify `_showStickerPicker()` method exists in chat_page.dart
- Check console for errors

### No stickers shown
- Verify migration ran successfully
- Verify seed data inserted
- Verify user has installed pack: `SELECT * FROM user_sticker_packs;`
- Check Supabase logs for RLS policy errors

### Animations don't play
- Verify Lottie dependency: `flutter pub get`
- Check Lottie URL is valid JSON
- Verify network connectivity
- Check console for Lottie load errors

### Performance issues
- Check if too many animations playing (should be autoPlay:false in picker)
- Verify RepaintBoundary is present on each sticker
- Check device performance (old devices may struggle with many Lottie animations)

## Next Steps After Testing
1. Fix any bugs found during testing
2. Implement sticker store page (browse/install new packs)
3. Add video sticker playback support
4. Add pack creation UI
5. Implement Supabase Storage upload for custom stickers
6. Add sticker suggestions based on message text
7. Add sound effects support

## Success Criteria
✅ User can open sticker picker from chat
✅ User can browse installed packs via tabs
✅ User can select and send stickers
✅ Static stickers display correctly
✅ Animated stickers play smoothly
✅ Recent stickers tab updates after usage
✅ Search works by emoji
✅ No performance issues or crashes

---

**Current Status:** 🎯 Ready for Testing  
**Estimated Test Time:** 15-20 minutes  
**Priority:** High - Core messaging feature
