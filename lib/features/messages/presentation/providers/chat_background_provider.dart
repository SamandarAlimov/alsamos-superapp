import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ChatWallpaperType { preset, color, gradient, image }

class ChatWallpaperConfig {
  final ChatWallpaperType type;
  final String value;
  final double dim;
  final double blur;
  final DateTime updatedAt;

  const ChatWallpaperConfig({
    required this.type,
    required this.value,
    this.dim = 0.16,
    this.blur = 0,
    required this.updatedAt,
  });

  static ChatWallpaperConfig get fallback => ChatWallpaperConfig(
        type: ChatWallpaperType.preset,
        value: 'wallpaper1.svg',
        dim: 0.14,
        blur: 0,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  ChatWallpaperConfig copyWith({
    ChatWallpaperType? type,
    String? value,
    double? dim,
    double? blur,
    DateTime? updatedAt,
  }) {
    return ChatWallpaperConfig(
      type: type ?? this.type,
      value: value ?? this.value,
      dim: dim ?? this.dim,
      blur: blur ?? this.blur,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'value': value,
        'dim': dim,
        'blur': blur,
        'updated_at': updatedAt.toIso8601String(),
      };

  static ChatWallpaperConfig? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final typeName = json['type'] as String?;
    final value = json['value'] as String?;
    if (typeName == null || value == null || value.isEmpty) return null;
    final type = ChatWallpaperType.values
        .where((item) => item.name == typeName)
        .firstOrNull;
    if (type == null) return null;
    return ChatWallpaperConfig(
      type: type,
      value: value,
      dim: (json['dim'] as num?)?.toDouble() ?? 0.16,
      blur: (json['blur'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static ChatWallpaperConfig? fromUserSettings(Map<String, dynamic>? row) {
    if (row == null) return null;
    final type = row['chat_wallpaper_type'] as String?;
    final value = row['chat_wallpaper_value'] as String?;
    if (type != null && value != null && value.isNotEmpty) {
      return fromJson({
        'type': type,
        'value': value,
        'dim': row['chat_wallpaper_dim'],
        'blur': row['chat_wallpaper_blur'],
        'updated_at': row['chat_wallpaper_updated_at'],
      });
    }
    final legacy = row['chat_background'] as String?;
    if (legacy != null && legacy.isNotEmpty) {
      return ChatWallpaperConfig(
        type: ChatWallpaperType.image,
        value: legacy,
        dim: 0.22,
        blur: 0,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }
    return null;
  }

  static ChatWallpaperConfig? fromParticipant(Map<String, dynamic>? row) {
    if (row == null) return null;
    final type = row['wallpaper_type'] as String?;
    final value = row['wallpaper_value'] as String?;
    if (type == null || value == null || value.isEmpty) return null;
    return fromJson({
      'type': type,
      'value': value,
      'dim': row['wallpaper_dim'],
      'blur': row['wallpaper_blur'],
      'updated_at': row['wallpaper_updated_at'],
    });
  }
}

Map<String, dynamic>? _decodeMap(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    final decoded = jsonDecode(value);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

class ChatWallpaperState {
  final ChatWallpaperConfig global;
  final Map<String, ChatWallpaperConfig?> perChat;

  const ChatWallpaperState({
    required this.global,
    required this.perChat,
  });

  ChatWallpaperConfig effectiveFor(String? conversationId) {
    if (conversationId != null && perChat.containsKey(conversationId)) {
      return perChat[conversationId] ?? global;
    }
    return global;
  }

  ChatWallpaperState copyWith({
    ChatWallpaperConfig? global,
    Map<String, ChatWallpaperConfig?>? perChat,
  }) {
    return ChatWallpaperState(
      global: global ?? this.global,
      perChat: perChat ?? this.perChat,
    );
  }
}

class ChatWallpaperNotifier extends StateNotifier<ChatWallpaperState> {
  ChatWallpaperNotifier()
      : super(ChatWallpaperState(
          global: ChatWallpaperConfig.fallback,
          perChat: const {},
        )) {
    loadGlobal();
  }

  static const _globalKey = 'alsamos_chat_wallpaper_global';
  static String _chatKey(String conversationId) =>
      'alsamos_chat_wallpaper_chat_$conversationId';

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> loadGlobal() async {
    final prefs = await SharedPreferences.getInstance();
    final local =
        ChatWallpaperConfig.fromJson(_decodeMap(prefs.getString(_globalKey)));
    if (local != null) state = state.copyWith(global: local);

    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      Map<String, dynamic>? row;
      try {
        row = await _client
            .from('user_settings')
            .select(
                'chat_wallpaper_type, chat_wallpaper_value, chat_wallpaper_dim, chat_wallpaper_blur, chat_wallpaper_updated_at, chat_background')
            .eq('user_id', uid)
            .maybeSingle();
      } catch (_) {
        row = await _client
            .from('user_settings')
            .select('chat_background')
            .eq('user_id', uid)
            .maybeSingle();
      }
      final remote = ChatWallpaperConfig.fromUserSettings(row);
      if (remote != null && remote.updatedAt.isAfter(state.global.updatedAt)) {
        state = state.copyWith(global: remote);
        await prefs.setString(_globalKey, jsonEncode(remote.toJson()));
      }
    } catch (_) {
      // Local wallpaper remains usable offline.
    }
  }

  Future<void> loadForConversation(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_chatKey(conversationId));
    if (raw == '__inherit__') {
      state = state.copyWith(
        perChat: {...state.perChat, conversationId: null},
      );
    } else {
      final local = ChatWallpaperConfig.fromJson(_decodeMap(raw));
      if (local != null) {
        state = state.copyWith(
          perChat: {...state.perChat, conversationId: local},
        );
      }
    }

    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      final row = await _client
          .from('conversation_participants')
          .select(
              'wallpaper_type, wallpaper_value, wallpaper_dim, wallpaper_blur, wallpaper_updated_at')
          .eq('conversation_id', conversationId)
          .eq('user_id', uid)
          .maybeSingle();
      final remote = ChatWallpaperConfig.fromParticipant(row);
      if (remote == null) {
        state = state.copyWith(
          perChat: {...state.perChat, conversationId: null},
        );
        await prefs.setString(_chatKey(conversationId), '__inherit__');
        return;
      }
      final current = state.perChat[conversationId];
      if (current == null || remote.updatedAt.isAfter(current.updatedAt)) {
        state = state.copyWith(
          perChat: {...state.perChat, conversationId: remote},
        );
        await prefs.setString(
            _chatKey(conversationId), jsonEncode(remote.toJson()));
      }
    } catch (_) {
      // Missing migration/offline: keep local override.
    }
  }

  Future<void> setGlobal(ChatWallpaperConfig config) async {
    final next = config.copyWith(updatedAt: DateTime.now().toUtc());
    state = state.copyWith(global: next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_globalKey, jsonEncode(next.toJson()));
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      await _client.from('user_settings').upsert({
        'user_id': uid,
        'chat_wallpaper_type': next.type.name,
        'chat_wallpaper_value': next.value,
        'chat_wallpaper_dim': next.dim,
        'chat_wallpaper_blur': next.blur,
        'chat_wallpaper_updated_at': next.updatedAt.toIso8601String(),
        'chat_background':
            next.type == ChatWallpaperType.image ? next.value : null,
      }, onConflict: 'user_id');
    } catch (_) {}
  }

  Future<void> setForConversation(
    String conversationId,
    ChatWallpaperConfig config,
  ) async {
    final next = config.copyWith(updatedAt: DateTime.now().toUtc());
    state = state.copyWith(
      perChat: {...state.perChat, conversationId: next},
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatKey(conversationId), jsonEncode(next.toJson()));
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      await _client.from('conversation_participants').update({
        'wallpaper_type': next.type.name,
        'wallpaper_value': next.value,
        'wallpaper_dim': next.dim,
        'wallpaper_blur': next.blur,
        'wallpaper_updated_at': next.updatedAt.toIso8601String(),
      }).match({'conversation_id': conversationId, 'user_id': uid});
    } catch (_) {}
  }

  Future<void> resetGlobal() async {
    await setGlobal(ChatWallpaperConfig.fallback);
  }

  Future<void> resetConversation(String conversationId) async {
    state = state.copyWith(
      perChat: {...state.perChat, conversationId: null},
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatKey(conversationId), '__inherit__');
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      await _client.from('conversation_participants').update({
        'wallpaper_type': null,
        'wallpaper_value': null,
        'wallpaper_dim': null,
        'wallpaper_blur': null,
        'wallpaper_updated_at': DateTime.now().toUtc().toIso8601String(),
      }).match({'conversation_id': conversationId, 'user_id': uid});
    } catch (_) {}
  }

  Future<ChatWallpaperConfig?> uploadCustomImage(XFile file) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final source = await file.readAsBytes();
    final compressed = _compressWallpaper(source);
    final path =
        '$uid/wallpapers/wallpaper-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('chat-wallpapers').uploadBinary(
          path,
          compressed,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return ChatWallpaperConfig(
      type: ChatWallpaperType.image,
      value: 'storage://chat-wallpapers/$path',
      dim: 0.18,
      blur: 0,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Uint8List _compressWallpaper(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final resized = decoded.width > 1800
        ? img.copyResize(decoded,
            width: 1800, interpolation: img.Interpolation.average)
        : decoded;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 84));
  }
}

final chatWallpaperProvider =
    StateNotifierProvider<ChatWallpaperNotifier, ChatWallpaperState>(
  (ref) => ChatWallpaperNotifier(),
);

final resolvedChatWallpaperProvider =
    Provider.family<ChatWallpaperConfig, String?>((ref, conversationId) {
  return ref.watch(chatWallpaperProvider).effectiveFor(conversationId);
});

final chatBackgroundProvider = Provider<String?>((ref) {
  final config = ref.watch(chatWallpaperProvider).global;
  return config.type == ChatWallpaperType.image ? config.value : null;
});
