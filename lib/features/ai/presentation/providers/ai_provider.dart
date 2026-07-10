import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/ai_models.dart';
import '../../data/ai_repository.dart';

final aiRepositoryProvider = Provider<AiRepository>((ref) => AiRepository());

class ForwardedPost {
  final String id;
  final String? content;
  final String? authorName;
  final String? mediaUrl;
  const ForwardedPost({required this.id, this.content, this.authorName, this.mediaUrl});
}

class AiState {
  final List<AiConversation> conversations;
  final List<AiMessage> messages;
  final String? currentConversationId;
  final bool isLoading; // streaming a reply
  final bool isGeneratingImage;
  final bool conversationsLoading;
  final String mode; // 'chat' | 'imagine'
  final ForwardedPost? forwardedPost;

  const AiState({
    this.conversations = const [],
    this.messages = const [],
    this.currentConversationId,
    this.isLoading = false,
    this.isGeneratingImage = false,
    this.conversationsLoading = true,
    this.mode = 'chat',
    this.forwardedPost,
  });

  AiState copyWith({
    List<AiConversation>? conversations,
    List<AiMessage>? messages,
    String? currentConversationId,
    bool clearCurrent = false,
    bool? isLoading,
    bool? isGeneratingImage,
    bool? conversationsLoading,
    String? mode,
    ForwardedPost? forwardedPost,
    bool clearForwarded = false,
  }) =>
      AiState(
        conversations: conversations ?? this.conversations,
        messages: messages ?? this.messages,
        currentConversationId:
            clearCurrent ? null : (currentConversationId ?? this.currentConversationId),
        isLoading: isLoading ?? this.isLoading,
        isGeneratingImage: isGeneratingImage ?? this.isGeneratingImage,
        conversationsLoading: conversationsLoading ?? this.conversationsLoading,
        mode: mode ?? this.mode,
        forwardedPost: clearForwarded ? null : (forwardedPost ?? this.forwardedPost),
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
      if (convs.isNotEmpty) {
        state = state.copyWith(
          currentConversationId: convs.first.id,
          messages: convs.first.messages,
          mode: convs.first.type,
        );
      }
    } catch (_) {
      state = state.copyWith(conversationsLoading: false);
    }
  }

  void setMode(String mode) {
    if (mode == 'chat' || mode == 'imagine') {
      state = state.copyWith(mode: mode);
    }
  }

  void startNew() {
    state = state.copyWith(messages: const [], clearCurrent: true, clearForwarded: true);
  }

  void openConversation(AiConversation conv) {
    state = state.copyWith(
      messages: conv.messages,
      currentConversationId: conv.id,
      mode: conv.type,
      clearForwarded: true,
    );
  }

  void clearForwardedPost() {
    state = state.copyWith(clearForwarded: true);
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
      mode: 'chat',
    );
  }

  Future<void> deleteConversation(String id) async {
    await _repo.deleteConversation(id);
    final remaining = state.conversations.where((c) => c.id != id).toList();
    state = state.copyWith(conversations: remaining);
    if (state.currentConversationId == id) startNew();
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

    // Build forwarded-post context (matches web AIPage behaviour)
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
    state = state.copyWith(
      messages: working,
      isGeneratingImage: true,
      mode: 'imagine',
    );
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
    // Find the last user message and resend it (matches web ReactCcw action).
    final msgs = state.messages;
    AiMessage? lastUser;
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].isUser) {
        lastUser = msgs[i];
        break;
      }
    }
    if (lastUser == null) return;
    // Drop the trailing assistant reply if present.
    final trimmed = msgs.last.role == 'assistant'
        ? msgs.sublist(0, msgs.length - 1)
        : List<AiMessage>.from(msgs);
    // Also drop the last user message so sendMessage re-appends it cleanly.
    if (trimmed.isNotEmpty && trimmed.last.id == lastUser.id) {
      trimmed.removeLast();
    }
    state = state.copyWith(messages: trimmed);
    if (state.mode == 'imagine') {
      await generateImage(lastUser.content);
    } else {
      await sendMessage(lastUser.content);
    }
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
    } catch (_) {/* persistence best-effort */}
  }
}

final aiProvider = StateNotifierProvider<AiNotifier, AiState>((ref) {
  final userId = ref.watch(authProvider).user?.id;
  return AiNotifier(ref.watch(aiRepositoryProvider), userId);
});
