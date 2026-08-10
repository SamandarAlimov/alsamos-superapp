# AI Office Setup Handoff

Date: 2026-07-16

## Completed

- Added root `AGENTS.md` as the shared agent guide.
- Added `.agents/` coordination workspace:
  - `README.md`
  - `PLAYBOOK.md`
  - `QUEUE.md`
  - `STATUS.md`
  - `TASK_TEMPLATE.md`
  - `playbooks/flutter.md`
  - `playbooks/supabase-migrations.md`
  - `playbooks/release-check.md`
  - `start-claude-agent.ps1`
- Verified Claude Code is installed: `2.1.210`.
- Verified Bedrock-related env exists:
  - `CLAUDE_CODE_USE_BEDROCK=1`
  - `AWS_REGION=us-east-1`
  - `AWS_BEARER_TOKEN_BEDROCK` present
  - `ANTHROPIC_MODEL=anthropic.claude-sonnet-5`
- Verified `claude agents --json` works and shows active sessions.

## Notes

- `claude doctor` still warns that Anthropic/claude.ai auth is not active.
  Bedrock env appears configured, so Claude workers should be launched with
  realistic budgets instead of the tiny smoke-test budget.
- The worktree already has unrelated dirty files. Future workers must avoid
  staging those unless their task explicitly owns them.

## Next Step

Put the next concrete product task in `.agents/QUEUE.md`, then split it into
disjoint worker tasks using `.agents/TASK_TEMPLATE.md`.

