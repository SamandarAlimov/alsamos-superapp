# Alsamos Content Engine Spec

Status: discovery and plan only. No production code was changed for this spec.

## 1. Current-State Findings

### Create Flow

- `lib/features/create/presentation/create_page.dart:25` wires `CreateRepository` directly from the page.
- `lib/features/create/presentation/create_page.dart:27` supports four tabs: post, story, reel, live.
- `lib/features/create/presentation/create_page.dart:162` contains the main `CreatePage`; it is a large monolithic page that owns compose state, media picking, story/reel/live UI, upload, and navigation.
- `lib/features/create/presentation/create_page.dart:223` picks arbitrary files with `file_picker`.
- `lib/features/create/presentation/create_page.dart:255` picks gallery images/videos with `image_picker`.
- `lib/features/create/presentation/create_page.dart:324` uploads media directly to Supabase Storage bucket `message-attachments` from the UI layer.
- `lib/features/create/presentation/create_page.dart:425` submits posts, stories, reels, and live routing from one method.
- `lib/features/create/presentation/create_page.dart:466` inserts stories directly from the page instead of routing through `CreateRepository`.
- `lib/features/create/data/create_repository.dart:5` is the only create repository; it only inserts basic `posts` rows (`content`, `media_urls`, `media_type`, `visibility`).

Main gap: create is functional but not a professional content engine yet. It needs capture, drafts, upload queue, editor/effects, normalized metadata, shoppable/location targets, and shared rendering contracts.

### Content Model

- `lib/features/home/data/models/post_model.dart:5` is the main post model.
- `lib/features/home/data/repositories/posts_repository.dart:22` fetches public posts from `posts`.
- `lib/features/videos/data/video_repository.dart:11` treats videos as `posts.media_type == 'video'`.
- `lib/features/stories/data/stories_repository.dart` and `lib/features/discovery/data/models/story_model.dart` keep stories separate from posts.
- Existing migrations add many post columns over time: `post_likes`, `post_views`, `reposts`, `tags`, `thumbnail_url`, `video_duration`, source metadata, and trending helpers.

Main gap: posts, stories, reels, ads, live archives, marketplace promos, and map posts are not represented by one stable content contract. Some code still references incompatible fields (`media_url` vs `media_urls`) or different profile embeds.

### Shared Rendering / Duplicates

- Home feed card: `lib/features/home/presentation/widgets/post_card.dart:40`.
- Discovery card: `lib/features/discovery/presentation/widgets/post_card.dart:25`.
- Search media card: `lib/features/search/presentation/widgets/media_post_card.dart:13`.
- Home carousel: `lib/features/home/presentation/widgets/post_media_carousel.dart:12`.
- Story viewer duplicate A: `lib/features/discovery/presentation/widgets/story_viewer.dart:17`.
- Story viewer duplicate B: `lib/features/stories/presentation/widgets/story_viewer.dart:23`.
- Comment likes duplicate A: `lib/shared/widgets/comment_likes_dialog.dart:11`.
- Comment likes duplicate B: `lib/features/comments/presentation/widgets/comment_likes_dialog.dart:24`.
- Messages post preview: `lib/features/messages/presentation/widgets/shared_post_preview.dart:12`.
- AI forwarded post card is local UI: `lib/features/ai/presentation/pages/ai_page.dart:706`.

Main gap: post rendering is split by surface, so every feature has to be reimplemented multiple times. The engine needs `lib/shared/content/` widgets and adapters.

### Surfaces That Show / Need Posts

- Home: `lib/features/home/presentation/pages/home_page.dart:88` renders `PostCard` from `PostsRepository.fetchPosts`.
- Notifications: `lib/features/notifications/data/notifications_repository.dart:64` fetches post data for notifications; notification page also has local video preview UI.
- Search: `lib/features/search/data/search_repository.dart:53` searches public posts and renders with `MediaPostCard`.
- Discovery: `lib/features/discovery/presentation/widgets/for_you_section.dart:400`, `trending_public_posts.dart:81`, and `trending_videos.dart` render/query posts with local widgets.
- Videos: `lib/features/videos/data/video_repository.dart:11` fetches video posts; `lib/features/videos/presentation/pages/videos_page.dart` owns reel playback.
- Messages: `lib/features/messages/presentation/widgets/shared_post_preview.dart:12` fetches a post by id; `messages_repository.dart` can insert/share post-like content.
- Marketplace: `lib/features/marketplace/data/marketplace_repository.dart:516` builds video commerce from `posts` + `sellers` + `products`.
- Map: `lib/features/map/data/map_repository.dart:545` fetches social post markers from `posts.location`.
- AI: `lib/features/ai/presentation/providers/ai_provider.dart:9` has `ForwardedPost`; AI page renders a local forwarded card.
- Profile: `lib/features/profile/data/profile_repository.dart:35` fetches user posts; profile pages render local grid tiles.
- Ads/Admin: `lib/features/ads/presentation/widgets/feed_ad_card.dart` and `admin_content_management.dart` have separate content/admin paths.

### Infrastructure To Reuse

- Data layer: `BaseRepository`, `SupabaseDataSource`, `AppError`, `guard`, and `requireUserId` are available.
- Notifications/toasts: `AppToast` and `friendlyError` are available.
- Media dependencies already present: `image_picker`, `file_picker`, `camera`, `video_player`, `record`, `flutter_svg`, `lottie`, `video_thumbnail`.
- Live/calls infra exists under `lib/features/live/**` and messages call widgets; live streaming must extend this carefully rather than replacing it.
- Marketplace, map, notifications, AI, profile, and search have real repositories that can consume a unified content adapter.

## 2. Target Architecture

### A. Unified Content Model

Create a shared content layer that can represent:

- post
- story
- reel
- live scheduled / live active / live archive
- ad / promoted post
- marketplace shoppable post
- map/location post
- channel/group post

Core fields:

- identity: `id`, `authorId`, `sourceType`, `sourceId`
- type: `contentType`, `mediaType`, `visibility`
- text: `text`, `caption`, `hashtags`, `mentions`, `links`
- media: ordered media items with `url`, `storagePath`, `thumbUrl`, `mimeType`, `width`, `height`, `durationMs`, `sizeBytes`
- commerce: product ids, seller id, price snapshot, CTA metadata
- location: lat/lng, place id/name/address, geohash
- engagement: like/comment/share/repost/view/bookmark counts and viewer state
- moderation: status, report counts, sensitive-content flags
- lifecycle: draft/scheduled/published/archived/deleted, `createdAt`, `updatedAt`

Implementation rule: keep old `posts` reads working through an adapter first. Add normalized tables only after the adapter is green.

### B. Shared Rendering Layer

Add `lib/shared/content/`:

- `models/content_item.dart`
- `models/content_media.dart`
- `data/content_repository.dart`
- `data/content_adapter.dart`
- `widgets/content_card.dart`
- `widgets/content_media_carousel.dart`
- `widgets/content_action_bar.dart`
- `widgets/content_author_header.dart`
- `widgets/content_text.dart`
- `widgets/reel_player.dart`
- `widgets/story_viewer.dart`
- `widgets/comment_likes_dialog.dart`
- `widgets/shoppable_product_strip.dart`
- `widgets/location_post_chip.dart`

Migration order:

1. Add shared widgets with adapters while old widgets remain.
2. Migrate Home.
3. Migrate Discovery/Search/Videos/Profile.
4. Migrate Messages/AI/Marketplace/Map/Admin/Ads.
5. Delete duplicates only after parity screenshots and `flutter analyze` pass.

### C. Professional Create Feature

Split `CreatePage` into a modular feature:

- `create_page.dart` becomes shell/navigation only.
- `capture/` handles camera, gallery, file import, audio, and live start.
- `editor/` handles trim, crop, aspect ratio, captions, text stickers, effects, filters, music, poll, product tags, location, schedule.
- `compose/` handles privacy, target surface, channel/group/profile, draft state, publish validation.
- `data/` owns upload queue, drafts, publish repository, local cache, retry.

Required UX:

- Draft auto-save.
- Background upload with progress/cancel/retry.
- Media order/reorder and album grouping.
- Story/reel/post/live mode picker with animated transitions.
- Product tagging for marketplace.
- Place tagging for map.
- AI assist for caption, hashtags, title, and translation.
- Professional validation before publish.

### D. Effects Strategy

Open-source-first:

- Start with Flutter-native filters: color matrices, blur, vignette, exposure/contrast/saturation, gradient overlays, LUT-like presets where feasible.
- Use existing `video_player` preview, `camera` capture, `image_picker` import.
- Evaluate open-source shader/effect packages only in a separate approval task.
- Face AR/Snapchat-grade effects require a dedicated engine. Do not add paid SDKs without approval.

Commercial/infra options to evaluate later:

- Banuba, DeepAR, Agora Extensions, or platform-native ML pipelines.
- FFmpeg/MediaKit transcoding for serious video export.

### E. Per-Surface Integration

- Home: default mixed public feed from shared `ContentRepository`.
- Notifications: notification payload links to `ContentItem` and opens shared detail view.
- Search: global content search uses shared result card and filters.
- Discovery: trending, hashtags, public channels, and reels use shared renderers.
- Videos: reels use `ReelPlayer` with shared engagement/actions.
- Messages: shared post preview and forward cards use compact `ContentCard`.
- Marketplace: shoppable posts attach product metadata and render purchase CTA.
- Map: geo posts use place metadata and open location content sheet.
- AI: AI can explain, summarize, translate, and suggest captions for `ContentItem`.
- Profile: grid/list tabs render from the same item adapter.
- Ads: promoted content is a decorated `ContentItem`, not a parallel card.
- Admin: moderation sees the same content shape plus audit/moderation metadata.

### F. Live Streaming Architecture

Use current WebRTC/call stack only for calls and lightweight live previews. For production-grade public live:

- Recommended: LiveKit self-hosted or managed compatible stack.
- Needs: room service, broadcaster token, viewer token, chat/events, moderation, recording/archive, RTMP ingest for gamers, screen share, camera switch, viewer reactions, gifts later.
- Flutter app should own UX and state; media transport should be delegated to a live stack.
- Gamer mode: screen share/RTMP, webcam overlay, category/game metadata, bitrate selector, low-latency chat, moderation queue.

### G. Phased Implementation Roadmap

Implementation must start only after approval.

1. C0: Content foundation and compatibility adapter.
2. C1: Shared rendering layer and duplicate collapse.
3. C2: Create page decomposition, drafts, upload queue.
4. C3: Editor/effects pipeline.
5. C4: Cross-surface integration.
6. C5: Professional live streaming foundation.
7. C6: Gamer live, monetization hooks, and advanced moderation.

## 3. Risks / Guardrails

- Do not change auth, payments, RLS, or security policies without explicit approval.
- Do not replace working cards in all surfaces at once.
- Do not introduce commercial SDKs or heavy media dependencies without an isolated proposal.
- Do not delete duplicate widgets until migrated surfaces pass screenshot/manual parity.
- Keep every migration additive and idempotent.
