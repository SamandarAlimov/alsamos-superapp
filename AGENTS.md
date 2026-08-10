# Alsamos Agent Rules

This repo is a Flutter/Supabase superapp. Multiple AI agents may work here in
parallel, so keep every change scoped and reviewable.

## Project Context

- Flutter superapp for Android, Web, Windows/Desktop; iOS is deferred unless the
  task says otherwise.
- Offline-first client with SQLite/local cache.
- Backend is Supabase: Postgres, Auth, Realtime, Storage, Edge Functions, RLS.
- State management follows existing Riverpod-style providers.
- Repo root: `D:\Alsamos\alsamos-superapp`.
- Flutter SDK is expected at `D:\web\flutter\flutter`.

## Core Rules

- Assume the app currently works. Do not break working features.
- One task = one concern = one focused commit.
- Do not revert or overwrite changes you did not make.
- Do not refactor "while here"; stay inside the task scope.
- Do not add/remove dependencies, change architecture, or rename/move files
  unless the user explicitly asks.
- Never stage or commit build/generated artifacts:
  `.dart_tool/**`, `build/**`, generated plugin registrants, or platform
  ephemeral files.
- For Supabase migrations, use additive/idempotent SQL only:
  `IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`,
  `DROP POLICY IF EXISTS` before `CREATE POLICY`, guarded realtime publication
  changes, and end with `NOTIFY pgrst, 'reload schema';`.
- The user applies Supabase SQL manually unless the lead agent explicitly says
  otherwise.
- Run `dart analyze` before handing off code. Run platform builds when the task
  touches platform, dependency, or release behavior.
- Keep UI changes consistent with the existing Alsamos design system and
  Telegram-grade interaction polish.
- Code, comments, and commit messages must be in English. User-facing
  explanations can be in Uzbek.

## Fragile Files

Do not edit these unless the task explicitly requires it:

- `lib/features/home/data/repositories/posts_repository.dart`
- `lib/features/home/presentation/providers/posts_provider.dart`
- `lib/features/home/presentation/pages/home_page.dart`
- `lib/features/home/data/models/post_model.dart`
- `lib/features/messages/data/repositories/messages_repository.dart`
- `lib/features/messages/presentation/providers/messages_provider.dart`
- `lib/features/marketplace/**/marketplace_page.dart`

If a task does require them:

- Never remove existing `.order()` calls.
- Never swallow exceptions with empty `catch` blocks.
- Keep null-safety in JSON/fromMap parsing.
- Do not casually change table/column names in `.select()` or `.eq()`.
- Do not add filters that can accidentally make valid feeds/chats return zero
  rows.

## Verification

- Run `dart analyze` or `flutter analyze` after code changes.
- Run `flutter build windows --debug` and/or `flutter build apk --debug` when
  touching platform, dependency, media, notification, release, or navigation
  behavior.
- Use `tool/release_check.ps1` for release-gate validation when appropriate.

## Parallel Work Protocol

- Each worker owns a disjoint file/module scope.
- If a file is already modified by another worker, stop and report the conflict
  instead of force-editing.
- Workers should return:
  changed paths, verification commands/results, migration files, manual steps,
  and known risks.
- The lead agent integrates, resolves conflicts, verifies builds, and commits.
