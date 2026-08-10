import '../../data/ai_models_v2.dart';
import '../providers/ai_provider.dart' show ForwardedPost;

/// Enhanced state for AI page V2 redesign.
/// Replaces the old AiState with expanded capabilities for projects, artifacts,
/// connectors, plugins, and richer UI state management.
class AiStateV2 {
  // ── Conversations & Messages ──────────────────────────────────────────────
  final List<AiConversationV2> conversations;
  final List<AiMessageV2> messages;
  final String? currentConversationId;
  final String? currentProjectId;
  final bool conversationsLoading;

  // ── Projects ──────────────────────────────────────────────────────────────
  final List<AiProject> projects;
  final bool projectsLoading;

  // ── Artifacts ─────────────────────────────────────────────────────────────
  final List<AiArtifact> artifacts;
  final AiArtifact? activeArtifact;
  final bool artifactsLoading;

  // ── Connectors ────────────────────────────────────────────────────────────
  final List<AiConnector> connectors;
  final bool connectorsLoading;

  // ── Plugins / Skills ──────────────────────────────────────────────────────
  final List<AiPlugin> plugins;
  final bool pluginsLoading;

  // ── UI State ──────────────────────────────────────────────────────────────
  final String currentView; // 'chat' | 'projects' | 'artifacts' | 'connectors'
  final bool showArtifactPanel;
  final bool sidebarCollapsed;

  // ── Composer State ────────────────────────────────────────────────────────
  final List<AttachedFile> attachments;
  final bool isVoiceMode;
  final String? voiceTranscript;

  // ── Generation State ──────────────────────────────────────────────────────
  final bool isGenerating;
  final GenerationType? generationType;
  final double? generationProgress; // 0.0 - 1.0

  // ── Search & Filters ──────────────────────────────────────────────────────
  final String searchQuery;
  final ConversationFilter filter;

  // ── Forwarded Content (keep for post integration) ─────────────────────────
  final ForwardedPost? forwardedPost;

  // ── Error Handling ────────────────────────────────────────────────────────
  final String? lastError;

  const AiStateV2({
    this.conversations = const [],
    this.messages = const [],
    this.currentConversationId,
    this.currentProjectId,
    this.conversationsLoading = true,
    this.projects = const [],
    this.projectsLoading = true,
    this.artifacts = const [],
    this.activeArtifact,
    this.artifactsLoading = true,
    this.connectors = const [],
    this.connectorsLoading = true,
    this.plugins = const [],
    this.pluginsLoading = true,
    this.currentView = 'chat',
    this.showArtifactPanel = false,
    this.sidebarCollapsed = false,
    this.attachments = const [],
    this.isVoiceMode = false,
    this.voiceTranscript,
    this.isGenerating = false,
    this.generationType,
    this.generationProgress,
    this.searchQuery = '',
    this.filter = const ConversationFilter(),
    this.forwardedPost,
    this.lastError,
  });

  AiStateV2 copyWith({
    List<AiConversationV2>? conversations,
    List<AiMessageV2>? messages,
    String? currentConversationId,
    bool clearCurrentConversation = false,
    String? currentProjectId,
    bool clearCurrentProject = false,
    bool? conversationsLoading,
    List<AiProject>? projects,
    bool? projectsLoading,
    List<AiArtifact>? artifacts,
    AiArtifact? activeArtifact,
    bool clearActiveArtifact = false,
    bool? artifactsLoading,
    List<AiConnector>? connectors,
    bool? connectorsLoading,
    List<AiPlugin>? plugins,
    bool? pluginsLoading,
    String? currentView,
    bool? showArtifactPanel,
    bool? sidebarCollapsed,
    List<AttachedFile>? attachments,
    bool? isVoiceMode,
    String? voiceTranscript,
    bool clearVoiceTranscript = false,
    bool? isGenerating,
    GenerationType? generationType,
    bool clearGenerationType = false,
    double? generationProgress,
    bool clearGenerationProgress = false,
    String? searchQuery,
    ConversationFilter? filter,
    ForwardedPost? forwardedPost,
    bool clearForwardedPost = false,
    String? lastError,
    bool clearLastError = false,
  }) =>
      AiStateV2(
        conversations: conversations ?? this.conversations,
        messages: messages ?? this.messages,
        currentConversationId: clearCurrentConversation
            ? null
            : (currentConversationId ?? this.currentConversationId),
        currentProjectId: clearCurrentProject
            ? null
            : (currentProjectId ?? this.currentProjectId),
        conversationsLoading: conversationsLoading ?? this.conversationsLoading,
        projects: projects ?? this.projects,
        projectsLoading: projectsLoading ?? this.projectsLoading,
        artifacts: artifacts ?? this.artifacts,
        activeArtifact: clearActiveArtifact
            ? null
            : (activeArtifact ?? this.activeArtifact),
        artifactsLoading: artifactsLoading ?? this.artifactsLoading,
        connectors: connectors ?? this.connectors,
        connectorsLoading: connectorsLoading ?? this.connectorsLoading,
        plugins: plugins ?? this.plugins,
        pluginsLoading: pluginsLoading ?? this.pluginsLoading,
        currentView: currentView ?? this.currentView,
        showArtifactPanel: showArtifactPanel ?? this.showArtifactPanel,
        sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
        attachments: attachments ?? this.attachments,
        isVoiceMode: isVoiceMode ?? this.isVoiceMode,
        voiceTranscript: clearVoiceTranscript
            ? null
            : (voiceTranscript ?? this.voiceTranscript),
        isGenerating: isGenerating ?? this.isGenerating,
        generationType: clearGenerationType
            ? null
            : (generationType ?? this.generationType),
        generationProgress: clearGenerationProgress
            ? null
            : (generationProgress ?? this.generationProgress),
        searchQuery: searchQuery ?? this.searchQuery,
        filter: filter ?? this.filter,
        forwardedPost: clearForwardedPost
            ? null
            : (forwardedPost ?? this.forwardedPost),
        lastError: clearLastError ? null : (lastError ?? this.lastError),
      );

  /// Helper: Get pinned conversations
  List<AiConversationV2> get pinnedConversations =>
      conversations.where((c) => c.isPinned).toList();

  /// Helper: Get unpinned conversations
  List<AiConversationV2> get unpinnedConversations =>
      conversations.where((c) => !c.isPinned).toList();

  /// Helper: Get conversations filtered by current project
  List<AiConversationV2> get filteredConversations {
    var result = conversations;

    // Filter by project
    if (filter.projectId != null) {
      result = result.where((c) => c.projectId == filter.projectId).toList();
    }

    // Filter by type
    if (filter.type != null) {
      result = result.where((c) => c.type == filter.type).toList();
    }

    // Filter by pinned
    if (filter.pinnedOnly == true) {
      result = result.where((c) => c.isPinned).toList();
    }

    // Filter by date range
    if (filter.startDate != null) {
      result = result
          .where((c) => c.updatedAt.isAfter(filter.startDate!))
          .toList();
    }
    if (filter.endDate != null) {
      result =
          result.where((c) => c.updatedAt.isBefore(filter.endDate!)).toList();
    }

    // Filter by search query
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result.where((c) {
        // Search in title
        if (c.title.toLowerCase().contains(query)) return true;
        // Search in message content
        return c.messages.any((m) => m.content.toLowerCase().contains(query));
      }).toList();
    }

    return result;
  }

  /// Helper: Get artifacts for current conversation
  List<AiArtifact> get currentConversationArtifacts {
    if (currentConversationId == null) return const [];
    return artifacts
        .where((a) => a.conversationId == currentConversationId)
        .toList();
  }

  /// Helper: Get project by ID
  AiProject? getProject(String projectId) {
    try {
      return projects.firstWhere((p) => p.id == projectId);
    } catch (_) {
      return null;
    }
  }

  /// Helper: Get conversation by ID
  AiConversationV2? getConversation(String conversationId) {
    try {
      return conversations.firstWhere((c) => c.id == conversationId);
    } catch (_) {
      return null;
    }
  }

  /// Helper: Check if any generation is in progress
  bool get isBusy =>
      isGenerating || conversationsLoading || projectsLoading || artifactsLoading;

  /// Helper: Check if empty new-chat state
  bool get isNewChat =>
      currentConversationId == null && messages.isEmpty && forwardedPost == null;
}
