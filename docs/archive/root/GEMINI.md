# Alsamos Superapp — AI Agent Guide

## Project
- Flutter superapp (Android / Web / Desktop; iOS deferred), offline-first + SQLite.
- Backend: Supabase (Postgres, Auth, Realtime, Storage, Edge Functions) with RLS.
- State management: Riverpod-style.
- Repo root: D:\Alsamos\alsamos-superapp
- Flutter SDK: D:\web\flutter\flutter

## GOLDEN RULES (always)
1. Assume the app currently WORKS. Do not break existing, working features.
2. Make SMALL, scoped changes. One task = one concern = one commit.
3. Explain the ROOT CAUSE, show a before/after diff, and list every file you changed.
4. After changes, run `flutter analyze` and fix any new warnings you introduced.
5. Do NOT add/remove dependencies, change architecture, or rename/move files unless asked.
6. Do NOT refactor "while you're here". Stay strictly inside the task scope.

## DO NOT TOUCH (unless the task explicitly requires it)
These control data loading. Editing them has broken the app before:
- lib/features/home/data/repositories/posts_repository.dart
- lib/features/home/presentation/providers/posts_provider.dart
- lib/features/home/presentation/pages/home_page.dart
- lib/features/home/data/models/post_model.dart
- lib/features/messages/data/repositories/messages_repository.dart
- lib/features/messages/presentation/providers/messages_provider.dart
- lib/features/marketplace/.../marketplace_page.dart

If a task DOES require editing them:
- Never remove `.order()`, never swallow exceptions with empty catch blocks.
- Keep null-safety in fromJson. Do not change table/column names in .select()/.eq().
- Do not add filters that could return 0 rows.

## GIT DISCIPLINE
- A checkpoint commit exists before each task. To inspect: `git log --oneline`, `git diff`.
- If a change turns out unnecessary, revert just that hunk.
- To restore a file to a known-good commit: `git checkout <commit> -- <file>`.
- Commit format: `type(scope): summary`  (e.g. `fix(home): restore posts loading`).

## SUPABASE MIGRATIONS (strict)
- Additive and idempotent ONLY. NEVER drop/rename/alter existing columns.
- Use IF NOT EXISTS; CREATE OR REPLACE; DROP POLICY IF EXISTS before CREATE POLICY.
- To change a function's parameter default: DROP FUNCTION IF EXISTS first (Postgres 42P13),
  EXCEPT functions referenced by RLS policies.
- Guard ALTER PUBLICATION statements.
- End every migration with:  NOTIFY pgrst, 'reload schema';
- SQL is run manually in the Supabase dashboard (project ref: mbhjganbihamoiqmankv), not locally.

## UI / RESPONSIVENESS
- Breakpoints: mobile <600, tablet 600–1023, desktop >=1024.
- No RenderFlex overflow at >=320px width.
- Use existing theme tokens; no hardcoded colors.

## LANGUAGE
- Code, comments, and commit messages in English.
- Explanations to the user may be in Uzbek.