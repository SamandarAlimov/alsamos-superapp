# Alsamos AI Page — Complete Redesign Architecture

**Date:** 2026-08-04  
**Scope:** Transform AI page to world-class assistant (Claude.ai/ChatGPT quality)  
**Status:** Architecture Planning Phase

---

## 1. EXECUTIVE SUMMARY

### Current State Issues
- **Manual Chat/Imagine toggle** — users must switch modes; request ignored if wrong mode
- **App reopens last chat** — violates UX expectation of fresh start
- **Basic sidebar** — only shows recent conversations, no organization
- **No artifacts system** — code/documents dumped inline as text walls
- **No agentic capabilities** — cannot execute code, browse web, create files
- **Limited input** — no attachments, no voice, no slash commands
- **Basic message rendering** — no markdown, no syntax highlighting, no branching

### Target State
- **Unified intelligent input** — intent detection auto-routes to image/video/code/doc generation
- **Fresh-start default** — always land on new chat, access history via sidebar
- **Professional sidebar** — Projects, Artifacts, Connectors, Plugins, Recents sections
- **Artifact viewer** — side panel for code/docs/spreadsheets with versioning
- **Agentic execution** — sandbox code execution, file generation, web browsing (with approval gates)
- **Rich input** — attachments, voice-to-text, voice conversation, slash commands
- **Production-grade rendering** — streaming markdown, syntax-highlighted code, inline media, message branching

---

## 2. COMPONENT ARCHITECTURE

### Widget Tree Structure

```
AIPageV2 (StatefulWidget)
├─ Scaffold
│  ├─ drawer: mobile ? AISidebar(drawer: true) : null
│  └─ body: SafeArea
│     └─ Row
│        ├─ !mobile ? AISidebar(drawer: false) : null
│        └─ Expanded
│           └─ Column
│              ├─ AITopBar (model selector, settings, collapse sidebar)
│              ├─ Expanded
│              │  └─ Stack
│              │     ├─ currentView == 'chat' ? AIChatView : null
│              │     ├─ currentView == 'projects' ? AIProjectsView : null
│              │     ├─ currentView == 'artifacts' ? AIArtifactsView : null
│              │     └─ currentView == 'connectors' ? AIConnectorsView : null
│              └─ AIComposerBar (unified input)
│        └─ showArtifactPanel && !mobile ? AIArtifactPanel : null

AISidebar
├─ Column
│  ├─ Header (logo, title, close button on mobile)
│  ├─ NewChatButton (gradient primary action)
│  ├─ SearchBar (fuzzy search across titles + message content)
│  ├─ Expanded
│  │  └─ SingleChildScrollView
│  │     └─ Column
│  │        ├─ CollapsibleSection(title: "Projects", icon: folder)
│  │        │  └─ ProjectList or EmptyState
│  │        ├─ CollapsibleSection(title: "Artifacts", icon: box)
│  │        │  └─ ArtifactGrid or EmptyState
│  │        ├─ CollapsibleSection(title: "Connectors", icon: plug)
│  │        │  └─ ConnectorList or EmptyState
│  │        ├─ CollapsibleSection(title: "Plugins", icon: puzzle)
│  │        │  └─ PluginList or EmptyState
│  │        └─ CollapsibleSection(title: "Recents", icon: history, defaultOpen: true)
│  │           └─ ConversationList grouped by date
│  └─ UserProfileFooter (avatar, name, tier, settings shortcut)

AIChatView
├─ currentConversationId == null ? AIEmptyState : AIMessageList
│  ├─ AIEmptyState
│  │  ├─ Hero icon + title + description
│  │  ├─ forwardedPost ? ForwardedPostCard : null
│  │  └─ SuggestionChips or SuggestionGrid
│  └─ AIMessageList (virtualized ListView)
│     └─ for each message:
│        ├─ AIUserBubble
│        └─ AIAssistantBubble
│           ├─ MarkdownRenderer (with syntax highlighting)
│           ├─ InlineMediaViewer (images, videos)
│           ├─ InlineCitationLinks
│           ├─ MessageActions (copy, regenerate, branch, read-aloud, share)
│           └─ isStreaming ? TypingIndicator : null

AIComposerBar
├─ Column
│  ├─ attachments.isNotEmpty ? AttachmentChipsRow : null
│  └─ Container (rounded border, gradient on focus)
│     └─ Row
│        ├─ Expanded
│        │  └─ AutoGrowingTextField (minLines: 1, maxLines: 6, slash command detection)
│        ├─ AttachButton (file picker, drag-drop on desktop)
│        ├─ VoiceButton (tap-to-talk, long-press for voice conversation mode)
│        └─ SendButton (morph to stop during generation)

AIArtifactPanel (side panel, desktop only)
├─ Header (artifact title, type icon, close)
├─ Expanded
│  └─ artifact.type == 'code' ? CodeViewer
│     artifact.type == 'document' ? DocumentViewer
│     artifact.type == 'spreadsheet' ? SpreadsheetViewer
│     artifact.type == 'image' ? ImageViewer
│     : GenericViewer
└─ Footer
   └─ Row
      ├─ CopyButton
      ├─ DownloadButton
      ├─ ShareButton
      └─ VersionDropdown (1/3 history states)
```

---

## 3. STATE MANAGEMENT PLAN

### Current State (Riverpod StateNotifier)
```dart
class AiState {
  final List<AiConversation> conversations;
  final List<AiMessage> messages;
  final String? currentConversationId;
  final bool isLoading;
  final bool isGeneratingImage;
  final bool conversationsLoading;
  final String mode; // ← REMOVE THIS (no more manual toggle)
  final ForwardedPost? forwardedPost;
}
```

### New State Structure
```dart
class AiStateV2 {
  // ── Conversations & Messages ──
  final List<AiConversation> conversations;  // keep
  final List<AiMessage> messages;            // keep
  final String? currentConversationId;       // keep
  final String? currentProjectId;            // NEW: active project filter
  
  // ── Projects ──
  final List<AiProject> projects;            // NEW: folder structure
  final bool projectsLoading;
  
  // ── Artifacts ──
  final List<AiArtifact> artifacts;          // NEW: generated outputs
  final AiArtifact? activeArtifact;          // NEW: shown in side panel
  final bool artifactsLoading;
  
  // ── Connectors ──
  final List<AiConnector> connectors;        // NEW: integrations
  final bool connectorsLoading;
  
  // ── Plugins / Skills ──
  final List<AiPlugin> plugins;              // NEW: extensions
  final bool pluginsLoading;
  
  // ── UI State ──
  final String currentView;                  // 'chat' | 'projects' | 'artifacts' | 'connectors'
  final bool showArtifactPanel;              // desktop side panel visibility
  final bool sidebarCollapsed;               // rail mode toggle
  
  // ── Composer State ──
  final List<AttachedFile> attachments;      // NEW: files in composer
  final bool isVoiceMode;                    // NEW: voice conversation active
  final String? voiceTranscript;             // NEW: live transcript
  
  // ── Generation State ──
  final bool isGenerating;                   // unified (chat, image, code, doc)
  final GenerationType? generationType;      // 'text' | 'image' | 'video' | 'code' | 'document'
  final double? generationProgress;          // 0.0 - 1.0 for progress bar
  
  // ── Search & Filters ──
  final String searchQuery;                  // sidebar search
  final ConversationFilter filter;           // date range, project, type filters
  
  // ── Forwarded Content (keep for post integration) ──
  final ForwardedPost? forwardedPost;        // keep
  
  // ── Error Handling ──
  final String? lastError;                   // NEW: display inline error banners
}
```

### Notifier Actions (expanded)
```dart
class AiNotifierV2 extends StateNotifier<AiStateV2> {
  // ── Conversation Management ──
  Future<void> startNewChat({String? projectId});
  Future<void> openConversation(String conversationId);
  Future<void> deleteConversation(String conversationId);
  Future<void> renameConversation(String conversationId, String newTitle);
  Future<void> moveConversationToProject(String conversationId, String projectId);
  Future<void> exportConversation(String conversationId, ExportFormat format);
  
  // ── Message Management ──
  Future<void> sendMessage(String text, {IntentHint? hint});
  Future<void> regenerateMessage(String messageId);
  Future<void> branchMessage(String messageId, String newResponse);
  Future<void> deleteMessage(String messageId);
  
  // ── Intent Detection & Generation ──
  Future<void> generateWithIntent(String prompt, {List<AttachedFile>? files});
  Future<void> generateImage(String prompt);
  Future<void> generateVideo(String prompt);
  Future<void> executeCode(String code, String language);
  Future<void> createDocument(String instructions);
  
  // ── Projects ──
  Future<void> createProject(String name, {String? description});
  Future<void> updateProject(String projectId, {String? name, String? instructions});
  Future<void> deleteProject(String projectId);
  Future<void> setActiveProject(String? projectId);
  
  // ── Artifacts ──
  Future<void> saveArtifact(AiArtifact artifact);
  Future<void> openArtifact(String artifactId);
  Future<void> closeArtifactPanel();
  Future<void> deleteArtifact(String artifactId);
  Future<void> downloadArtifact(String artifactId);
  
  // ── Connectors ──
  Future<void> connectIntegration(ConnectorType type, Map<String, dynamic> config);
  Future<void> disconnectIntegration(String connectorId);
  Future<void> testConnector(String connectorId);
  
  // ── Voice ──
  Future<void> startVoiceConversation();
  Future<void> stopVoiceConversation();
  Future<void> sendVoiceInput(Uint8List audioData);
  
  // ── Search & UI ──
  void setSearchQuery(String query);
  void setView(String view);
  void toggleSidebar();
  void addAttachment(AttachedFile file);
  void removeAttachment(int index);
}
```

---

## 4. NEW DATA MODELS

### Projects
```dart
class AiProject {
  final String id;
  final String name;
  final String? description;
  final String? iconEmoji;
  final Color? color;
  final String? customInstructions;  // per-project AI behavior tuning
  final List<String> knowledgeFileIds;  // attached docs for context
  final DateTime createdAt;
  final DateTime updatedAt;
  final int conversationCount;
}
```

### Artifacts
```dart
enum ArtifactType { code, document, spreadsheet, slides, diagram, image, video }

class AiArtifact {
  final String id;
  final String title;
  final ArtifactType type;
  final String content;  // code, markdown, JSON data, or file URL
  final String? language;  // for code blocks
  final String conversationId;
  final String? messageId;  // which message generated this
  final List<ArtifactVersion> versions;  // history
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;  // execution results, dimensions, etc.
}

class ArtifactVersion {
  final String id;
  final String content;
  final DateTime createdAt;
  final String? changeDescription;
}
```

### Connectors
```dart
enum ConnectorType {
  googleDrive, gmail, googleCalendar,
  notion, github, 
  alsamosBozor, alsamosTolov, alsamosXarita,  // internal modules
  custom
}

class AiConnector {
  final String id;
  final ConnectorType type;
  final String displayName;
  final String? description;
  final bool isConnected;
  final DateTime? lastSyncAt;
  final Map<String, dynamic> config;  // auth tokens, API keys (encrypted)
  final List<String> permissions;  // read, write, execute
}
```

### Plugins/Skills
```dart
class AiPlugin {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final bool isEnabled;
  final bool isBuiltIn;
  final String? marketplaceUrl;
  final List<String> capabilities;  // "code_execution", "web_search", etc.
}
```

### Enhanced Message
```dart
class AiMessage {
  // existing fields
  final String id;
  final String role;
  final String content;
  final String? imageUrl;
  final DateTime timestamp;
  
  // NEW fields
  final List<String>? artifactIds;      // links to generated artifacts
  final List<Citation>? citations;      // web sources
  final String? parentMessageId;        // for branching
  final List<String>? childMessageIds;  // alternate responses
  final int? selectedChildIndex;        // which branch is active
  final MessageStatus status;           // pending, streaming, complete, error, stopped
  final Map<String, dynamic>? metadata; // execution logs, tool calls, etc.
}

enum MessageStatus { pending, streaming, complete, error, stopped }

class Citation {
  final String id;
  final String title;
  final String url;
  final String? snippet;
  final int position;  // footnote number
}
```

### Intent Detection
```dart
enum IntentType {
  chat,           // conversational text
  imageGen,       // "draw...", "generate image..."
  videoGen,       // "create video...", "animate..."
  codeGen,        // "write code...", "implement..."
  codeExec,       // "run this code", "execute..."
  documentGen,    // "write a report...", "draft..."
  spreadsheetGen, // "create a spreadsheet...", "analyze data..."
  webSearch,      // "search for...", "what's the latest..."
  translate,      // "translate...", "tarjima qil..."
  summarize,      // "summarize...", "qisqacha ayt..."
}

class DetectedIntent {
  final IntentType type;
  final double confidence;  // 0.0 - 1.0
  final Map<String, dynamic>? parameters;  // extracted entities
}
```

---

## 5. API / BACKEND REQUIREMENTS

### New Endpoints Needed

#### Projects
```
POST   /api/v1/ai/projects                    # create project
GET    /api/v1/ai/projects                    # list user's projects
GET    /api/v1/ai/projects/:id                # get project details
PATCH  /api/v1/ai/projects/:id                # update project
DELETE /api/v1/ai/projects/:id                # delete project
POST   /api/v1/ai/projects/:id/knowledge      # upload knowledge file
```

#### Artifacts
```
POST   /api/v1/ai/artifacts                   # save artifact
GET    /api/v1/ai/artifacts                   # list user's artifacts
GET    /api/v1/ai/artifacts/:id               # get artifact + versions
DELETE /api/v1/ai/artifacts/:id               # delete artifact
GET    /api/v1/ai/artifacts/:id/download      # download artifact file
```

#### Connectors
```
GET    /api/v1/ai/connectors                  # list available connectors
POST   /api/v1/ai/connectors/:type/connect    # initiate OAuth / API key setup
DELETE /api/v1/ai/connectors/:id              # disconnect
POST   /api/v1/ai/connectors/:id/test         # test connection
GET    /api/v1/ai/connectors/:id/status       # sync status
```

#### Intent Detection & Unified Generation
```
POST   /api/v1/ai/detect-intent               # classify user prompt
POST   /api/v1/ai/generate                    # unified generation endpoint
  body: { prompt, intent, files[], context }
  returns: { type, content, artifactId?, citations? }
```

#### Code Execution (sandboxed)
```
POST   /api/v1/ai/execute-code                # run code in sandbox
  body: { code, language, timeout }
  returns: { stdout, stderr, exitCode, files[] }
```

#### Voice
```
POST   /api/v1/ai/voice/transcribe            # speech-to-text
POST   /api/v1/ai/voice/synthesize            # text-to-speech
WS     /api/v1/ai/voice/conversation          # full-duplex voice chat
```

#### Conversation Enhancements
```
PATCH  /api/v1/ai/conversations/:id/title     # rename conversation
POST   /api/v1/ai/conversations/:id/export    # export to PDF/MD/JSON
POST   /api/v1/ai/conversations/:id/share     # generate share link
GET    /api/v1/ai/search                      # search across all conversations
  query: { q, projectId?, dateRange? }
```

### Supabase Schema Changes

**New tables needed:**

```sql
-- Projects
CREATE TABLE IF NOT EXISTS ai_projects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  icon_emoji TEXT,
  color TEXT,
  custom_instructions TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Artifacts
CREATE TABLE IF NOT EXISTS ai_artifacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES ai_conversations(id) ON DELETE SET NULL,
  message_id UUID,
  title TEXT NOT NULL,
  type TEXT NOT NULL,  -- code, document, spreadsheet, etc.
  content TEXT NOT NULL,
  language TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ai_artifact_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  artifact_id UUID REFERENCES ai_artifacts(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  change_description TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Connectors
CREATE TABLE IF NOT EXISTS ai_connectors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,  -- google_drive, notion, alsamos_bozor, etc.
  display_name TEXT NOT NULL,
  is_connected BOOLEAN DEFAULT false,
  config JSONB,  -- encrypted credentials
  permissions TEXT[],
  last_sync_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Enhanced conversations table (add columns)
ALTER TABLE ai_conversations ADD COLUMN IF NOT EXISTS project_id UUID REFERENCES ai_projects(id) ON DELETE SET NULL;
ALTER TABLE ai_conversations ADD COLUMN IF NOT EXISTS title TEXT;
ALTER TABLE ai_conversations ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;

-- Message enhancements (JSONB for flexibility)
-- messages are already stored as JSONB array, extend schema in app layer
```

**Note:** If `ai_conversations` table doesn't exist yet (currently storing in JSONB in another table), create it properly:

```sql
CREATE TABLE IF NOT EXISTS ai_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  project_id UUID REFERENCES ai_projects(id) ON DELETE SET NULL,
  title TEXT,
  context TEXT,  -- 'chat' | 'imagine'
  messages JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_pinned BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_conversations_user ON ai_conversations(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_conversations_project ON ai_conversations(project_id, updated_at DESC);
```

---

## 6. IMPLEMENTATION PHASES

### Phase 1: Foundation (Tasks #1-2) ✅ THIS DOCUMENT
- ✅ Architecture documentation
- Define all new data models
- Document API contracts

### Phase 2: Core Input Redesign (Task #3)
- Remove Chat/Imagine toggle from UI
- Build unified `AIComposerBar` widget
- Implement auto-growing text field
- Add attachment picker UI (file chips above input)
- Add model selector near input
- Add send/stop button morphing
- Stub intent detection (client-side heuristics for now)

### Phase 3: Sidebar Rebuild (Task #4)
- Build `AISidebar` with collapsible sections
- Implement search bar with fuzzy matching
- Add Projects section (empty state initially)
- Add Artifacts section (empty state initially)
- Add Connectors section (empty state initially)
- Add Plugins section (empty state initially)
- Migrate Recents section with date grouping
- Add pin/rename/delete/export context menu

### Phase 4: Message Rendering (Task #5)
- Integrate `flutter_markdown` package
- Add syntax highlighting with `flutter_highlight`
- Implement streaming token-by-token display
- Add inline media viewer for images/videos
- Build message action toolbar (copy, regenerate, branch, TTS, share)
- Add citation footnotes rendering
- Implement message branching UI (‹ 1/3 › navigation)

### Phase 5: Artifacts Panel (Task #6)
- Create `AIArtifactPanel` side panel widget
- Build code viewer with syntax highlighting + copy button
- Build document viewer (markdown/rich text)
- Build image viewer with zoom/download
- Add version dropdown (if multiple versions exist)
- Integrate save/download/share actions

### Phase 6: App Launch Fix (Task #7)
- Modify `AiNotifier._load()` to NOT set `currentConversationId` on load
- Ensure `messages` starts empty
- Show `AIEmptyState` by default on fresh launch
- Persist conversation list in background (sidebar access only)

### Phase 7: Projects System (Task #8)
- Create data models for `AiProject`
- Build Projects list UI in sidebar
- Build project creation dialog (name, icon, description)
- Build project detail page (custom instructions, knowledge files)
- Implement "move to project" action in conversation context menu
- Add project filter to conversation list

### Phase 8: Connectors (Task #9)
- Define `AiConnector` model
- Build connectors list UI
- Implement connect/disconnect toggle
- Add Alsamos internal module connectors (Bozor, To'lov, Xarita stubs)
- Build connector detail/config page
- Add "test connection" action

### Phase 9: Voice Mode (Task #10)
- Add microphone button to composer
- Implement tap-to-talk with waveform animation
- Integrate speech-to-text (populate input field for editing)
- Build full-screen voice conversation UI (call-style)
- Add live transcript overlay
- Add mute/interrupt controls

### Phase 10: Verification & Polish (Task #11)
- Test mobile (drawer sidebar, single column)
- Test tablet (persistent sidebar, optional artifact panel)
- Test desktop (persistent sidebar + artifact panel 3-column layout)
- Verify safe areas and keyboard avoidance
- Run `flutter analyze` and fix all issues
- Run `flutter build windows --debug`
- Run `flutter build apk --debug`
- Fix any build errors

---

## 7. TECHNICAL CONSIDERATIONS

### Intent Detection Strategy
**Phase 1 (MVP):** Client-side heuristic matching
```dart
DetectedIntent _detectIntent(String prompt) {
  final lower = prompt.toLowerCase();
  
  // Image generation keywords
  if (RegExp(r'\b(draw|rasm|generate.*image|create.*image|surat|chiz)\b').hasMatch(lower)) {
    return DetectedIntent(type: IntentType.imageGen, confidence: 0.8);
  }
  
  // Video generation
  if (RegExp(r'\b(video.*yarat|create.*video|animate)\b').hasMatch(lower)) {
    return DetectedIntent(type: IntentType.videoGen, confidence: 0.7);
  }
  
  // Code execution (user saying "run this")
  if (RegExp(r'\b(run|execute|ishla)\b').hasMatch(lower) && prompt.contains('```')) {
    return DetectedIntent(type: IntentType.codeExec, confidence: 0.9);
  }
  
  // Default to chat
  return DetectedIntent(type: IntentType.chat, confidence: 0.5);
}
```

**Phase 2 (Future):** Server-side LLM-based classification via `/api/v1/ai/detect-intent`

### Offline Handling
- Queue messages locally if network drops
- Show "pending" status with retry button
- Sync when connection restores

### Performance
- Virtualize conversation list (use `ListView.builder`)
- Virtualize message list
- Lazy-load artifacts (thumbnails only in sidebar)
- Cache images with `cached_network_image`
- Debounce search input (300ms)

### Accessibility
- Proper semantic labels for screen readers
- Keyboard navigation for desktop/web
- Scalable text (respect system font size)
- Sufficient contrast ratios (WCAG AA)

### Localization
- All new strings go through `AppStrings` (i18n system)
- Support: Uzbek (Latin), Russian, English
- RTL-ready layout (future Arabic support)

### Security
- Never store connector credentials in plain text (use Supabase Vault)
- Show confirmation dialog before any destructive action (delete project, disconnect)
- Code execution runs in sandboxed environment (backend responsibility)
- User approval required before web browsing agent submits forms / makes purchases

---

## 8. MIGRATION STRATEGY

### Backward Compatibility
- Keep existing `ai_conversations` data structure
- `context` field ('chat' | 'imagine') maps to message metadata, not mode toggle
- Existing conversations show in Recents section
- No data loss

### Gradual Rollout
- Ship Phase 2-6 first (core UX improvements, no backend changes)
- Deploy backend changes for Projects/Artifacts/Connectors in parallel
- Feature-flag advanced features (voice, code execution) until backend ready

---

## 9. RISK MITIGATION

### High-Risk Areas
1. **Intent detection accuracy** — users will complain if requests ignored
   - Mitigation: Show disambiguation UI ("Did you mean to generate an image?") with quick-fix buttons
   
2. **App launch behavior** — must not break existing navigation
   - Mitigation: Test thoroughly on cold start, hot reload, deep link entry
   
3. **Message branching complexity** — can confuse users
   - Mitigation: Keep UI minimal (only show branch navigation after regenerate), hide complexity until needed
   
4. **Performance on low-end Android** — sidebar + messages + artifact panel = heavy
   - Mitigation: Profile on mid-range device (Redmi Note 10), lazy load everything, collapse artifact panel on tablet if FPS drops

### Testing Checklist
- [ ] Cold start → lands on new chat (no conversation loaded)
- [ ] Sidebar search returns correct results
- [ ] Image generation works without manual mode toggle
- [ ] Streaming messages render smoothly at 60fps
- [ ] Artifact panel doesn't block chat input on desktop
- [ ] Voice button doesn't crash when mic permission denied
- [ ] Message regenerate doesn't duplicate messages
- [ ] Conversation export (PDF/Markdown) includes all messages + artifacts
- [ ] Dark mode renders correctly
- [ ] Uzbek/Russian translations complete

---

## 10. SUCCESS METRICS

### User Experience
- **Zero "nothing happens" bug reports** (current Imagine mode issue)
- **<2 seconds** to start new chat from any state
- **90%+ intent detection accuracy** (measured via user corrections)
- **<100ms** message search response time

### Technical
- **60fps** scroll performance on mid-range devices
- **<50ms** composer input latency
- **Zero** regressions in existing features (Home, Messages, Bozor)
- **100%** `flutter analyze` clean

### Adoption
- **>50%** of AI users create at least 1 project (shows organization value)
- **>30%** of AI users open artifacts panel (shows utility)
- **>20%** of AI users connect at least 1 connector (shows ecosystem stickiness)

---

## 11. NEXT STEPS

1. ✅ Review this architecture with team
2. Get backend API spec confirmed (or stub endpoints)
3. Create Supabase migration for new tables
4. Begin Phase 2 implementation (unified input)
5. Iterate on each phase, testing on real device after each

---

**Document Owner:** Kiro AI Agent  
**Last Updated:** 2026-08-04  
**Review Status:** Pending team approval
