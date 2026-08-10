import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/ai_models.dart';
import '../../data/ai_models_v2.dart';
import '../../data/ai_repository.dart';
import '../../data/intent_detector.dart';

final aiRepositoryProvider = Provider<AiRepository>((ref) => AiRepository());

class ForwardedPost {
  final String id;
  final String? content;
  final String? authorName;
  final String? mediaUrl;
  const ForwardedPost({required this.id, this.content, this.authorName, this.mediaUrl});
}

enum AiView { chat, projects, artifacts, connectors, plugins }

class AiState {
  final List<AiConversation> conversations;
  final List<AiMessage> messages;
  final String? currentConversationId;
  final bool isLoading;
  final bool isGeneratingImage;
  final bool conversationsLoading;
  final ForwardedPost? forwardedPost;

  // V2 fields
  final AiView currentView;
  final bool showArtifactPanel;
  final bool sidebarCollapsed;
  final List<AttachedFile> attachments;
  final DetectedIntent? lastIntent;
  final String? selectedModel;

  const AiState({
    this.conversations = const [],
    this.messages = const [],
    this.currentConversationId,
    this.isLoading = false,
    this.isGeneratingImage = false,
    this.conversationsLoading = true,
    this.forwardedPost,
    this.currentView = AiView.chat,
    this.showArtifactPanel = false,
    this.sidebarCollapsed = false,
    this.attachments = const [],
    this.lastIntent,
    this.selectedModel,
  });

  bool get isBusy => isLoading || isGeneratingImage;
  bool get isNewChat => currentConversationId == null && messages.isEmpty;

  AiState copyWith({
    List<AiConversation>? conversations,
    List<AiMessage>? messages,
    String? currentConversationId,
    bool clearCurrent = false,
    bool? isLoading,
    bool? isGeneratingImage,
    bool? conversationsLoading,
    ForwardedPost? forwardedPost,
    bool clearForwarded = false,
    AiView? currentView,
    bool? showArtifactPanel,
    bool? sidebarCollapsed,
    List<AttachedFile>? attachments,
    DetectedIntent? lastIntent,
    bool clearIntent = false,
    String? selectedModel,
    bool clearModel = false,
  }) =>
      AiState(
        conversations: conversations ?? this.conversations,
        messages: messages ?? this.messages,
        currentConversationId:
            clearCurrent ? null : (currentConversationId ?? this.currentConversationId),
        isLoading: isLoading ?? this.isLoading,
        isGeneratingImage: isGeneratingImage ?? this.isGeneratingImage,
        conversationsLoading: conversationsLoading ?? this.conversationsLoading,
        forwardedPost: clearForwarded ? null : (forwardedPost ?? this.forwardedPost),
        currentView: currentView ?? this.currentView,
        showArtifactPanel: showArtifactPanel ?? this.showArtifactPanel,
        sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
        attachments: attachments ?? this.attachments,
        lastIntent: clearIntent ? null : (lastIntent ?? this.lastIntent),
        selectedModel: clearModel ? null : (selectedModel ?? this.selectedModel),
      );
}

class AiNotifier extends StateNotifier<AiState> {
  AiNotifier(this._repo, this._userId) : super(const AiState()) {
    _load();
  }

  final AiRepository _repo;
  final String? _userId;

  Future<void> _load() async {
    if (_userId == null) {
      state = state.copyWith(conversationsLoading: false);
      return;
    }
    try {
      final convs = await _repo.loadConversations(_userId);
      state = state.copyWith(conversations: convs, conversationsLoading: false);
    } catch (_) {
      state = state.copyWith(conversationsLoading: false);
    }
  }

  void setView(AiView view) {
    state = state.copyWith(currentView: view);
  }

  void toggleSidebarCollapsed() {
    state = state.copyWith(sidebarCollapsed: !state.sidebarCollapsed);
  }

  void toggleArtifactPanel() {
    state = state.copyWith(showArtifactPanel: !state.showArtifactPanel);
  }

  void setModel(String model) {
    state = state.copyWith(selectedModel: model);
  }

  void startNew() {
    state = state.copyWith(
      messages: const [],
      clearCurrent: true,
      clearForwarded: true,
      clearIntent: true,
      attachments: const [],
    );
  }

  void openConversation(AiConversation conv) {
    state = state.copyWith(
      messages: conv.messages,
      currentConversationId: conv.id,
      clearForwarded: true,
      clearIntent: true,
      currentView: AiView.chat,
    );
  }

  void clearForwardedPost() {
    state = state.copyWith(clearForwarded: true);
  }

  void addAttachment(AttachedFile file) {
    state = state.copyWith(attachments: [...state.attachments, file]);
  }

  void removeAttachment(int index) {
    final list = List<AttachedFile>.from(state.attachments);
    if (index < list.length) list.removeAt(index);
    state = state.copyWith(attachments: list);
  }

  void clearAttachments() {
    state = state.copyWith(attachments: const []);
  }

  Future<void> attachForwardedPost(String postId, {String? fallbackContent}) async {
    startNew();
    final post = await _repo.fetchForwardedPost(postId);
    state = state.copyWith(
      forwardedPost: post != null
          ? ForwardedPost(
              id: post.id,
              content: post.content,
              authorName: post.authorName,
              mediaUrl: post.mediaUrl,
            )
          : ForwardedPost(id: postId, content: fallbackContent),
    );
  }

  Future<void> deleteConversation(String id) async {
    await _repo.deleteConversation(id);
    final remaining = state.conversations.where((c) => c.id != id).toList();
    state = state.copyWith(conversations: remaining);
    if (state.currentConversationId == id) startNew();
  }

  /// Unified send - automatically routes to image generation if intent detected
  Future<void> send(String text) async {
    if (_userId == null || text.trim().isEmpty || state.isBusy) return;

    final intent = IntentDetector.detect(text);
    state = state.copyWith(lastIntent: intent);

    if (intent.type == IntentType.imageGen && intent.isHighConfidence) {
      await generateImage(text);
    } else {
      await sendMessage(text);
    }
  }

  Future<void> sendMessage(String text) async {
    if (_userId == null || text.trim().isEmpty || state.isLoading) return;
    final userMsg = AiMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: 'user',
      content: text.trim(),
    );
    final working = [...state.messages, userMsg];
    state = state.copyWith(messages: working, isLoading: true);

    String? contextInfo;
    final fp = state.forwardedPost;
    if (fp != null) {
      final author = fp.authorName ?? 'Noma\'lum';
      final body = fp.content ?? '(matn yo\'q)';
      final media = fp.mediaUrl != null ? '\nMedia: ${fp.mediaUrl}' : '';
      contextInfo =
          '\n\n[Foydalanuvchi quyidagi postni AI ga yubordi]\nPost muallifi: $author\nPost matni: $body$media';
    }

    var assistant = AiMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}-a',
      role: 'assistant',
      content: '',
    );
    var appended = false;
    var acc = '';
    try {
      await for (final delta
          in _repo.streamChat(working, _userId, contextInfo: contextInfo)) {
        acc += delta;
        assistant = assistant.copyWith(content: acc);
        if (!appended) {
          state = state.copyWith(messages: [...working, assistant]);
          appended = true;
        } else {
          final list = [...state.messages];
          list[list.length - 1] = assistant;
          state = state.copyWith(messages: list);
        }
      }
      if (!appended) {
        assistant = assistant.copyWith(content: 'Javob olinmadi.');
        state = state.copyWith(messages: [...working, assistant]);
      }
      await _persist(state.messages, 'chat');
      state = state.copyWith(clearForwarded: true);
    } catch (e) {
      final err = AiMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}-e',
        role: 'assistant',
        content: 'Xatolik: $e',
      );
      state = state.copyWith(messages: [...working, err]);
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> generateImage(String prompt) async {
    if (_userId == null || prompt.trim().isEmpty || state.isGeneratingImage) return;
    final userMsg = AiMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: 'user',
      content: prompt.trim(),
    );
    final working = [...state.messages, userMsg];
    state = state.copyWith(messages: working, isGeneratingImage: true);
    try {
      final res = await _repo.generateImage(prompt.trim());
      final assistant = AiMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}-a',
        role: 'assistant',
        content: res.revisedPrompt ?? 'Rasm yaratildi!',
        imageUrl: res.imageUrl,
      );
      final updated = [...working, assistant];
      state = state.copyWith(messages: updated);
      await _persist(updated, 'imagine');
    } catch (e) {
      final err = AiMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}-e',
        role: 'assistant',
        content: 'Xatolik: $e',
      );
      state = state.copyWith(messages: [...working, err]);
    } finally {
      state = state.copyWith(isGeneratingImage: false);
    }
  }

  Future<void> regenerate() async {
    final msgs = state.messages;
    AiMessage? lastUser;
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].isUser) {
        lastUser = msgs[i];
        break;
      }
    }
    if (lastUser == null) return;
    final trimmed = msgs.last.role == 'assistant'
        ? msgs.sublist(0, msgs.length - 1)
        : List<AiMessage>.from(msgs);
    if (trimmed.isNotEmpty && trimmed.last.id == lastUser.id) {
      trimmed.removeLast();
    }
    state = state.copyWith(messages: trimmed);
    await send(lastUser.content);
  }

  Future<void> _persist(List<AiMessage> msgs, String context) async {
    if (_userId == null) return;
    try {
      if (state.currentConversationId != null) {
        await _repo.updateConversation(state.currentConversationId!, msgs);
        final updated = state.conversations
            .map((c) => c.id == state.currentConversationId
                ? AiConversation(
                    id: c.id, messages: msgs, updatedAt: DateTime.now(), type: c.type)
                : c)
            .toList();
        state = state.copyWith(conversations: updated);
      } else {
        final id = await _repo.createConversation(_userId, msgs, context);
        if (id != null) {
          final conv = AiConversation(
              id: id, messages: msgs, updatedAt: DateTime.now(), type: context);
          state = state.copyWith(
            currentConversationId: id,
            conversations: [conv, ...state.conversations],
          );
        }
      }
    } catch (_) {}
  }
}

final aiProvider = StateNotifierProvider<AiNotifier, AiState>((ref) {
  final userId = ref.read(authProvider).user?.id;
  return AiNotifier(ref.read(aiRepositoryProvider), userId);
});
