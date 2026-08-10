-- Sample sticker packs for testing
-- Run this manually after migration to populate sample data

-- Create a default emoji sticker pack
INSERT INTO public.sticker_packs (id, title, cover_url, is_animated, created_by)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'Default Smiles', null, false, null);

-- Add some static emoji stickers
INSERT INTO public.stickers (pack_id, emoji, type, position)
VALUES
  ('00000000-0000-0000-0000-000000000001', '😀', 'static', 0),
  ('00000000-0000-0000-0000-000000000001', '😃', 'static', 1),
  ('00000000-0000-0000-0000-000000000001', '😄', 'static', 2),
  ('00000000-0000-0000-0000-000000000001', '😁', 'static', 3),
  ('00000000-0000-0000-0000-000000000001', '😅', 'static', 4),
  ('00000000-0000-0000-0000-000000000001', '😂', 'static', 5),
  ('00000000-0000-0000-0000-000000000001', '🤣', 'static', 6),
  ('00000000-0000-0000-0000-000000000001', '😊', 'static', 7),
  ('00000000-0000-0000-0000-000000000001', '😇', 'static', 8),
  ('00000000-0000-0000-0000-000000000001', '🙂', 'static', 9),
  ('00000000-0000-0000-0000-000000000001', '😉', 'static', 10),
  ('00000000-0000-0000-0000-000000000001', '😍', 'static', 11),
  ('00000000-0000-0000-0000-000000000001', '🥰', 'static', 12),
  ('00000000-0000-0000-0000-000000000001', '😘', 'static', 13),
  ('00000000-0000-0000-0000-000000000001', '😗', 'static', 14),
  ('00000000-0000-0000-0000-000000000001', '😙', 'static', 15),
  ('00000000-0000-0000-0000-000000000001', '😚', 'static', 16),
  ('00000000-0000-0000-0000-000000000001', '😋', 'static', 17),
  ('00000000-0000-0000-0000-000000000001', '😛', 'static', 18),
  ('00000000-0000-0000-0000-000000000001', '😝', 'static', 19),
  ('00000000-0000-0000-0000-000000000001', '😜', 'static', 20),
  ('00000000-0000-0000-0000-000000000001', '🤪', 'static', 21),
  ('00000000-0000-0000-0000-000000000001', '🤨', 'static', 22),
  ('00000000-0000-0000-0000-000000000001', '🧐', 'static', 23),
  ('00000000-0000-0000-0000-000000000001', '🤓', 'static', 24),
  ('00000000-0000-0000-0000-000000000001', '😎', 'static', 25),
  ('00000000-0000-0000-0000-000000000001', '🤩', 'static', 26),
  ('00000000-0000-0000-0000-000000000001', '🥳', 'static', 27);

-- Create an animated sticker pack placeholder (with Lottie URLs)
INSERT INTO public.sticker_packs (id, title, is_animated, created_by)
VALUES
  ('00000000-0000-0000-0000-000000000002', 'Animated Pack', true, null);

-- Add sample animated stickers (these are placeholder Lottie files from public CDN)
-- In production, you'd upload your own Lottie files to Supabase Storage
INSERT INTO public.stickers (pack_id, emoji, lottie_url, type, position)
VALUES
  ('00000000-0000-0000-0000-000000000002', '👍', 'https://assets10.lottiefiles.com/packages/lf20_myo4mqln.json', 'animated', 0),
  ('00000000-0000-0000-0000-000000000002', '❤️', 'https://assets10.lottiefiles.com/packages/lf20_qv9b9cpv.json', 'animated', 1),
  ('00000000-0000-0000-0000-000000000002', '🎉', 'https://assets10.lottiefiles.com/packages/lf20_rovf9gzu.json', 'animated', 2),
  ('00000000-0000-0000-0000-000000000002', '🔥', 'https://assets10.lottiefiles.com/packages/lf20_7vkhmk7n.json', 'animated', 3),
  ('00000000-0000-0000-0000-000000000002', '⭐', 'https://assets10.lottiefiles.com/packages/lf20_ofa3xwo7.json', 'animated', 4);

-- Auto-install default pack for all existing users (optional)
-- Uncomment if you want all users to have the default pack
-- INSERT INTO public.user_sticker_packs (user_id, pack_id)
-- SELECT id, '00000000-0000-0000-0000-000000000001'
-- FROM public.users
-- ON CONFLICT DO NOTHING;

COMMENT ON TABLE public.sticker_packs IS 'Telegram-style sticker packs';
COMMENT ON TABLE public.stickers IS 'Individual stickers with support for static, animated (Lottie), and video formats';
COMMENT ON TABLE public.user_sticker_packs IS 'Junction table for user-installed sticker packs';
COMMENT ON TABLE public.recent_stickers IS 'Tracks recently used stickers for quick access';
