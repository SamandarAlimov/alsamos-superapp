# Agent Task Template

## Title

`<short task title>`

## Objective

What must be true when the task is complete.

## Ownership

Files/modules this worker may edit:

- `<path>`

Files/modules this worker must not edit:

- Build/generated outputs
- Unrelated dirty files

## Requirements

- Reuse existing patterns.
- Keep changes surgical.
- Add or update focused tests when practical.
- Run verification before final response.

## Verification

Run as applicable:

```powershell
dart analyze
flutter build windows --debug
flutter build apk --debug
```

## Output

Return:

- Changed paths
- Summary
- Verification results
- Migration SQL/manual steps
- Risks or follow-ups

