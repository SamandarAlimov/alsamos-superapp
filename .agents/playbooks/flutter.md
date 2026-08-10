# Flutter Playbook

## Before Editing

- Identify the smallest widget/provider/service scope.
- Check current dirty files; do not overwrite unrelated edits.
- Reuse existing theme tokens and local patterns.

## UI Rules

- No RenderFlex overflow at 320px width or desktop widths.
- Keep page/tool UI functional first; avoid decorative churn.
- Prefer existing shared widgets before creating new ones.
- Use responsive constraints for fixed-format controls.

## Verification

```powershell
dart analyze
flutter build windows --debug
flutter build apk --debug
```

Run builds only when relevant to the touched surface.

