param(
  [Parameter(Mandatory = $true)]
  [string]$TaskFile,

  [Parameter(Mandatory = $true)]
  [string]$Name,

  [string]$Model = "sonnet",
  [string]$Effort = "medium",
  [switch]$Background,
  [switch]$Worktree
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $TaskFile)) {
  throw "Task file not found: $TaskFile"
}

$task = Get-Content -LiteralPath $TaskFile -Raw
$repo = (Resolve-Path ".").Path

$system = @"
You are a scoped Alsamos worker agent.
Follow AGENTS.md and .agents/PLAYBOOK.md.
Do not revert other people's changes.
Do not stage build/generated artifacts.
Keep edits within the task ownership section.
Return changed paths and verification results.
"@

$claudeArgs = @(
  "--model", $Model,
  "--effort", $Effort,
  "--name", $Name,
  "--append-system-prompt", $system,
  "--add-dir", $repo
)

if ($Background) { $claudeArgs += "--bg" }
if ($Worktree) { $claudeArgs += @("--worktree", $Name) }

$claudeArgs += $task

Write-Host "Starting Claude agent '$Name' with model '$Model'..."
claude @claudeArgs
