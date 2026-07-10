import 'package:flutter/foundation.dart';
import '../../../core/supabase/supabase_client.dart';

/// Helper class to create test messages for debugging
class TestMessagesHelper {
  static Future<void> createTestConversationAndMessages(String userId) async {
    debugPrint('[TestMessagesHelper] Creating test data for user: $userId');
    
    try {
      // Check if test conversation already exists
      final existing = await supabase
          .from('conversations')
          .select('id')
          .eq('id', 'test-conv-$userId')
          .maybeSingle();
      
      if (existing != null) {
        debugPrint('[TestMessagesHelper] Test conversation already exists');
        return;
      }
      
      // Create test conversation
      final conv = await supabase
          .from('conversations')
          .insert({
            'id': 'test-conv-$userId',
            'type': 'private',
            'owner_id': userId,
            'last_message_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select()
          .single();
      
      debugPrint('[TestMessagesHelper] Created conversation: ${conv['id']}');
      
      // Add user as participant
      await supabase
          .from('conversation_participants')
          .insert({
            'conversation_id': conv['id'],
            'user_id': userId,
            'role': 'owner',
          });
      
      debugPrint('[TestMessagesHelper] Added user as participant');
      
      // Create test messages
      final messages = [
        {
          'conversation_id': conv['id'],
          'sender_id': userId,
          'content': 'Salom! Bu test xabar',
          'created_at': DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String(),
        },
        {
          'conversation_id': conv['id'],
          'sender_id': userId,
          'content': 'Qalaysiz? Hammasi yaxshimi?',
          'created_at': DateTime.now().subtract(const Duration(minutes: 4)).toUtc().toIso8601String(),
        },
        {
          'conversation_id': conv['id'],
          'sender_id': userId,
          'content': 'Messages feature ishlayaptimi?',
          'created_at': DateTime.now().subtract(const Duration(minutes: 3)).toUtc().toIso8601String(),
        },
        {
          'conversation_id': conv['id'],
          'sender_id': userId,
          'content': 'Professional UI juda chiroyli 🎉',
          'created_at': DateTime.now().subtract(const Duration(minutes: 2)).toUtc().toIso8601String(),
        },
        {
          'conversation_id': conv['id'],
          'sender_id': userId,
          'content': 'Hamma narsalar to\'g\'ri ishlashi kerak',
          'created_at': DateTime.now().subtract(const Duration(minutes: 1)).toUtc().toIso8601String(),
        },
      ];
      
      await supabase.from('messages').insert(messages);
      
      debugPrint('[TestMessagesHelper] Created ${messages.length} test messages');
      debugPrint('[TestMessagesHelper] Test data created successfully!');
      
    } catch (e, st) {
      debugPrint('[TestMessagesHelper] Error creating test data: $e');
      debugPrint('[TestMessagesHelper] Stack trace: $st');
    }
  }
}
