import '../../../../core/supabase/supabase_client.dart';
import '../models/message_model.dart';

abstract class ContentAiService {
  Future<Map<String, dynamic>> translate({
    required Message message,
    required String targetLanguage,
  });

  Future<Map<String, dynamic>> transcribe(Message message);
}

class SupabaseContentAiService implements ContentAiService {
  const SupabaseContentAiService();

  @override
  Future<Map<String, dynamic>> translate({
    required Message message,
    required String targetLanguage,
  }) async {
    final response =
        await supabase.functions.invoke('message-translate', body: {
      'message_id': message.id,
      'text': message.content ?? '',
      'target_language': targetLanguage,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }

  @override
  Future<Map<String, dynamic>> transcribe(Message message) async {
    final response = await supabase.functions.invoke('voice-transcribe', body: {
      'message_id': message.id,
      'audio_url': message.mediaUrl,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }
}
