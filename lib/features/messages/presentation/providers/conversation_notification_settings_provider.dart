import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/presentation/providers/auth_provider.dart';

class ConversationNotificationSettings {
  const ConversationNotificationSettings({
    required this.conversationId,
    required this.muteForever,
    required this.mentionsOnly,
    required this.previewEnabled,
    required this.sound,
    this.mutedUntil,
  });

  final String conversationId;
  final DateTime? mutedUntil;
  final bool muteForever;
  final bool mentionsOnly;
  final bool previewEnabled;
  final String sound;

  bool get isMuted {
    if (muteForever) return true;
    final until = mutedUntil;
    return until != null && until.isAfter(DateTime.now().toUtc());
  }

  String get subtitle {
    if (muteForever) return 'Doimiy ovozsiz';
    if (mutedUntil != null && isMuted) return 'Ovoz vaqtincha o\'chirilgan';
    if (mentionsOnly) return 'Faqat mentionlar';
    return 'Bildirishnomalar yoqilgan';
  }

  factory ConversationNotificationSettings.defaults(String conversationId) =>
      ConversationNotificationSettings(
        conversationId: conversationId,
        muteForever: false,
        mentionsOnly: false,
        previewEnabled: true,
        sound: 'default',
      );

  factory ConversationNotificationSettings.fromMap(
    String conversationId,
    Map<String, dynamic>? map,
  ) {
    if (map == null) {
      return ConversationNotificationSettings.defaults(conversationId);
    }
    final mutedUntilRaw = map['muted_until']?.toString();
    return ConversationNotificationSettings(
      conversationId: conversationId,
      mutedUntil:
          mutedUntilRaw == null ? null : DateTime.tryParse(mutedUntilRaw),
      muteForever: map['mute_forever'] as bool? ?? false,
      mentionsOnly: map['mentions_only'] as bool? ?? false,
      previewEnabled: map['preview_enabled'] as bool? ?? true,
      sound: map['sound'] as String? ?? 'default',
    );
  }
}

final conversationNotificationSettingsProvider =
    FutureProvider.family<ConversationNotificationSettings, String>(
        (ref, conversationId) async {
  final userId = ref.watch(authProvider).user?.id;
  if (userId == null) {
    return ConversationNotificationSettings.defaults(conversationId);
  }
  final row = await Supabase.instance.client
      .from('conversation_notification_settings')
      .select(
          'muted_until, mute_forever, mentions_only, preview_enabled, sound')
      .eq('conversation_id', conversationId)
      .eq('user_id', userId)
      .maybeSingle();
  return ConversationNotificationSettings.fromMap(conversationId, row);
});

final conversationNotificationSettingsRepositoryProvider =
    Provider((ref) => ConversationNotificationSettingsRepository(ref));

class ConversationNotificationSettingsRepository {
  ConversationNotificationSettingsRepository(this._ref);

  final Ref _ref;
  SupabaseClient get _client => Supabase.instance.client;
  String? get _userId => _ref.read(authProvider).user?.id;

  Future<void> setMuted(
    String conversationId, {
    Duration? duration,
    bool forever = false,
  }) async {
    final mutedUntil = duration == null
        ? null
        : DateTime.now().toUtc().add(duration).toIso8601String();
    await _upsert(conversationId, {
      'muted_until': mutedUntil,
      'mute_forever': forever,
      'mentions_only': false,
    });
  }

  Future<void> setMentionsOnly(String conversationId) async {
    await _upsert(conversationId, {
      'muted_until': null,
      'mute_forever': false,
      'mentions_only': true,
    });
  }

  Future<void> enableAll(String conversationId) async {
    await _upsert(conversationId, {
      'muted_until': null,
      'mute_forever': false,
      'mentions_only': false,
    });
  }

  Future<void> setPreviewEnabled(
    String conversationId,
    bool enabled,
  ) async {
    await _upsert(conversationId, {'preview_enabled': enabled});
  }

  Future<void> setSound(String conversationId, String sound) async {
    await _upsert(conversationId, {'sound': sound});
  }

  Future<void> _upsert(
    String conversationId,
    Map<String, dynamic> updates,
  ) async {
    final userId = _userId;
    if (userId == null) return;
    final row = {
      'conversation_id': conversationId,
      'user_id': userId,
      ...updates,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      await _client
          .from('conversation_notification_settings')
          .upsert(row, onConflict: 'user_id,conversation_id');
      if (updates.containsKey('muted_until') ||
          updates.containsKey('mute_forever') ||
          updates.containsKey('mentions_only')) {
        final isMuted = (updates['mute_forever'] as bool? ?? false) ||
            updates['muted_until'] != null ||
            (updates['mentions_only'] as bool? ?? false);
        await _client
            .from('conversation_participants')
            .update({'is_muted': isMuted})
            .eq('conversation_id', conversationId)
            .eq('user_id', userId);
      }
    } catch (e) {
      debugPrint('[ConversationNotificationSettings] upsert failed: $e');
      rethrow;
    }
  }
}
