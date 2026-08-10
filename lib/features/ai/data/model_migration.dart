import 'ai_models.dart';
import 'ai_models_v2.dart';

/// Utilities for migrating between old (V1) and new (V2) AI data models.
/// Ensures backward compatibility during the transition period.
class ModelMigration {
  /// Convert old AiMessage to new AiMessageV2
  static AiMessageV2 messageToV2(AiMessage old) {
    return AiMessageV2(
      id: old.id,
      role: old.role,
      content: old.content,
      imageUrl: old.imageUrl,
      timestamp: old.timestamp,
      status: MessageStatus.complete,
    );
  }

  /// Convert new AiMessageV2 to old AiMessage (for legacy code)
  static AiMessage messageToV1(AiMessageV2 msg) {
    return AiMessage(
      id: msg.id,
      role: msg.role,
      content: msg.content,
      imageUrl: msg.imageUrl,
      timestamp: msg.timestamp,
    );
  }

  /// Convert old AiConversation to new AiConversationV2
  static AiConversationV2 conversationToV2(AiConversation old) {
    return AiConversationV2(
      id: old.id,
      messages: old.messages.map(messageToV2).toList(),
      updatedAt: old.updatedAt,
      createdAt: old.updatedAt, // use updatedAt as fallback
      type: old.type,
      isPinned: false,
    );
  }

  /// Convert new AiConversationV2 to old AiConversation (for legacy code)
  static AiConversation conversationToV1(AiConversationV2 conv) {
    return AiConversation(
      id: conv.id,
      messages: conv.messages.map(messageToV1).toList(),
      updatedAt: conv.updatedAt,
      type: conv.type,
    );
  }

  /// Batch convert list of conversations
  static List<AiConversationV2> conversationsToV2(
      List<AiConversation> oldList) {
    return oldList.map(conversationToV2).toList();
  }

  /// Batch convert list of messages
  static List<AiMessageV2> messagesToV2(List<AiMessage> oldList) {
    return oldList.map(messageToV2).toList();
  }

  /// Batch convert list of conversations back to V1
  static List<AiConversation> conversationsToV1(
      List<AiConversationV2> newList) {
    return newList.map(conversationToV1).toList();
  }

  /// Batch convert list of messages back to V1
  static List<AiMessage> messagesToV1(List<AiMessageV2> newList) {
    return newList.map(messageToV1).toList();
  }

  /// Upgrade a conversation's messages from V1 format stored in DB
  static AiConversationV2 upgradeConversationFromMap(
      Map<String, dynamic> dbData) {
    // First try to parse as V2
    try {
      return AiConversationV2.fromMap(dbData);
    } catch (_) {
      // Fallback: parse as V1 and convert
      final oldConv = AiConversation.fromMap(dbData);
      return conversationToV2(oldConv);
    }
  }

  /// Create a default project for migrated conversations
  static AiProject createDefaultProject(String userId) {
    return AiProject(
      id: 'default-$userId',
      name: 'General',
      description: 'Default project for all conversations',
      iconEmoji: '💬',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}
