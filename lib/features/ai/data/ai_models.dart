/// Ported from web AIPage / AIContext message + conversation shapes.
class AiMessage {
  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  final String? imageUrl;
  final DateTime timestamp;

  AiMessage({
    required this.id,
    required this.role,
    required this.content,
    this.imageUrl,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == 'user';

  factory AiMessage.fromMap(Map<String, dynamic> m) => AiMessage(
        id: (m['id'] as String?) ?? DateTime.now().microsecondsSinceEpoch.toString(),
        role: (m['role'] as String?) ?? 'assistant',
        content: (m['content'] as String?) ?? '',
        imageUrl: m['imageUrl'] as String?,
        timestamp: m['timestamp'] != null ? DateTime.tryParse(m['timestamp'].toString()) : null,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'role': role,
        'content': content,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'timestamp': timestamp.toIso8601String(),
      };

  AiMessage copyWith({String? content, String? imageUrl}) => AiMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        imageUrl: imageUrl ?? this.imageUrl,
        timestamp: timestamp,
      );
}

class AiConversation {
  final String id;
  final List<AiMessage> messages;
  final DateTime updatedAt;
  final String type; // 'chat' | 'imagine'

  const AiConversation({
    required this.id,
    required this.messages,
    required this.updatedAt,
    this.type = 'chat',
  });

  String get title {
    final first = messages.where((m) => m.isUser).cast<AiMessage?>().firstWhere((_) => true, orElse: () => null);
    if (first == null) return 'Yangi suhbat';
    final t = first.content;
    return t.length > 50 ? '${t.substring(0, 50)}...' : t;
  }

  factory AiConversation.fromMap(Map<String, dynamic> m) {
    final raw = (m['messages'] as List?) ?? const [];
    return AiConversation(
      id: m['id'] as String,
      messages: raw.map((e) => AiMessage.fromMap(Map<String, dynamic>.from(e as Map))).toList(),
      updatedAt: DateTime.tryParse((m['updated_at'] as String?) ?? '')?.toLocal() ?? DateTime.now(),
      type: (m['context'] as String?) == 'imagine' ? 'imagine' : 'chat',
    );
  }
}
