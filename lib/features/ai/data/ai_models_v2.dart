import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MESSAGES — Enhanced with branching, citations, artifacts
// ═══════════════════════════════════════════════════════════════════════════

enum MessageStatus {
  pending,
  streaming,
  complete,
  error,
  stopped,
}

class Citation {
  final String id;
  final String title;
  final String url;
  final String? snippet;
  final int position; // footnote number

  const Citation({
    required this.id,
    required this.title,
    required this.url,
    this.snippet,
    required this.position,
  });

  factory Citation.fromMap(Map<String, dynamic> m) => Citation(
        id: m['id'] as String,
        title: m['title'] as String,
        url: m['url'] as String,
        snippet: m['snippet'] as String?,
        position: m['position'] as int,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'url': url,
        if (snippet != null) 'snippet': snippet,
        'position': position,
      };
}

class AiMessageV2 {
  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  final String? imageUrl;
  final DateTime timestamp;

  // Enhanced fields
  final List<String>? artifactIds;
  final List<Citation>? citations;
  final String? parentMessageId;
  final List<String>? childMessageIds;
  final int? selectedChildIndex;
  final MessageStatus status;
  final Map<String, dynamic>? metadata;

  AiMessageV2({
    required this.id,
    required this.role,
    required this.content,
    this.imageUrl,
    DateTime? timestamp,
    this.artifactIds,
    this.citations,
    this.parentMessageId,
    this.childMessageIds,
    this.selectedChildIndex,
    this.status = MessageStatus.complete,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == 'user';
  bool get hasArtifacts => artifactIds != null && artifactIds!.isNotEmpty;
  bool get hasCitations => citations != null && citations!.isNotEmpty;
  bool get hasBranches => childMessageIds != null && childMessageIds!.isNotEmpty;

  factory AiMessageV2.fromMap(Map<String, dynamic> m) {
    final citationsRaw = m['citations'] as List?;
    final artifactIdsRaw = m['artifactIds'] as List?;
    final childIdsRaw = m['childMessageIds'] as List?;

    return AiMessageV2(
      id: (m['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      role: (m['role'] as String?) ?? 'assistant',
      content: (m['content'] as String?) ?? '',
      imageUrl: m['imageUrl'] as String?,
      timestamp: m['timestamp'] != null
          ? DateTime.tryParse(m['timestamp'].toString())
          : null,
      artifactIds: artifactIdsRaw?.map((e) => e.toString()).toList(),
      citations: citationsRaw
          ?.map((e) => Citation.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      parentMessageId: m['parentMessageId'] as String?,
      childMessageIds: childIdsRaw?.map((e) => e.toString()).toList(),
      selectedChildIndex: m['selectedChildIndex'] as int?,
      status: _parseStatus(m['status'] as String?),
      metadata: m['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'role': role,
        'content': content,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'timestamp': timestamp.toIso8601String(),
        if (artifactIds != null) 'artifactIds': artifactIds,
        if (citations != null)
          'citations': citations!.map((c) => c.toMap()).toList(),
        if (parentMessageId != null) 'parentMessageId': parentMessageId,
        if (childMessageIds != null) 'childMessageIds': childMessageIds,
        if (selectedChildIndex != null) 'selectedChildIndex': selectedChildIndex,
        'status': status.name,
        if (metadata != null) 'metadata': metadata,
      };

  AiMessageV2 copyWith({
    String? content,
    String? imageUrl,
    List<String>? artifactIds,
    List<Citation>? citations,
    String? parentMessageId,
    List<String>? childMessageIds,
    int? selectedChildIndex,
    MessageStatus? status,
    Map<String, dynamic>? metadata,
  }) =>
      AiMessageV2(
        id: id,
        role: role,
        content: content ?? this.content,
        imageUrl: imageUrl ?? this.imageUrl,
        timestamp: timestamp,
        artifactIds: artifactIds ?? this.artifactIds,
        citations: citations ?? this.citations,
        parentMessageId: parentMessageId ?? this.parentMessageId,
        childMessageIds: childMessageIds ?? this.childMessageIds,
        selectedChildIndex: selectedChildIndex ?? this.selectedChildIndex,
        status: status ?? this.status,
        metadata: metadata ?? this.metadata,
      );

  static MessageStatus _parseStatus(String? s) {
    if (s == null) return MessageStatus.complete;
    try {
      return MessageStatus.values.firstWhere((e) => e.name == s);
    } catch (_) {
      return MessageStatus.complete;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONVERSATIONS — Enhanced with project assignment, pinning, custom title
// ═══════════════════════════════════════════════════════════════════════════

class AiConversationV2 {
  final String id;
  final List<AiMessageV2> messages;
  final DateTime updatedAt;
  final DateTime createdAt;
  final String? projectId;
  final String? customTitle;
  final bool isPinned;
  final String type; // 'chat' | 'imagine' (kept for backward compat)

  const AiConversationV2({
    required this.id,
    required this.messages,
    required this.updatedAt,
    DateTime? createdAt,
    this.projectId,
    this.customTitle,
    this.isPinned = false,
    this.type = 'chat',
  }) : createdAt = createdAt ?? updatedAt;

  String get title {
    if (customTitle != null && customTitle!.isNotEmpty) return customTitle!;
    final first = messages
        .where((m) => m.isUser)
        .cast<AiMessageV2?>()
        .firstWhere((_) => true, orElse: () => null);
    if (first == null) return 'Yangi suhbat';
    final t = first.content;
    return t.length > 50 ? '${t.substring(0, 50)}...' : t;
  }

  factory AiConversationV2.fromMap(Map<String, dynamic> m) {
    final raw = (m['messages'] as List?) ?? const [];
    return AiConversationV2(
      id: m['id'] as String,
      messages: raw
          .map((e) => AiMessageV2.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      updatedAt: DateTime.tryParse((m['updated_at'] as String?) ?? '')
              ?.toLocal() ??
          DateTime.now(),
      createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '')?.toLocal(),
      projectId: m['project_id'] as String?,
      customTitle: m['title'] as String?,
      isPinned: m['is_pinned'] as bool? ?? false,
      type: (m['context'] as String?) == 'imagine' ? 'imagine' : 'chat',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'messages': messages.map((m) => m.toMap()).toList(),
        'updated_at': updatedAt.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        if (projectId != null) 'project_id': projectId,
        if (customTitle != null) 'title': customTitle,
        'is_pinned': isPinned,
        'context': type,
      };

  AiConversationV2 copyWith({
    List<AiMessageV2>? messages,
    DateTime? updatedAt,
    String? projectId,
    bool clearProject = false,
    String? customTitle,
    bool? isPinned,
    String? type,
  }) =>
      AiConversationV2(
        id: id,
        messages: messages ?? this.messages,
        updatedAt: updatedAt ?? this.updatedAt,
        createdAt: createdAt,
        projectId: clearProject ? null : (projectId ?? this.projectId),
        customTitle: customTitle ?? this.customTitle,
        isPinned: isPinned ?? this.isPinned,
        type: type ?? this.type,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// PROJECTS — Organize related conversations with custom instructions
// ═══════════════════════════════════════════════════════════════════════════

class AiProject {
  final String id;
  final String name;
  final String? description;
  final String? iconEmoji;
  final Color? color;
  final String? customInstructions;
  final List<String> knowledgeFileIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int conversationCount;

  AiProject({
    required this.id,
    required this.name,
    this.description,
    this.iconEmoji,
    this.color,
    this.customInstructions,
    this.knowledgeFileIds = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
    this.conversationCount = 0,
  })  : createdAt = createdAt ?? updatedAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory AiProject.fromMap(Map<String, dynamic> m) {
    final knowledgeRaw = m['knowledge_file_ids'] as List?;
    final colorValue = m['color'] as String?;

    return AiProject(
      id: m['id'] as String,
      name: m['name'] as String,
      description: m['description'] as String?,
      iconEmoji: m['icon_emoji'] as String?,
      color: colorValue != null ? _parseColor(colorValue) : null,
      customInstructions: m['custom_instructions'] as String?,
      knowledgeFileIds: knowledgeRaw?.map((e) => e.toString()).toList() ?? const [],
      createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '')?.toLocal(),
      updatedAt: DateTime.tryParse((m['updated_at'] as String?) ?? '')?.toLocal(),
      conversationCount: m['conversation_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        if (iconEmoji != null) 'icon_emoji': iconEmoji,
        if (color != null) 'color': '#${color!.toARGB32().toRadixString(16).padLeft(8, '0')}',
        if (customInstructions != null) 'custom_instructions': customInstructions,
        'knowledge_file_ids': knowledgeFileIds,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'conversation_count': conversationCount,
      };

  AiProject copyWith({
    String? name,
    String? description,
    String? iconEmoji,
    Color? color,
    bool clearColor = false,
    String? customInstructions,
    List<String>? knowledgeFileIds,
    DateTime? updatedAt,
    int? conversationCount,
  }) =>
      AiProject(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        iconEmoji: iconEmoji ?? this.iconEmoji,
        color: clearColor ? null : (color ?? this.color),
        customInstructions: customInstructions ?? this.customInstructions,
        knowledgeFileIds: knowledgeFileIds ?? this.knowledgeFileIds,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        conversationCount: conversationCount ?? this.conversationCount,
      );

  static Color? _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', ''), radix: 16));
    } catch (_) {
      return null;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ARTIFACTS — Generated outputs (code, documents, spreadsheets, etc.)
// ═══════════════════════════════════════════════════════════════════════════

enum ArtifactType {
  code,
  document,
  spreadsheet,
  slides,
  diagram,
  image,
  video,
}

class ArtifactVersion {
  final String id;
  final String content;
  final DateTime createdAt;
  final String? changeDescription;

  const ArtifactVersion({
    required this.id,
    required this.content,
    required this.createdAt,
    this.changeDescription,
  });

  factory ArtifactVersion.fromMap(Map<String, dynamic> m) => ArtifactVersion(
        id: m['id'] as String,
        content: m['content'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        changeDescription: m['change_description'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'content': content,
        'created_at': createdAt.toIso8601String(),
        if (changeDescription != null) 'change_description': changeDescription,
      };
}

class AiArtifact {
  final String id;
  final String title;
  final ArtifactType type;
  final String content;
  final String? language;
  final String conversationId;
  final String? messageId;
  final List<ArtifactVersion> versions;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  AiArtifact({
    required this.id,
    required this.title,
    required this.type,
    required this.content,
    this.language,
    required this.conversationId,
    this.messageId,
    this.versions = const [],
    DateTime? createdAt,
    this.metadata,
  }) : createdAt = createdAt ?? DateTime.now();

  factory AiArtifact.fromMap(Map<String, dynamic> m) {
    final versionsRaw = m['versions'] as List?;

    return AiArtifact(
      id: m['id'] as String,
      title: m['title'] as String,
      type: _parseType(m['type'] as String?),
      content: m['content'] as String,
      language: m['language'] as String?,
      conversationId: m['conversation_id'] as String,
      messageId: m['message_id'] as String?,
      versions: versionsRaw
              ?.map((e) =>
                  ArtifactVersion.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      createdAt:
          DateTime.tryParse((m['created_at'] as String?) ?? '')?.toLocal(),
      metadata: m['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'type': type.name,
        'content': content,
        if (language != null) 'language': language,
        'conversation_id': conversationId,
        if (messageId != null) 'message_id': messageId,
        'versions': versions.map((v) => v.toMap()).toList(),
        'created_at': createdAt.toIso8601String(),
        if (metadata != null) 'metadata': metadata,
      };

  AiArtifact copyWith({
    String? title,
    String? content,
    String? language,
    List<ArtifactVersion>? versions,
    Map<String, dynamic>? metadata,
  }) =>
      AiArtifact(
        id: id,
        title: title ?? this.title,
        type: type,
        content: content ?? this.content,
        language: language ?? this.language,
        conversationId: conversationId,
        messageId: messageId,
        versions: versions ?? this.versions,
        createdAt: createdAt,
        metadata: metadata ?? this.metadata,
      );

  static ArtifactType _parseType(String? s) {
    if (s == null) return ArtifactType.code;
    try {
      return ArtifactType.values.firstWhere((e) => e.name == s);
    } catch (_) {
      return ArtifactType.code;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONNECTORS — Integrations (Google, Notion, Alsamos modules, etc.)
// ═══════════════════════════════════════════════════════════════════════════

enum ConnectorType {
  googleDrive,
  gmail,
  googleCalendar,
  notion,
  github,
  alsamosBozor,
  alsamosTolov,
  alsamosXarita,
  custom,
}

class AiConnector {
  final String id;
  final ConnectorType type;
  final String displayName;
  final String? description;
  final bool isConnected;
  final DateTime? lastSyncAt;
  final Map<String, dynamic> config;
  final List<String> permissions;

  const AiConnector({
    required this.id,
    required this.type,
    required this.displayName,
    this.description,
    this.isConnected = false,
    this.lastSyncAt,
    this.config = const {},
    this.permissions = const [],
  });

  factory AiConnector.fromMap(Map<String, dynamic> m) {
    final permissionsRaw = m['permissions'] as List?;

    return AiConnector(
      id: m['id'] as String,
      type: _parseType(m['type'] as String?),
      displayName: m['display_name'] as String,
      description: m['description'] as String?,
      isConnected: m['is_connected'] as bool? ?? false,
      lastSyncAt:
          DateTime.tryParse((m['last_sync_at'] as String?) ?? '')?.toLocal(),
      config: m['config'] as Map<String, dynamic>? ?? const {},
      permissions: permissionsRaw?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'display_name': displayName,
        if (description != null) 'description': description,
        'is_connected': isConnected,
        if (lastSyncAt != null) 'last_sync_at': lastSyncAt!.toIso8601String(),
        'config': config,
        'permissions': permissions,
      };

  AiConnector copyWith({
    String? displayName,
    String? description,
    bool? isConnected,
    DateTime? lastSyncAt,
    bool clearLastSync = false,
    Map<String, dynamic>? config,
    List<String>? permissions,
  }) =>
      AiConnector(
        id: id,
        type: type,
        displayName: displayName ?? this.displayName,
        description: description ?? this.description,
        isConnected: isConnected ?? this.isConnected,
        lastSyncAt: clearLastSync ? null : (lastSyncAt ?? this.lastSyncAt),
        config: config ?? this.config,
        permissions: permissions ?? this.permissions,
      );

  static ConnectorType _parseType(String? s) {
    if (s == null) return ConnectorType.custom;
    try {
      // Handle snake_case from backend
      final normalized = s.replaceAll('_', '').toLowerCase();
      return ConnectorType.values.firstWhere(
        (e) => e.name.toLowerCase() == normalized,
        orElse: () => ConnectorType.custom,
      );
    } catch (_) {
      return ConnectorType.custom;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLUGINS / SKILLS — Extensions that add AI capabilities
// ═══════════════════════════════════════════════════════════════════════════

class AiPlugin {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final bool isEnabled;
  final bool isBuiltIn;
  final String? marketplaceUrl;
  final List<String> capabilities;

  const AiPlugin({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.isEnabled = false,
    this.isBuiltIn = false,
    this.marketplaceUrl,
    this.capabilities = const [],
  });

  factory AiPlugin.fromMap(Map<String, dynamic> m) {
    final capsRaw = m['capabilities'] as List?;

    return AiPlugin(
      id: m['id'] as String,
      name: m['name'] as String,
      description: m['description'] as String,
      icon: _parseIcon(m['icon'] as String?),
      isEnabled: m['is_enabled'] as bool? ?? false,
      isBuiltIn: m['is_built_in'] as bool? ?? false,
      marketplaceUrl: m['marketplace_url'] as String?,
      capabilities: capsRaw?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'icon': icon.codePoint.toString(),
        'is_enabled': isEnabled,
        'is_built_in': isBuiltIn,
        if (marketplaceUrl != null) 'marketplace_url': marketplaceUrl,
        'capabilities': capabilities,
      };

  AiPlugin copyWith({
    String? name,
    String? description,
    IconData? icon,
    bool? isEnabled,
    List<String>? capabilities,
  }) =>
      AiPlugin(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        icon: icon ?? this.icon,
        isEnabled: isEnabled ?? this.isEnabled,
        isBuiltIn: isBuiltIn,
        marketplaceUrl: marketplaceUrl,
        capabilities: capabilities ?? this.capabilities,
      );

  static IconData _parseIcon(String? codePoint) {
    if (codePoint == null) return Icons.extension;
    try {
      final code = int.parse(codePoint);
      // ignore: non_const_argument_for_const_parameter
      return IconData(code, fontFamily: 'MaterialIcons');
    } catch (_) {
      return Icons.extension;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INTENT DETECTION — Auto-route requests to appropriate generation type
// ═══════════════════════════════════════════════════════════════════════════

enum IntentType {
  chat,
  imageGen,
  videoGen,
  codeGen,
  codeExec,
  documentGen,
  spreadsheetGen,
  webSearch,
  translate,
  summarize,
}

class DetectedIntent {
  final IntentType type;
  final double confidence;
  final Map<String, dynamic>? parameters;

  const DetectedIntent({
    required this.type,
    this.confidence = 0.5,
    this.parameters,
  });

  bool get isHighConfidence => confidence >= 0.7;
  bool get requiresConfirmation => confidence < 0.7 && type != IntentType.chat;

  factory DetectedIntent.fromMap(Map<String, dynamic> m) => DetectedIntent(
        type: _parseType(m['type'] as String?),
        confidence: (m['confidence'] as num?)?.toDouble() ?? 0.5,
        parameters: m['parameters'] as Map<String, dynamic>?,
      );

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'confidence': confidence,
        if (parameters != null) 'parameters': parameters,
      };

  static IntentType _parseType(String? s) {
    if (s == null) return IntentType.chat;
    try {
      return IntentType.values.firstWhere((e) => e.name == s);
    } catch (_) {
      return IntentType.chat;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ATTACHMENTS — Files attached to composer
// ═══════════════════════════════════════════════════════════════════════════

enum AttachmentType {
  image,
  video,
  audio,
  document,
  spreadsheet,
  code,
  other,
}

class AttachedFile {
  final String id;
  final String name;
  final String? path;
  final int sizeBytes;
  final AttachmentType type;
  final String? mimeType;
  final String? thumbnailUrl;

  const AttachedFile({
    required this.id,
    required this.name,
    this.path,
    required this.sizeBytes,
    required this.type,
    this.mimeType,
    this.thumbnailUrl,
  });

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory AttachedFile.fromMap(Map<String, dynamic> m) => AttachedFile(
        id: m['id'] as String,
        name: m['name'] as String,
        path: m['path'] as String?,
        sizeBytes: m['size_bytes'] as int,
        type: _parseType(m['type'] as String?),
        mimeType: m['mime_type'] as String?,
        thumbnailUrl: m['thumbnail_url'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        if (path != null) 'path': path,
        'size_bytes': sizeBytes,
        'type': type.name,
        if (mimeType != null) 'mime_type': mimeType,
        if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      };

  static AttachmentType _parseType(String? s) {
    if (s == null) return AttachmentType.other;
    try {
      return AttachmentType.values.firstWhere((e) => e.name == s);
    } catch (_) {
      return AttachmentType.other;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GENERATION TYPE — Track what type of content is being generated
// ═══════════════════════════════════════════════════════════════════════════

enum GenerationType {
  text,
  image,
  video,
  code,
  document,
  spreadsheet,
}

// ═══════════════════════════════════════════════════════════════════════════
// CONVERSATION FILTER — For sidebar search & filtering
// ═══════════════════════════════════════════════════════════════════════════

class ConversationFilter {
  final String? projectId;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? type;
  final bool? pinnedOnly;

  const ConversationFilter({
    this.projectId,
    this.startDate,
    this.endDate,
    this.type,
    this.pinnedOnly,
  });

  ConversationFilter copyWith({
    String? projectId,
    bool clearProject = false,
    DateTime? startDate,
    bool clearStartDate = false,
    DateTime? endDate,
    bool clearEndDate = false,
    String? type,
    bool clearType = false,
    bool? pinnedOnly,
  }) =>
      ConversationFilter(
        projectId: clearProject ? null : (projectId ?? this.projectId),
        startDate: clearStartDate ? null : (startDate ?? this.startDate),
        endDate: clearEndDate ? null : (endDate ?? this.endDate),
        type: clearType ? null : (type ?? this.type),
        pinnedOnly: pinnedOnly ?? this.pinnedOnly,
      );
}
