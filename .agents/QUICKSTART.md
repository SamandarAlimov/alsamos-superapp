# AI Page Redesign — Quick Start Guide

👋 Welcome! This guide gets you up to speed in 5 minutes.

---

## 📍 You Are Here

**Phase 1 Complete:** Foundation & Unified Input (3/11 tasks)  
**Next Task:** Sidebar Navigation Rebuild  
**Build Status:** ✅ 100% Clean

---

## 🎯 What We Built

### 1. The Big Fix: Unified Input ✨
**Problem:** Users had to manually toggle between "Chat" and "Imagine" modes. If they were in the wrong mode, nothing happened when they sent a message.

**Solution:** Removed the toggle. Now one intelligent input detects intent:
- Type "draw a cat" → auto-generates image
- Type "hello" → regular chat
- Ambiguous requests get a confirmation dialog

### 2. Complete Data Model
Built 11 new models (AiMessageV2, AiProject, AiArtifact, etc.) with:
- Branching conversations
- Citations & footnotes
- Artifact versioning
- Project folders
- Connector framework
- Plugin system

### 3. New Composer Widget
Drop-in replacement for old composer with:
- Intent detection hints
- Attachment support
- Voice button (placeholder)
- Auto-growing input (1-6 lines)
- Model selector

---

## 📖 Essential Reading (in order)

### First: Read This (5 min)
**`.agents/STATUS.md`** — Current status, completed work, what's next

### Second: Architecture Overview (15 min)
**`.agents/tasks/AI_PAGE_REDESIGN_ARCHITECTURE.md`** — Read sections 1-3 only:
1. Executive Summary
2. Component Architecture
3. State Management Plan

Skip sections 4-11 for now (you'll read them as you build each feature).

### Third: Phase 1 Handoff (10 min)
**`.agents/handoffs/2026-08-04-ai-page-redesign-phase1.md`** — Detailed context on what was built and why.

---

## 🚀 Start Building Task #4 (Sidebar)

### Quick Overview
Replace the current minimal sidebar (only recent chats) with:
```
┌─────────────────┐
│ [+ New Chat]    │ ← Always visible, gradient button
│ [Search...]     │ ← Fuzzy search across all content
│                 │
│ ▸ Projects      │ ← Collapsible sections
│ ▸ Artifacts     │
│ ▸ Connectors    │
│ ▸ Plugins       │
│ ▾ Recents      │ ← Default open
│   • Today       │
│   • Yesterday   │
│   • Last 7 days │
│                 │
│ [User Profile]  │ ← Pinned at bottom
└─────────────────┘
```

### Implementation Steps

**1. Read the Architecture (5 min)**
- Open `.agents/tasks/AI_PAGE_REDESIGN_ARCHITECTURE.md`
- Jump to Section 2: "Component Architecture"
- Find the "AISidebar" widget tree

**2. Check Current Sidebar (5 min)**
- Open `lib/features/ai/presentation/pages/ai_page.dart`
- Find the `_sidebar()` method (~line 200)
- Understand current structure (it's simple: header + list + footer)

**3. Create New Widget File (30 min)**
Create `lib/features/ai/presentation/widgets/ai_sidebar_v2.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';

class AISidebarV2 extends ConsumerStatefulWidget {
  final bool isDrawer;
  
  const AISidebarV2({
    super.key,
    this.isDrawer = false,
  });
  
  @override
  ConsumerState<AISidebarV2> createState() => _AISidebarV2State();
}

class _AISidebarV2State extends ConsumerState<AISidebarV2> {
  // TODO: Add section expanded states
  
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    
    return Container(
      width: widget.isDrawer ? 300 : 280,
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: 0.8),
        border: widget.isDrawer 
            ? null 
            : Border(right: BorderSide(color: c.border.withValues(alpha: 0.5))),
      ),
      child: Column(
        children: [
          _buildHeader(c),
          _buildNewChatButton(c),
          _buildSearchBar(c),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildProjectsSection(c),
                  _buildArtifactsSection(c),
                  _buildConnectorsSection(c),
                  _buildPluginsSection(c),
                  _buildRecentsSection(c),
                ],
              ),
            ),
          ),
          _buildUserFooter(c),
        ],
      ),
    );
  }
  
  Widget _buildHeader(AlsamosColors c) {
    // TODO: Logo + title + close button (mobile)
    return Container();
  }
  
  Widget _buildNewChatButton(AlsamosColors c) {
    // TODO: Gradient button
    return Container();
  }
  
  // ... implement other sections
}
```

**4. Create Collapsible Section Widget (20 min)**
Create `lib/features/ai/presentation/widgets/collapsible_section.dart`:

```dart
class CollapsibleSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final bool defaultOpen;
  
  // ... implementation
}
```

**5. Wire to Existing Page (10 min)**
In `ai_page.dart`:
```dart
// Add at top
import 'widgets/ai_sidebar_v2.dart';

// In build() method, replace:
if (!mobile) _sidebar(c, state, mobile: false),
// With:
if (!mobile) const AISidebarV2(),

// For mobile drawer:
drawer: mobile ? const AISidebarV2(isDrawer: true) : null,
```

**6. Test (10 min)**
- Run app
- Verify sidebar appears on desktop
- Verify drawer slides in on mobile
- Check theming in light/dark modes

### Total Time: ~1.5 hours for basic structure

---

## 🧪 Testing as You Go

After each section implementation:
```bash
# Check for errors
flutter analyze lib/features/ai/presentation/widgets/ai_sidebar_v2.dart

# Hot reload and visually verify
# (Run app in debug mode, make changes, save file)
```

---

## 💡 Tips

1. **Start Simple:** Implement sections as empty containers first, then flesh out
2. **Use Existing Patterns:** Copy styling from current sidebar (`_sidebar()` method)
3. **Mobile First:** Get drawer working before tackling desktop persistent mode
4. **Empty States:** Add friendly messages like "No projects yet — create one to organize chats"
5. **Ask for Help:** If stuck for >30 min, consult the architecture doc or ask team

---

## 📞 Need Help?

**Stuck on:**
- Data models? → Read `lib/features/ai/data/ai_models_v2.dart` doc comments
- State management? → Check `lib/features/ai/presentation/providers/ai_state_v2.dart`
- Styling? → Review `lib/app/theme/app_theme.dart` for design tokens
- Current code? → Search existing AI page: `lib/features/ai/presentation/pages/ai_page.dart`

**Common Issues:**
- "AlsamosColors not found" → Import `import '../../../../app/theme/app_theme.dart';`
- "Riverpod errors" → Make sure widget extends `ConsumerStatefulWidget`
- "Icons not showing" → Import `import 'package:lucide_flutter/lucide_flutter.dart';`

---

## ✅ Definition of Done (Task #4)

- [ ] Sidebar renders on desktop (persistent)
- [ ] Sidebar renders on mobile (drawer)
- [ ] New Chat button works
- [ ] Search bar exists (stub is fine)
- [ ] All 5 sections exist (Projects, Artifacts, Connectors, Plugins, Recents)
- [ ] Sections can expand/collapse
- [ ] Empty states show when sections are empty
- [ ] User profile footer shows
- [ ] Light mode looks good
- [ ] Dark mode looks good
- [ ] `flutter analyze` passes with 0 errors

---

## 🎉 You're Ready!

This foundation is solid. The hard architectural decisions are made. Now it's execution.

Start with the sidebar, then message rendering, then artifacts panel. Each task builds on the previous one.

**Good luck! 🚀**

---

_Created: 2026-08-04_  
_Last Updated: 2026-08-04_  
_Next Review: After Task #4 completion_
