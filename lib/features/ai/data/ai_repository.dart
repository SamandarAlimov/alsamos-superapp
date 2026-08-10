import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';
import 'ai_models.dart';

/// Ported from web AIPage/AIContext. Talks to the Supabase edge functions
/// `ai-assistant` (SSE chat) and `ai-generate-image`, persists to
/// `ai_conversations`.
class AiRepository extends BaseRepository {
  const AiRepository({
    SupabaseDataSource db = const SupabaseDataSource(),
  }) : _db = db;

  final SupabaseDataSource _db;

  Future<List<AiConversation>> loadConversations(String userId) async {
    return guard('loadConversations', () async {
      final res = await _db
          .table('ai_conversations')
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false);
      return (res as List)
          .map((e) => AiConversation.fromMap(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<String?> createConversation(
      String userId, List<AiMessage> messages, String context) async {
    return guard('createConversation', () async {
      final res = await _db
          .table('ai_conversations')
          .insert({
            'user_id': userId,
            'messages': messages.map((m) => m.toMap()).toList(),
            'context': context,
          })
          .select()
          .single();
      return res['id'] as String?;
    });
  }

  Future<void> updateConversation(String id, List<AiMessage> messages) async {
    return guard('updateConversation', () async {
      await _db.table('ai_conversations').update({
        'messages': messages.map((m) => m.toMap()).toList(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
    });
  }

  Future<void> deleteConversation(String id) async {
    return guard('deleteConversation', () async {
      await _db.table('ai_conversations').delete().eq('id', id);
    });
  }

  /// Streams assistant text deltas from the `ai-assistant` edge function,
  /// parsing the OpenAI-style SSE format used by the web client.
  Stream<String> streamChat(List<AiMessage> messages, String userId,
      {String? contextInfo}) async* {
    final uri =
        Uri.parse('${ApiConstants.supabaseUrl}/functions/v1/ai-assistant');
    final aiMessages =
        messages.map((m) => {'role': m.role, 'content': m.content}).toList();
    if (contextInfo != null &&
        contextInfo.isNotEmpty &&
        aiMessages.isNotEmpty) {
      aiMessages[0] = {
        ...aiMessages[0],
        'content': '${aiMessages[0]['content']}$contextInfo',
      };
    }

    final req = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = 'Bearer ${ApiConstants.supabaseAnonKey}'
      ..body = jsonEncode({'messages': aiMessages, 'userId': userId});

    final client = http.Client();
    try {
      final resp = await client.send(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('AI xizmati bilan xatolik (${resp.statusCode})');
      }
      var buffer = '';
      await for (final chunk in resp.stream.transform(utf8.decoder)) {
        buffer += chunk;
        int nl;
        while ((nl = buffer.indexOf('\n')) != -1) {
          var line = buffer.substring(0, nl);
          buffer = buffer.substring(nl + 1);
          if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
          if (line.startsWith(':') || line.trim().isEmpty) continue;
          if (!line.startsWith('data: ')) continue;
          final jsonStr = line.substring(6).trim();
          if (jsonStr == '[DONE]') return;
          try {
            final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
            final delta =
                (parsed['choices'] as List?)?.first?['delta']?['content'];
            if (delta is String && delta.isNotEmpty) yield delta;
          } catch (_) {
            buffer = '$line\n$buffer';
            break;
          }
        }
      }
    } finally {
      client.close();
    }
  }

  /// Invokes the `ai-generate-image` edge function and returns the image URL
  /// (and optional revised_prompt). Mirrors the web `supabase.functions.invoke`
  /// call in `AIPage.generateImage`.
  Future<({String imageUrl, String? revisedPrompt})> generateImage(
      String prompt) async {
    return guard('generateImage', () async {
      final res = await _db.invokeFunction(
        'ai-generate-image',
        body: {'prompt': prompt},
      );
      if (res.status >= 400) {
        throw Exception('Rasm yaratishda xatolik (${res.status})');
      }
      final data = res.data;
      if (data is Map) {
        final url = (data['image_url'] ?? data['imageUrl']) as String?;
        final rev =
            (data['revised_prompt'] ?? data['revisedPrompt']) as String?;
        if (url == null || url.isEmpty) {
          throw Exception('Rasm yaratilmadi');
        }
        return (imageUrl: url, revisedPrompt: rev);
      }
      throw Exception('Noma\'lum javob formati');
    });
  }

  /// Fetches a public post snapshot so the AIPage can show a forwarded-post
  /// context card. Mirrors the `posts` select used by the web client.
  Future<({String id, String? content, String? authorName, String? mediaUrl})?>
      fetchForwardedPost(String postId) async {
    return guard('fetchForwardedPost', () async {
      try {
        final res = await _db
            .table('posts')
            .select(
                'id, content, media_urls, media_type, profile:profiles!posts_user_id_fkey(display_name, username, avatar_url)')
            .eq('id', postId)
            .maybeSingle();
        if (res == null) return null;
        final profile = res['profile'] as Map?;
        final media = res['media_urls'];
        String? firstMedia;
        if (media is List && media.isNotEmpty) {
          firstMedia = media.first?.toString();
        }
        return (
          id: res['id'] as String,
          content: res['content'] as String?,
          authorName:
              (profile?['display_name'] ?? profile?['username']) as String?,
          mediaUrl: firstMedia,
        );
      } catch (_) {
        return null;
      }
    });
  }
}
