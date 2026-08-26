# Local Animated Emoji Setup

Alsamos bundles its local animated emoji pack in the repository under
`assets/animated_emoji/`.

## Asset Location

- Primary bundled pack: `assets/animated_emoji/noto/`
- Runtime manifest: `assets/animated_emoji/manifest.json`
- Generated Dart catalog:
  `lib/shared/communication/emoji/bundled_animated_emoji_pack.dart`
- Attribution: `assets/animated_emoji/ATTRIBUTION.md`

The current committed pack contains Google Noto Animated Emoji Lottie JSON
assets. They are bundled with the app and do not require a Telegram API,
Telegram account, or runtime download.

## Import Or Update

Run the importer from the repository root:

```powershell
dart run tool\emoji\import_animated_emoji_pack.dart
```

Optional arguments:

```powershell
dart run tool\emoji\import_animated_emoji_pack.dart --source assets\animated_emoji\noto --manifest assets\animated_emoji\manifest.json --dart lib\shared\communication\emoji\bundled_animated_emoji_pack.dart
```

The importer scans `.json`, `.tgs`, `.webm`, and `.webp` files, normalizes
codepoint filenames into stable emoji IDs, writes a deterministic JSON manifest,
and regenerates the Dart catalog used by the runtime resolver.

## Validate

Run:

```powershell
dart run tool\emoji\validate_animated_emoji_assets.dart
```

The validator checks the manifest, generated Dart catalog, asset readability,
duplicate IDs, duplicate emoji mappings, unsupported extensions, malformed JSON,
unsafe paths, orphan assets, and missing files.

## Mapping Report

The importer prints:

- files found
- valid files
- mapped emoji
- invalid files
- ambiguous/conflicting mappings
- duplicates
- coverage percentage

The same summary is stored in `assets/animated_emoji/manifest.json`.

## Run The App

```powershell
flutter pub get
flutter run -d chrome
```

Open Messages, open the emoji picker, and select an emoji.

## Manual Checks

- Picker: open the emoji picker and confirm visible cells animate.
- Single emoji: send `😂`; it should render large at the existing standalone
  size.
- Multi emoji: send `😂 ❤️ 🔥 🎉`; existing multi-emoji sizing must remain.
- Inline emoji: send `Salom 😂`; it must stay inside the normal message card.
- Reactions: long-press a message and pick a reaction; the reaction chip uses
  the same animated emoji resolver.
- Fallback: unsupported or missing emoji fall back to Noto/Unicode rather than
  crashing or showing a blank box.

## Runtime Resolver Order

1. Bundled repository animated emoji pack
2. Existing verified/licensed catalog hook
3. Existing Noto Lottie pack
4. Unicode fallback

## Licensing And Provenance

The committed pack is Google Noto Animated Emoji from
`https://googlefonts.github.io/noto-emoji-animation/`, documented in
`assets/animated_emoji/ATTRIBUTION.md` as CC BY 4.0.

If this repository is later used for public or commercial distribution, the
artwork must have appropriate licensing, attribution, and product/legal review,
or be replaced with original/properly licensed assets.
