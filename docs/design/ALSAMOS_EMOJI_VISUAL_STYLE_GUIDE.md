# Alsamos Emoji Visual Style Guide

Status: pilot style direction  
Scope: static/idle quality for animated emoji, reactions, chat, comments, and story overlays  
Reference render: [alsamos_emoji_pilot_batch_v1.png](assets/alsamos_emoji_pilot_batch_v1.png)

## Goal

Alsamos emoji must feel premium at rest, before animation starts. The idle frame
is the most visible state in chat bubbles, reaction chips, message lists, and
pickers, so it must read as finished artwork rather than a fallback glyph.

The target is an original Alsamos design system with the same level of polish as
leading emoji systems, without copying Telegram, Apple, Twemoji, Noto, or any
other platform artwork.

## Benchmark Principles

Telegram, Apple, Twemoji, and Noto feel professional for different reasons:

- Strong silhouette: every emoji remains readable at small chat sizes.
- Controlled gradients: faces and objects have form, not flat fills.
- Consistent light source: highlights and shadows agree across the set.
- Confident facial linework: eyes, brows, and mouths have deliberate weight.
- Resting frame quality: even a paused animation frame looks like a complete
  static icon.
- Category consistency: faces, hands, objects, symbols, and reactions share a
  common scale and material language.

Alsamos should use these principles abstractly, then execute original shapes,
features, proportions, and motion.

## Shading Model

Light source:

- Primary light comes from the top-left at roughly 10 o'clock.
- Secondary warm fill comes from the front.
- Lower-right edge receives the strongest ambient occlusion.

Face/object surfaces:

- Base fill uses a vertical/radial gradient, lightest in the upper-left third.
- Add one soft specular highlight on glossy round forms. It should be subtle,
  not a white sticker.
- Add an orange-gold rim at the lower edge to give volume.
- Add a soft contact shadow only when the emoji is rendered as a standalone
  large object, not inside tiny chips.

Recommended face gradient:

- Highlight: `#FFF3A6`
- Base: `#FFD84D`
- Midtone: `#FFB11F`
- Lower rim: `#F47A12`
- Shadow accent: `#B85A0A`

## Linework

Facial features:

- Stroke color: deep brown-black, `#3A1B10`, never pure black unless the icon is
  intentionally graphic.
- Stroke width at 1024 canvas: 28-44 px for eyes/brows, 34-52 px for mouth
  contours.
- Ends and joins are rounded.
- Mouth interiors use layered color: dark cavity, red tongue, white teeth where
  needed.
- Brows should carry expression without copying platform-specific shapes.

Hands/objects:

- Hands use soft knuckle segmentation and orange rim shadows.
- Object outlines are thinner than face outlines, usually 18-30 px at 1024.
- Accent outlines can echo Alsamos orange.

## Color Palette

Core brand relationship:

- Alsamos orange remains the brand accent, not the face base.
- Use orange for rims, cuffs, small accents, reaction badges, and party/fire
  details.
- Avoid making every emoji orange. The set must not become one-note.

Core colors:

- Face yellow: `#FFD84D`
- Face highlight: `#FFF3A6`
- Alsamos orange: `#FF6A13`
- Warm rim: `#F47A12`
- Feature dark: `#3A1B10`
- Cheek blush: `#FF8A3D` at 25-45% opacity
- Heart red: `#FF2F45` to `#B90F22`
- Tear blue: `#1FB7FF` to `#0879D9`
- Fire: `#FFE96A`, `#FF8A18`, `#F23B17`

## Grid And Proportions

Master canvas:

- Source artboard: 1024 x 1024 px.
- Safe area: 80 px on all sides.
- Face circle diameter: 780-860 px.
- Large object diameter/height: 760-880 px.
- Small reaction chip render target: must remain readable at 18-24 logical px.
- Standalone chat emoji target: must remain crisp at 72-104 logical px.

Construction:

- All primary shapes align to the same optical center.
- Eyes sit between 38-52% of canvas height for face emoji.
- Mouth sits between 54-72% depending on expression.
- Highlights should never overlap eyes or key expression lines.
- Emoji should not touch canvas edges.

## Static And Animated Consistency

The first Lottie frame is the idle artwork. It must:

- Match the approved static design exactly.
- Use the same gradients, shadows, linework, and proportions.
- Be visually complete even when animation is disabled by accessibility settings.
- Stop on a clean resting frame after a single play.
- Avoid awkward in-between frames as the final state.

Animation layers should be named and grouped so the renderer can pause cleanly:

- `face_base`
- `face_highlight`
- `rim_shadow`
- `eyes`
- `mouth`
- `accent`
- `burst_or_secondary_motion`

## Pilot Batch

The first redrawn production batch should cover the emoji already visible in the
app today:

- Smile
- Grin
- Laughing with tears
- Heart eyes
- Halo smile
- Thumbs up
- Red heart
- Handshake
- Fire
- Party popper
- Thinking face
- Clapping hands

These 12 assets should replace the highest-frequency chat/reaction idle states
before expanding the full catalog.

## Asset Production Pipeline

Design source:

- One Figma or Illustrator master file.
- One page per category: faces, hands, symbols, objects, reactions.
- One artboard per emoji, named by Unicode key, for example `1f604`.
- Shared components for face base, highlights, cheeks, rim, eyes, brows, and
  mouth primitives.

Export:

- Export vectors to After Effects or Lottie-capable tooling.
- Export final production as Lottie JSON.
- File naming must match `animatedEmojiAssetKeys`, for example
  `assets/animated_emoji/alsamos/1f604.json`.
- Add catalog entries under `assets/animated_emoji/alsamos/metadata/catalog.json`
  only after legal/design approval.
- Run `dart run tool/emoji/validate_animated_emoji_assets.dart` before commit.

Renderer expectations:

- No TGS dependency is required.
- All production assets must be Lottie JSON.
- Idle frame is frame 0.
- End frame is a polished resting state.
- Looping is off for chat and reaction default playback.

## QA Checklist

Before shipping each emoji:

- Side-by-side check against this guide and the pilot sheet.
- Check at 18 px, 24 px, 40 px, 72 px, and 104 px logical size.
- Check on light chat background and green/patterned chat background.
- Check static mode with animations disabled.
- Check first visible play once.
- Check tap replay once.
- Check reaction burst does not affect normal message idle state.
- Check no blank fallback and no asset load exception.
- Check `flutter analyze`, targeted emoji tests, and asset validator pass.

## Rollout Plan

1. Approve this style direction and the 12-item pilot batch.
2. Redraw the 12 pilot emoji as editable vector masters.
3. Export the 12 pilot emoji to Lottie JSON.
4. Add them to the Alsamos provider/catalog ahead of Licensed/Noto fallback.
5. QA in chat bubbles, standalone emoji messages, reaction chips, context
   reaction rail, and picker.
6. Expand in waves:
   - Wave 2: top 50 reactions and chat emoji.
   - Wave 3: hands, hearts, faces, and celebration set.
   - Wave 4: objects, symbols, flags, professions, ZWJ sequences.
7. Keep Noto fallback for anything not yet redrawn.

## Legal Boundary

Do not import, trace, decompile, recolor, or derive from Telegram, Apple,
Twemoji, Noto, or any third-party emoji artwork. Benchmark quality principles
only. All Alsamos emoji assets must be original or explicitly licensed.
