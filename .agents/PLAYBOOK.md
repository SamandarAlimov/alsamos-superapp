# Multi-Agent Playbook

## Splitting Work

Good parallel tasks have disjoint write scopes:

- UI-only widget polish
- Repository/provider fix
- Migration/RLS authoring
- Test or verification pass
- Read-only audit

Avoid assigning two workers to the same file unless the lead is intentionally
sequencing them.

## Worktree Strategy

For larger worker tasks, use Claude Code `--worktree` so each worker gets an
isolated git worktree. The lead integrates after review.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .agents/start-claude-agent.ps1 `
  -TaskFile .agents/tasks/example.md `
  -Name messages-worker `
  -Model sonnet `
  -Background
```

## Review Gate

Before integration, check:

- Does the patch touch only owned files?
- Does it preserve existing user changes?
- Does it avoid generated/build files?
- Does it pass `dart analyze`?
- Are migrations additive/idempotent?

