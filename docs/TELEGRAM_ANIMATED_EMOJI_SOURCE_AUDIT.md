# Telegram Animated Emoji Source Audit

Date: 2026-08-26

## Result

No Telegram animated emoji artwork was imported in this pass.

The existing production resolver behavior is retained while source rights are
unresolved.

## Local Repository Search

- `.tgs`: 0 files found outside generated/ephemeral directories.
- `.webp`: 0 files found outside generated/ephemeral directories.
- `.webm`: 0 files found outside generated/ephemeral directories.
- animated emoji JSON: 910 Noto Lottie files in `assets/animated_emoji/noto/`.
- previous website implementation: not found in this repository.
- Telegram emoji provenance files: not found in this repository.
- only animated non-JSON files found were unrelated `file_picker` example GIFs
  under platform `ephemeral` plugin symlinks.

## Public Source Reviewed

- Repository: `Tarikul-Islam-Anik/Telegram-Animated-Emojis`
- Location: https://github.com/Tarikul-Islam-Anik/Telegram-Animated-Emojis
- Format: animated WebP
- README provenance statement: media files are downloaded from Emojipedia and rights are reserved by Telegram.
- Status: NOT REDISTRIBUTABLE

The repository provides convenient WebP files, but the repository license is not sufficient evidence that Telegram's emoji artwork may be commercially redistributed inside Alsamos. The README's own provenance statement points away from repository-owned artwork rights.

- Source: Telegram sticker/emoji authoring documentation
- Location: https://core.telegram.org/stickers
- Format evidence: Telegram accepts `.TGS` vector animations and `.WEBM` video
  stickers/emoji.
- Status: LICENSE VERIFICATION REQUIRED

This documentation describes upload formats and technical requirements for
artists. It does not grant redistribution rights to Telegram's official
animated emoji artwork.

- Source: Emojipedia article about Telegram Telemoji
- Location: https://blog.emojipedia.org/telegrams-animated-emoji-set/
- Format/provenance evidence: Telemoji designs are Telegram animated emoji
  designs viewable on Emojipedia.
- Status: NOT REDISTRIBUTABLE

The article is useful provenance context, but it is not a redistribution license
for shipping the artwork inside Alsamos.

## Local Decision

Alsamos keeps the existing legal local animated pipeline and resolver behavior intact while Telegram asset rights remain unresolved. Future Telegram or partner artwork must be added through `licensedEmojiAssetCatalog` only after asset-specific redistribution rights are verified, imported, cataloged, and tested.

## Regeneration

Current legal animated fallback assets are the bundled Noto Animated Emoji Lottie JSON files documented in `assets/animated_emoji/ATTRIBUTION.md`.
