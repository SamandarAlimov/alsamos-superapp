# Alsamos AI Office

This folder is the coordination workspace for Codex-led multi-agent work.

## Roles

- **Lead / Integrator:** Codex in the main workspace. Splits tasks, assigns
  scoped work, reviews patches, runs final builds, commits.
- **Explorer:** read-only codebase investigation, risk mapping, dependency
  checks, schema audits.
- **Worker:** scoped implementation in a clearly owned module or worktree.
- **Reviewer:** targeted verification, regression checks, and build/test review.

## Standard Flow

1. Put the next work item in `.agents/QUEUE.md`.
2. Lead splits it into independent tasks using `.agents/TASK_TEMPLATE.md`.
3. Workers use separate write scopes or separate git worktrees.
4. Workers report changed paths and verification.
5. Lead integrates, runs `dart analyze` and required builds, then commits.
6. Lead updates `.agents/STATUS.md`.

## Safety

- Do not let two agents edit the same file set at the same time.
- Do not stage build outputs.
- Do not run destructive commands unless the user explicitly asks.
- Keep secrets out of task files and commits.

## Claude Code

Claude Code is installed on this laptop. Use `.agents/start-claude-agent.ps1`
to launch a scoped Claude task from a task file. Claude auth/Bedrock credentials
must be valid before background workers can actually run. Bedrock-specific
launch notes live in `.agents/playbooks/bedrock-claude.md`.
