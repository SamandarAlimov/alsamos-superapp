# Create flow parity: superapp <-> web

Last updated: 2026-08-31

Peer repository: `SamandarAlimov/socialalsamos` (Vite + React + TypeScript web
client). The full plan with audit details lives there in
`docs/CREATE-PRO-PLAN.md`. This file is the superapp-side contract.

Both clients talk to the **same Supabase project**. Any create capability must
exist as a database contract first, then be consumed by both clients. No
business logic is duplicated per client.

## 1. Shared backend contract

If any item below changes, both repositories must be updated in the same
work item.

| Area | Contract |
| --- | --- |
| Publish a post | `atomic_create_publish` RPC + `post_media`, `post_locations`, `post_music`, `polls` |
| Story lifecycle | `create_story_draft` / `activate_story_draft` / `discard_story_draft` |
| Story stickers | `story_stickers`, `respond_story_sticker`, `story_sticker_results` |
| Stickers | `search_stickers`, `touch_sticker_recent`, `trending_stickers`, `report_sticker` |
| Music | `music_tracks`, `search_music_tracks` |
| Places | `places`, `post_locations` (+ geocoder proxy once shipped) |
| Media jobs | `video_jobs` with kinds `sticker_burn`, `reel_render` |
| Collaboration | collaboration lifecycle RPCs, hard cap of 10 collaborators |
| Visibility | `create_visibility_media` rules; private/friends media must not leak public URLs |

Story publish is a two-phase flow: upload media, create a hidden draft
(returns `storyId`, `postId`, `mediaId`), attach interactive stickers, then
activate. Abandoned drafts must be discarded so storage and the post graph stay
clean. The superapp must implement the same two phases; a direct insert into
`posts` for stories is not allowed.

## 2. Migration rules

- Additive and idempotent SQL only: `IF NOT EXISTS`,
  `ADD COLUMN IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`,
  `DROP POLICY IF EXISTS` before `CREATE POLICY`, guarded realtime publication
  changes, ending with `NOTIFY pgrst, 'reload schema';`.
- SQL authored in either repository is applied manually by the user. Each phase
  keeps a checklist of migrations that still need to be applied.
- Never rename or drop columns/tables that the peer client selects.

## 3. Create feature parity matrix

| Capability | Web | Superapp (`lib/features/create`) |
| --- | --- | --- |
| Any file type as attachment | done | verify / implement |
| Rich text formatting | done | parity needed |
| Polls (5 types) | partial | parity needed |
| Location (two modes + live) | done | parity needed |
| Sticker studio | done | parity needed |
| Story draft flow | done | parity needed |
| Reel composer | done | wire with `lib/features/videos` |
| Live broadcast | done | `lib/features/live` must use the same signaling function |
| Scheduled posts | UI only, backend missing | after backend lands |
| Effects / AR filters | missing | missing |

Known backend gaps (same for both clients): no scheduled-post publisher, no
`video_jobs` worker, empty music catalog (no ingest job), effects picker is a
shim, AR filters have no runtime, no geocoder proxy, sticker NSFW check is not
enforced on upload.

## 4. Design tokens derived from the map UI

The map surface is the reference design language. The create surface must match
it on both clients. Keep these as constants in `lib/core/theme` and mirror the
same values in the web `snap-sheet` component.

| Token | Value |
| --- | --- |
| Sheet radius | 28 (mobile top corners), 24 (desktop panel) |
| Surface opacity | 0.92 mobile, 0.82 desktop, over a blurred backdrop |
| Border / ring | subtle border at ~50% opacity, 1 px light ring on desktop |
| Snap points | peek 112 px, half ~54% of viewport, full ~90% |
| Drag behaviour | velocity above 0.55 px/ms jumps to the next snap, otherwise snap to nearest |
| Grabber | 6 x 44 rounded bar, muted foreground at 35% |
| Desktop layout | fixed 376 px control panel on the left, content on the right |

Icons must be professional vector icons, never emoji glyphs.

## 5. Rollout order

Each phase runs database -> web -> superapp -> docs, and no phase starts before
the previous one meets its acceptance criteria.

1. **P1** Remove dead buttons: scheduled-post publisher + `video_jobs` worker.
2. **P2** Move create onto the map design language (snap sheet, desktop panel).
3. **P3** Real media editors: edits applied to the uploaded file, not only preview.
4. **P4** Effects and AR with shared effect slugs across clients.
5. **P5** Music ingest and licensed catalog.
6. **P6** Poll types, collaboration invite states, geocoder proxy.
7. **P7** Sticker moderation enforcement, trending shelf, usage cleanup.
8. **P8** Stability: split oversized composers, remove duplicates, add tests,
   close this parity matrix.

## 6. Working rules

- Push to `main` only.
- Never touch `.env` files.
- One task = one concern = one focused commit; do not leave shell components
  that look functional but do nothing.
- Do not edit the fragile files listed in `AGENTS.md` unless the task requires
  it, and run `dart analyze` before handing off.
