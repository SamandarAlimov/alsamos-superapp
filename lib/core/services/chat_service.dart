// Chat service for creating product inquiry conversations

import 'package:supabase_flutter/supabase_flutter.dart';

class ChatService {
  final SupabaseClient _supabase;

  const ChatService(this._supabase);

  /// Get or create private conversation with seller about a product
  /// Returns conversation ID
  Future<String?> getOrCreateProductConversation({
    required String sellerId,
    required String productId,
    required String productTitle,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return null;

    try {
      // Check if conversation already exists between buyer and seller
      final existingParticipations = await _supabase
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', currentUserId);

      if (existingParticipations.isNotEmpty) {
        // Check each conversation to see if it's with this seller
        for (final participation in existingParticipations) {
          final convId = participation['conversation_id'] as String;
          
          // Check if this conversation is private and has the seller as participant
          final conv = await _supabase
              .from('conversations')
              .select('id, type')
              .eq('id', convId)
              .eq('type', 'private')
              .maybeSingle();

          if (conv != null) {
            // Check if seller is participant
            final sellerParticipation = await _supabase
                .from('conversation_participants')
                .select('user_id')
                .eq('conversation_id', convId)
                .eq('user_id', sellerId)
                .maybeSingle();

            if (sellerParticipation != null) {
              // Found existing conversation
              return convId;
            }
          }
        }
      }

      // Create new conversation
      final newConv = await _supabase
          .from('conversations')
          .insert({
            'type': 'private',
            'created_by': currentUserId,
            'last_message_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      final conversationId = newConv['id'] as String;

      // Add participants
      await _supabase.from('conversation_participants').insert([
        {
          'conversation_id': conversationId,
          'user_id': currentUserId,
          'joined_at': DateTime.now().toIso8601String(),
        },
        {
          'conversation_id': conversationId,
          'user_id': sellerId,
          'joined_at': DateTime.now().toIso8601String(),
        },
      ]);

      // Send initial product reference message
      await _supabase.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': currentUserId,
        'content': 'Mahsulot haqida savol: $productTitle',
        'type': 'text',
        'metadata': {
          'product_id': productId,
          'product_title': productTitle,
          'is_product_reference': true,
        },
      });

      return conversationId;
    } catch (e) {
      return null;
    }
  }

  /// Send product reference message to existing conversation
  Future<bool> sendProductReference({
    required String conversationId,
    required String productId,
    required String productTitle,
    String? imageUrl,
    double? price,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return false;

    try {
      await _supabase.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': currentUserId,
        'content': productTitle,
        'type': 'product_card',
        'metadata': {
          'product_id': productId,
          'product_title': productTitle,
          if (imageUrl != null) 'image_url': imageUrl,
          if (price != null) 'price': price,
        },
      });
      return true;
    } catch (e) {
      return false;
    }
  }
}
