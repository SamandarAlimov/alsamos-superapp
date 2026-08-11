# Alsamos Animated Emoji System

## Licensing Decision

Recommended path: **C) Hybrid**.

Alsamos should ship a small original branded reaction set for product identity,
and use a legally redistributable open set for standard Unicode animated emoji
coverage until a paid or partner-licensed premium pack is available.

| Path | Decision | Legal risk | Notes |
| --- | --- | --- | --- |
| A. Fully original in-house set | Future branded pack | Low | Best long-term option. Alsamos owns the assets outright if the designer contract assigns copyright and source files. Higher design cost and slower catalog coverage. |
| B. Openly licensed third-party sets | Approved for standard coverage when license is explicit | Low to Medium | Google Noto Animated Emoji is published as animated emoji artwork under CC BY 4.0. Attribution is required. Twemoji graphics are CC BY 4.0 but are static, so they are useful for fallback/source style, not animated parity. OpenMoji is CC BY-SA 4.0, which adds share-alike obligations and should not be the default commercial app asset source without legal approval. |
| C. Hybrid | **Use this** | Low | Gives product polish quickly, keeps IP risk controlled, and lets Alsamos swap in licensed premium packs later without rewriting message UI. |

Rejected sources:

- Telegram, Apple, WhatsApp, Snapchat, Instagram, and other proprietary platform
  emoji/sticker/animation assets must not be copied into a shipped build unless
  Alsamos has a written license or partnership agreement for redistribution.
- GitHub mirrors, Telegram asset dumps, "free download" sites, converter output,
  or screenshots of platform assets are not acceptable licensing evidence.
- LottieFiles or marketplace packs are acceptable only when the exact asset
  pack license explicitly permits commercial redistribution inside a shipped app.

Evidence checked:

- Google Noto Animated Emoji official page:
  https://googlefonts.github.io/noto-emoji-animation/
- Google Developers Blog states the animated artwork is available under CC BY
  4.0:
  https://developers.googleblog.com/updates-to-emoji-new-characters-new-animation-new-color-customization-and-more/
- Twemoji repository states graphics are licensed under CC BY 4.0:
  https://github.com/twitter/twemoji
- OpenMoji FAQ states graphics are CC BY-SA 4.0:
  https://openmoji.org/faq/

## Technical Pipeline

Canonical internal format: **Lottie JSON**.

`.tgs` may be accepted later as an import/storage optimization, but the app
runtime should normalize to Lottie JSON metadata so Web, Windows, macOS, Linux,
iOS, and Android use one rendering path.

Technical constraints:

- Canvas: 512 x 512 px.
- Duration: target <= 3 seconds.
- Looping: all animated emoji loop.
- Max file size target: <= 64 KB for core pack; exceptions require review.
- Background: transparent only.
- Frame rate: use composition frame rate, not forced max frame rate.
- Reduced motion: obey Flutter accessibility flags and stop animation.
- Fallback: missing or failing assets render as static Unicode text, never as a
  debug/error widget in user-facing UI.

Current implementation:

- Renderer: `lib/shared/communication/emoji/animated_emoji.dart`.
- Bundled catalog: `assets/animated_emoji/noto/`.
- Generated asset key catalog:
  `lib/shared/communication/emoji/animated_emoji_catalog.dart`.
- Attribution: `assets/animated_emoji/ATTRIBUTION.md`.
- Consumers: emoji picker, emoji-only messages, reaction chips, reaction bar.

Delivery model:

1. **Now:** bundle the initial open/licensed pack in-app for offline reliability.
2. **Next:** add a signed JSON catalog from `media.alsamos.com`/MinIO:
   - `pack_id`
   - `version`
   - `license`
   - `attribution`
   - `emoji`
   - `asset_url`
   - `sha256`
   - `format`
   - `max_size_bytes`
3. Cache remote packs locally and keep bundled assets as fallback.
4. Allow pack updates without app releases once catalog signature validation is
   in place.

Authoring pipeline for original Alsamos packs:

1. Design vector source in Figma/Illustrator/Rive-compatible workflow.
2. Animate in After Effects or Rive.
3. Export Lottie JSON.
4. Validate canvas, duration, loop, transparency, and file size.
5. Compress/optimize JSON.
6. Add to catalog with license metadata and attribution.
7. Run Flutter visual QA on mobile, desktop, and web.

## Initial Catalog Scope

Launch catalog:

- Keep the current Noto Animated Emoji catalog for high-frequency reactions,
  Telegram-coverage-targeted codepoints from the imported reference lists, and
  the official Noto Animated Emoji API catalog. The current bundled catalog
  contains 910 legal Noto Lottie assets. The official API listed 881 codepoint
  entries at import time; copyright and registered-symbol animation files were
  unavailable from the upstream CDN, so those remain static Unicode fallback.
- Add only assets with clear license metadata.
- Keep static Unicode rendering for unsupported long-tail emoji.

Expansion roadmap:

1. Fill the full high-frequency chat reaction set.
2. Add category tabs for recent, smileys, gestures, love, celebration, objects,
   and branded Alsamos.
3. Add original Alsamos premium reactions.
4. Add remote catalog and cache.
5. Add pack management and server-side feature flags for premium packs.
6. Add licensed partner packs only after legal approval.

## Implementation Timeline

Phase 1: Foundation hardening, 1-2 engineering days.

- Keep the safe Lottie renderer.
- Add catalog metadata model.
- Add asset validation script.
- Ensure all message/reaction render paths use the shared renderer.

Phase 2: Catalog and cache, 3-5 engineering days.

- Implement signed remote catalog read path.
- Add local cache with bundled fallback.
- Add versioning and checksum validation.

Phase 3: Designer workflow, 3-7 design days plus 1 engineering day.

- Produce the first original Alsamos premium reaction set.
- Validate and ingest source files.
- Add attribution and ownership records.

Phase 4: Product polish, 3-5 engineering days.

- Add animated picker previews, long-press preview, recent/favorite ordering,
  and performance throttling for dense grids.
- QA desktop/mobile/web.

## Current Product Position

Alsamos can honestly present the messaging system as having a Telegram-grade
animated emoji architecture: transparent looping animation, emoji-only large
messages, reaction animations, fallback safety, and a premium-pack-ready catalog
model.

Alsamos should not claim that shipped assets are Telegram's assets unless a
written Telegram license or partnership explicitly permits that.
