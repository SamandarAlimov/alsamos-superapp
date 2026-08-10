# Bedrock Claude Workers

Use this when launching Claude Code workers through Amazon Bedrock.

## Current Setup

- `claude` is installed and available on PATH.
- Bedrock env is present:
  - `CLAUDE_CODE_USE_BEDROCK=1`
  - `AWS_REGION=us-east-1`
  - `AWS_BEARER_TOKEN_BEDROCK` present
  - `ANTHROPIC_MODEL=anthropic.claude-sonnet-5`
- `claude doctor` may still warn about Anthropic/claude.ai auth. That is not
  fatal for Bedrock-backed use when Bedrock credentials are configured.

## Launch Pattern

Prefer a task file under `.agents/tasks/` and launch through:

```powershell
.agents/start-claude-agent.ps1 -TaskFile .agents/tasks/<task>.md -Name <short-name> -Background -Worktree
```

For direct smoke tests, use a realistic task budget. The tiny `$0.01` smoke
test can fail with `budget_exhausted` even when Bedrock is reachable.

## Monitoring

```powershell
claude agents --json --cwd D:\Alsamos\alsamos-superapp
```

## Rules

- Never put secrets in task files or handoff files.
- Each worker gets a disjoint file/module scope.
- The lead agent stages and commits final integrated work.
- Workers must not stage build/generated files or unrelated dirty files.
