# Alsamos Execution Task List

Generated from `docs/ARCHITECTURE_AUDIT.md`.

Rules:
- Keep each checkbox as one scoped task.
- `[SERIAL]` means the task touches shared/core/app/main/pubspec/router or broad cross-module state and must run alone.
- Stop and ask before touching payments, auth, RLS, or security-sensitive logic.
- Do not mark an item done unless it has: minimal fix, passing `flutter analyze`, commit, and merge when applicable.

## Phase 0: Critical Regressions

- [x] Fix home posts import/loading path
  - OWNER: home
  - Touch files: `lib/features/home/presentation/providers/posts_provider.dart`, `lib/features/home/data/repositories/posts_repository.dart`

- [x] Debug current location provider
  - OWNER: map
  - Touch files: `lib/features/map/presentation/providers/location_provider.dart`, `android/app/src/main/AndroidManifest.xml`

- [x] Fix messages loading / realtime subscription logging
  - OWNER: messaging
  - Touch files: `lib/features/messages/presentation/providers/messages_provider.dart`, `lib/features/messages/data/repositories/messages_repository.dart`

- [x] Verify AppToast migration [SERIAL]
  - OWNER: shared
  - Touch files: `lib/shared/widgets/app_toast.dart`, remaining call sites found by `rg "ScaffoldMessenger|SnackBar\\(" lib`

## Phase 1: Centralization / Architecture Refactors

- [x] Core Rollout: activity repository
  - OWNER: activity
  - Touch files: `lib/features/activity/data/activity_repository.dart`

- [x] Core Rollout: ads repository
  - OWNER: ads
  - Touch files: `lib/features/ads/data/ads_repository.dart`

- [x] Core Rollout: ai repository
  - OWNER: ai
  - Touch files: `lib/features/ai/data/ai_repository.dart`

- [x] Core Rollout: channels repository
  - OWNER: channels
  - Touch files: `lib/features/channels/data/channels_repository.dart`

- [x] Core Rollout: comments repository
  - OWNER: comments
  - Touch files: `lib/features/comments/data/comments_repository.dart`

- [x] Core Rollout: create repository
  - OWNER: create
  - Touch files: `lib/features/create/data/create_repository.dart`

- [x] Core Rollout: home posts repository
  - OWNER: home
  - Touch files: `lib/features/home/data/repositories/posts_repository.dart`

- [x] Core Rollout: map repository
  - OWNER: map
  - Touch files: `lib/features/map/data/map_repository.dart`

- [x] Core Rollout: messages admin + stickers repositories
  - OWNER: messaging
  - Touch files: `lib/features/messages/data/repositories/conversation_admin_repository.dart`, `lib/features/messages/data/repositories/stickers_repository.dart`

- [x] Core Rollout: notifications repository
  - OWNER: notifications
  - Touch files: `lib/features/notifications/data/notifications_repository.dart`

- [x] Core Rollout: orders repository
  - OWNER: orders
  - Touch files: `lib/features/orders/data/orders_repository.dart`

- [x] Core Rollout: profile repository
  - OWNER: profile
  - Touch files: `lib/features/profile/data/profile_repository.dart`

- [x] Core Rollout: settings repositories
  - OWNER: settings
  - Touch files: `lib/features/settings/data/history_repository.dart`, `lib/features/settings/data/settings_repository.dart`

- [x] Core Rollout: stories repositories
  - OWNER: stories
  - Touch files: `lib/features/stories/data/stories_repository.dart`, `lib/features/stories/data/story_highlights_repository.dart`

- [x] Core Rollout: videos repository
  - OWNER: videos
  - Touch files: `lib/features/videos/data/video_repository.dart`

- [ ] Core Rollout: marketplace repository [BLOCKED]
  - OWNER: marketplace
  - Touch files: `lib/features/marketplace/data/marketplace_repository.dart`
  - Blocked: file has pre-existing uncommitted edits in main; skip to avoid overwriting active work.

- [ ] Core Rollout: messages repository [BLOCKED]
  - OWNER: messaging
  - Touch files: `lib/features/messages/data/repositories/messages_repository.dart`
  - Blocked: file has pre-existing uncommitted edits in main; skip to avoid overwriting active work.

- [ ] Core Rollout: search repository [FLAGGED]
  - OWNER: search
  - Touch files: `lib/features/search/data/search_repository.dart`, `lib/features/search/data/repositories/search_repository.dart`
  - Flagged: both duplicate `SearchRepository` files are imported by real providers; needs product/architecture decision before migration.

- [ ] Core Rollout: payment repository [EXCLUDED]
  - OWNER: payment
  - Touch files: `lib/features/payment/data/payment_repository.dart`
  - Excluded: payment/security-sensitive repository requires explicit approval.

- [ ] Core Rollout: admin repository [EXCLUDED]
  - OWNER: admin
  - Touch files: `lib/features/admin/data/admin_repository.dart`
  - Excluded: admin/security-sensitive repository requires explicit approval.

- [x] Create BaseRepository pilot [SERIAL]
  - OWNER: core
  - Touch files: `lib/core/data/base_repository.dart`, `lib/features/home/data/repositories/posts_repository.dart`

- [x] Extract SupabaseDataSource pilot [SERIAL]
  - OWNER: core
  - Touch files: `lib/core/data/supabase_data_source.dart`, `lib/features/home/data/repositories/posts_repository.dart`

- [ ] Create AppError sealed class [SERIAL]
  - OWNER: core
  - Touch files: `lib/core/errors/app_error.dart`, `lib/core/data/base_repository.dart`

- [ ] Extend AppToast with error mapping [SERIAL]
  - OWNER: shared
  - Touch files: `lib/shared/widgets/app_toast.dart`, `lib/core/errors/app_error.dart`

- [x] Create auth_guard extension [SERIAL]
  - OWNER: core/auth
  - Touch files: `lib/core/auth/auth_guard.dart`, `lib/features/auth/presentation/providers/auth_provider.dart`

- [ ] Add null-safety guards for unauthenticated repository calls [SERIAL]
  - OWNER: core
  - Touch files: `lib/core/auth/auth_guard.dart`, `lib/features/activity/data/activity_repository.dart`, `lib/features/admin/data/admin_repository.dart`, `lib/features/ads/data/ads_repository.dart`, `lib/features/ai/data/ai_repository.dart`, `lib/features/channels/data/channels_repository.dart`, `lib/features/comments/data/comments_repository.dart`, `lib/features/create/data/create_repository.dart`, `lib/features/home/data/repositories/posts_repository.dart`, `lib/features/map/data/map_repository.dart`, `lib/features/marketplace/data/marketplace_repository.dart`, `lib/features/messages/data/repositories/conversation_admin_repository.dart`, `lib/features/messages/data/repositories/messages_repository.dart`, `lib/features/messages/data/repositories/stickers_repository.dart`, `lib/features/miniapps/data/mini_apps_repository.dart`, `lib/features/notifications/data/notifications_repository.dart`, `lib/features/orders/data/orders_repository.dart`, `lib/features/payment/data/payment_repository.dart`, `lib/features/profile/data/profile_repository.dart`, `lib/features/search/data/search_repository.dart`, `lib/features/search/data/repositories/search_repository.dart`, `lib/features/settings/data/history_repository.dart`, `lib/features/settings/data/settings_repository.dart`, `lib/features/stories/data/stories_repository.dart`, `lib/features/stories/data/story_highlights_repository.dart`, `lib/features/videos/data/video_repository.dart`

- [ ] Consolidate duplicate widgets [SERIAL]
  - OWNER: shared
  - Touch files: `lib/features/comments/presentation/widgets/comment_likes_dialog.dart`, `lib/shared/widgets/comment_likes_dialog.dart`, `lib/features/home/presentation/widgets/post_card.dart`, `lib/features/discovery/presentation/widgets/post_card.dart`, `lib/features/stories/presentation/widgets/story_viewer.dart`, `lib/features/discovery/presentation/widgets/story_viewer.dart`

- [ ] Create formatters utility [SERIAL]
  - OWNER: shared
  - Touch files: `lib/shared/utils/formatters.dart`, date/number/string formatting call sites found by `rg "DateFormat|timeago|NumberFormat" lib`

## Phase 2: Scalability / Performance

- [ ] Add cursor pagination to messages
  - OWNER: messaging
  - Touch files: `lib/features/messages/data/repositories/messages_repository.dart`, `lib/features/messages/presentation/providers/messages_provider.dart`, `lib/features/messages/presentation/pages/chat_page.dart`

- [ ] Add pagination / server aggregation plan to activity logs
  - OWNER: activity
  - Touch files: `lib/features/activity/data/activity_repository.dart`, optional migration `supabase/migrations/*activity_summary*.sql`

- [ ] Optimize posts N+1 queries
  - OWNER: home
  - Touch files: `lib/features/home/data/repositories/posts_repository.dart`, `lib/features/home/data/models/post_model.dart`, optional migration `supabase/migrations/*fetch_posts_optimized*.sql`

- [ ] Replace SELECT * with explicit column lists
  - OWNER: data
  - Touch files: `lib/features/activity/data/activity_repository.dart`, `lib/features/admin/data/admin_repository.dart`, `lib/features/ads/data/ads_repository.dart`, `lib/features/ai/data/ai_repository.dart`, `lib/features/channels/data/channels_repository.dart`, `lib/features/comments/data/comments_repository.dart`, `lib/features/create/data/create_repository.dart`, `lib/features/home/data/repositories/posts_repository.dart`, `lib/features/map/data/map_repository.dart`, `lib/features/marketplace/data/marketplace_repository.dart`, `lib/features/messages/data/repositories/conversation_admin_repository.dart`, `lib/features/messages/data/repositories/messages_repository.dart`, `lib/features/messages/data/repositories/stickers_repository.dart`, `lib/features/miniapps/data/mini_apps_repository.dart`, `lib/features/notifications/data/notifications_repository.dart`, `lib/features/orders/data/orders_repository.dart`, `lib/features/payment/data/payment_repository.dart`, `lib/features/profile/data/profile_repository.dart`, `lib/features/search/data/search_repository.dart`, `lib/features/search/data/repositories/search_repository.dart`, `lib/features/settings/data/history_repository.dart`, `lib/features/settings/data/settings_repository.dart`, `lib/features/stories/data/stories_repository.dart`, `lib/features/stories/data/story_highlights_repository.dart`, `lib/features/videos/data/video_repository.dart`

- [ ] Add SQLite caching to posts
  - OWNER: home
  - Touch files: `lib/features/home/data/local/posts_local_store.dart`, `lib/features/home/data/repositories/posts_repository.dart`, `lib/features/home/presentation/providers/posts_provider.dart`

- [ ] Add SQLite caching to profiles
  - OWNER: profile
  - Touch files: `lib/features/profile/data/local/profiles_local_store.dart`, `lib/features/profile/data/profile_repository.dart`, `lib/features/profile/presentation/providers/profile_provider.dart`

- [ ] Fix realtime subscription disposal
  - OWNER: messaging
  - Touch files: `lib/features/messages/presentation/providers/messages_provider.dart`

- [ ] Convert postsProvider to AsyncNotifier
  - OWNER: home
  - Touch files: `lib/features/home/presentation/providers/posts_provider.dart`, `lib/features/home/presentation/pages/home_page.dart`

- [ ] Replace eager ListView usage with lazy builders
  - OWNER: UI modules
  - Touch files: `lib/features/map/presentation/pages/map_page.dart`, `lib/features/map/presentation/widgets/location_history_panel.dart`, `lib/features/notifications/presentation/pages/notifications_page.dart`, `lib/features/messages/presentation/pages/messages_page.dart`, plus exact files returned by `rg "ListView\\(" lib/features`

- [ ] Add RepaintBoundary to animation-heavy widgets
  - OWNER: UI modules
  - Touch files: `lib/features/map/presentation/pages/map_page.dart`, `lib/features/home/presentation/pages/home_page.dart`, `lib/features/stories/presentation/widgets/story_viewer.dart`

- [ ] Move activity aggregation to isolate
  - OWNER: activity
  - Touch files: `lib/features/activity/data/activity_repository.dart`

- [ ] Audit and add const constructors [SERIAL]
  - OWNER: all-ui
  - Touch files: Dart files touched by `dart fix --apply --code=prefer_const_constructors`, reviewed before commit

- [ ] Add Supabase performance indexes
  - OWNER: database
  - Touch files: `supabase/migrations/*add_performance_indexes.sql`

- [ ] Implement OfflineRepository mixin [SERIAL]
  - OWNER: core
  - Touch files: `lib/core/data/offline_repository.dart`, `lib/features/home/data/repositories/posts_repository.dart`, `lib/features/profile/data/profile_repository.dart`, `lib/features/stories/data/stories_repository.dart`

- [ ] Preload SVG assets [SERIAL]
  - OWNER: app
  - Touch files: `lib/main.dart`, `pubspec.yaml`, SVG asset paths discovered under `assets/`

- [ ] Add autoDispose + keepAlive TTL to providers [SERIAL]
  - OWNER: providers
  - Touch files: `lib/features/home/presentation/providers/posts_provider.dart`, `lib/features/profile/presentation/providers/profile_provider.dart`, `lib/features/stories/presentation/providers/stories_provider.dart`, other provider files selected after read-only audit

## Phase 3: Animation Performance Polish

- [ ] Optimize MapPage composition
  - OWNER: map
  - Touch files: `lib/features/map/presentation/pages/map_page.dart`, new local widgets under `lib/features/map/presentation/widgets/`

- [ ] Add RepaintBoundary to Home PostCard
  - OWNER: home
  - Touch files: `lib/features/home/presentation/widgets/post_card.dart`

- [ ] Optimize SkeletonShimmer [SERIAL]
  - OWNER: shared
  - Touch files: `lib/shared/widgets/skeleton_shimmer.dart`

- [ ] Lazy-load story media
  - OWNER: stories
  - Touch files: `lib/features/stories/presentation/widgets/story_viewer.dart`, `lib/features/stories/presentation/providers/stories_provider.dart`

- [ ] Profile animation performance pass
  - OWNER: profile
  - Touch files: `lib/features/profile/presentation/pages/profile_page.dart`, `lib/features/profile/presentation/pages/user_profile_page.dart`, `lib/features/profile/presentation/widgets/edit_profile_dialog.dart`, `lib/features/profile/presentation/widgets/follow_message_buttons.dart`

## Content Engine Roadmap

### Phase C0: Foundation / Compatibility

- [x] Add unified content models and adapters [SERIAL]
  - OWNER: content-core
  - Touch files: `lib/shared/content/models/content_item.dart`, `lib/shared/content/models/content_media.dart`, `lib/shared/content/data/content_adapter.dart`, `lib/features/home/data/models/post_model.dart`

- [x] Add content repository facade [SERIAL]
  - OWNER: content-core
  - Touch files: `lib/shared/content/data/content_repository.dart`, `lib/core/data/supabase_data_source.dart`, `lib/features/home/data/repositories/posts_repository.dart`, `lib/features/videos/data/video_repository.dart`

- [x] Add content foundation migration [SERIAL]
  - OWNER: database
  - Touch files: `supabase/migrations/*content_engine_foundation.sql`

- [x] Normalize current post schema compatibility reads
  - OWNER: content-core
  - Touch files: `lib/shared/content/data/content_adapter.dart`, `lib/features/home/data/models/post_model.dart`, `lib/features/map/data/map_repository.dart`, `lib/features/marketplace/data/marketplace_repository.dart`

### Phase C1: Shared Rendering Layer

- [ ] Add shared content card widgets [SERIAL]
  - OWNER: shared-content
  - Touch files: `lib/shared/content/widgets/content_card.dart`, `lib/shared/content/widgets/content_author_header.dart`, `lib/shared/content/widgets/content_text.dart`, `lib/shared/content/widgets/content_action_bar.dart`, `lib/shared/content/widgets/content_media_carousel.dart`

- [ ] Collapse Home PostCard onto shared renderer
  - OWNER: home
  - Touch files: `lib/features/home/presentation/widgets/post_card.dart`, `lib/features/home/presentation/widgets/post_media_carousel.dart`, `lib/features/home/presentation/pages/home_page.dart`

- [ ] Collapse Discovery/Search/Videos/Profile renderers
  - OWNER: discovery
  - Touch files: `lib/features/discovery/presentation/widgets/post_card.dart`, `lib/features/search/presentation/widgets/media_post_card.dart`, `lib/features/videos/presentation/pages/videos_page.dart`, `lib/features/profile/presentation/pages/profile_page.dart`, `lib/features/profile/presentation/pages/user_profile_page.dart`

- [ ] Collapse duplicate story viewers and comment-like dialogs [SERIAL]
  - OWNER: shared-content
  - Touch files: `lib/shared/content/widgets/story_viewer.dart`, `lib/shared/content/widgets/comment_likes_dialog.dart`, `lib/features/discovery/presentation/widgets/story_viewer.dart`, `lib/features/stories/presentation/widgets/story_viewer.dart`, `lib/shared/widgets/comment_likes_dialog.dart`, `lib/features/comments/presentation/widgets/comment_likes_dialog.dart`

### Phase C2: Professional Create Flow

- [ ] Split CreatePage into shell and mode modules [SERIAL]
  - OWNER: create
  - Touch files: `lib/features/create/presentation/create_page.dart`, `lib/features/create/presentation/widgets/create_mode_shell.dart`, `lib/features/create/presentation/widgets/create_mode_selector.dart`

- [x] Extract collaborator and product-tag picker modules
  - OWNER: create
  - Touch files: `lib/features/create/presentation/widgets/create_collaborator_picker.dart`, `lib/features/create/presentation/widgets/create_product_tag_picker.dart`, `lib/features/create/presentation/create_page.dart`

- [ ] Add capture/import module
  - OWNER: create
  - Touch files: `lib/features/create/presentation/capture/content_capture_sheet.dart`, `lib/features/create/presentation/capture/camera_capture_page.dart`, `lib/features/create/presentation/capture/media_import_picker.dart`

- [ ] Add drafts and upload queue
  - OWNER: create
  - Touch files: `lib/features/create/data/create_repository.dart`, `lib/features/create/data/content_upload_queue.dart`, `lib/features/create/data/content_draft_store.dart`, `supabase/migrations/*content_drafts_uploads.sql`

- [x] Add cross-platform device-local draft store foundation
  - OWNER: create
  - Touch files: `lib/features/create/data/drafts/**`

- [x] Extract retryable upload transport and guarded Create metadata repositories
  - OWNER: create
  - Touch files: `lib/features/create/data/upload/**`, `lib/features/create/data/create_collaboration_repository.dart`, `lib/features/create/data/create_product_tag_repository.dart`, `lib/features/create/presentation/create_page.dart`

- [ ] Persist drafts and upload manifests across app restarts
  - OWNER: create
  - Touch files: `lib/features/create/data/content_draft_store.dart`, `lib/features/create/data/content_upload_queue.dart`

- [ ] Add compose/publish validation
  - OWNER: create
  - Touch files: `lib/features/create/presentation/compose/content_compose_page.dart`, `lib/features/create/presentation/compose/publish_settings_panel.dart`, `lib/features/create/data/create_repository.dart`

- [x] Wire existing Create UI publish path through ContentPostRepository [SERIAL]
  - OWNER: create
  - Touch files: `lib/features/create/presentation/create_page.dart`, `lib/shared/content/models/content_item.dart`

### Phase C3: Editor and Effects

- [ ] Add image/video editor foundation
  - OWNER: create-effects
  - Touch files: `lib/features/create/presentation/editor/content_editor_page.dart`, `lib/features/create/presentation/editor/media_timeline.dart`, `lib/features/create/presentation/editor/trim_controls.dart`, `lib/features/create/presentation/editor/crop_aspect_controls.dart`

- [ ] Add open-source filter/effect presets
  - OWNER: create-effects
  - Touch files: `lib/features/create/effects/effect_preset.dart`, `lib/features/create/effects/effect_preview.dart`, `lib/features/create/effects/filter_matrix.dart`, `lib/features/create/presentation/editor/effects_panel.dart`

- [ ] Add stickers/text/music/poll/product/location overlays
  - OWNER: create-effects
  - Touch files: `lib/features/create/presentation/editor/overlay_canvas.dart`, `lib/features/create/presentation/widgets/music_picker.dart`, `lib/features/create/presentation/widgets/poll_creator.dart`, `lib/features/create/presentation/editor/product_tag_panel.dart`, `lib/features/create/presentation/editor/location_tag_panel.dart`

### Phase C4: Surface Integrations

- [x] Add shared visibility-aware music playback for posts and stories
  - OWNER: shared-content
  - Touch files: `lib/shared/audio/**`, `lib/shared/widgets/music_attachment.dart`, `lib/shared/stories/story_music_pill.dart`, story viewers

- [x] Enforce active-reel video/music ownership and soundtrack fallback
  - OWNER: videos
  - Touch files: `lib/features/videos/presentation/pages/videos_page.dart`, `lib/shared/audio/**`

- [ ] Integrate content engine into messages and AI
  - OWNER: messaging-ai
  - Touch files: `lib/features/messages/presentation/widgets/shared_post_preview.dart`, `lib/features/messages/data/repositories/messages_repository.dart`, `lib/features/ai/presentation/pages/ai_page.dart`, `lib/features/ai/presentation/providers/ai_provider.dart`

- [ ] Integrate shoppable posts into marketplace
  - OWNER: marketplace
  - Touch files: `lib/features/marketplace/data/marketplace_repository.dart`, `lib/features/marketplace/presentation/widgets/video_commerce_section.dart`, `lib/shared/content/widgets/shoppable_product_strip.dart`

- [ ] Integrate location posts into map
  - OWNER: map
  - Touch files: `lib/features/map/data/map_repository.dart`, `lib/features/map/presentation/pages/map_page.dart`, `lib/shared/content/widgets/location_post_chip.dart`

- [ ] Integrate admin, ads, notifications
  - OWNER: admin-ads-notifications
  - Touch files: `lib/features/admin/presentation/widgets/admin_content_management.dart`, `lib/features/admin/data/admin_repository.dart`, `lib/features/ads/presentation/widgets/feed_ad_card.dart`, `lib/features/ads/presentation/widgets/story_ad_widget.dart`, `lib/features/notifications/data/notifications_repository.dart`, `lib/features/notifications/presentation/pages/notifications_page.dart`

### Phase C5: Professional Live Streaming

- [ ] Add live streaming architecture decision document [SERIAL]
  - OWNER: live
  - Touch files: `docs/LIVE_STREAMING_ARCHITECTURE.md`

- [ ] Add live room/session model and repository
  - OWNER: live
  - Touch files: `lib/features/live/data/live_repository.dart`, `lib/features/live/data/live_models.dart`, `supabase/migrations/*live_stream_sessions.sql`

- [ ] Add broadcaster and viewer shell
  - OWNER: live
  - Touch files: `lib/features/create/presentation/widgets/live_stream_page.dart`, `lib/features/live/presentation/pages/live_broadcaster_page.dart`, `lib/features/live/presentation/pages/live_viewer_page.dart`

### Phase C6: Gamer Live and Advanced Monetization Hooks

- [ ] Add gamer live mode shell
  - OWNER: live
  - Touch files: `lib/features/live/presentation/widgets/gamer_live_controls.dart`, `lib/features/live/presentation/widgets/stream_category_picker.dart`, `lib/features/live/data/live_models.dart`

- [ ] Add live moderation and reaction overlays
  - OWNER: live
  - Touch files: `lib/features/live/presentation/widgets/live_moderation_panel.dart`, `lib/features/live/presentation/widgets/live_reaction_overlay.dart`, `lib/features/live/data/live_repository.dart`, `supabase/migrations/*live_moderation_reactions.sql`

- [ ] Add shoppable/live ad hooks without payment changes
  - OWNER: marketplace-ads-live
  - Touch files: `lib/shared/content/widgets/shoppable_product_strip.dart`, `lib/features/live/presentation/widgets/live_product_overlay.dart`, `lib/features/ads/presentation/widgets/feed_ad_card.dart`
