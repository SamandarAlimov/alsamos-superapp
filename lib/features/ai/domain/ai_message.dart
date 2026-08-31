import 'ai_capabilities.dart';

/// Web repo `src/components/ai/types.ts` bilan bir xil modellar.
/// Kontrakt: `docs/AI_AGENT_CONTRACT.md` (v1.0.0).

enum AIToolStatus { running, done, error }

class AISource {
  const AISource({required this.title, required this.url, this.snippet});

  final String title;
  final String url;
  final String? snippet;

  factory AISource.fromJson(Map<String, dynamic> json) => AISource(
        title: (json['title'] ?? json['url'] ?? '').toString(),
        url: (json['url'] ?? '').toString(),
        snippet: json['snippet'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'url': url,
        if (snippet != null) 'snippet': snippet,
      };
}

class AIToolEvent {
  AIToolEvent({
    required this.id,
    required this.name,
    required this.label,
    required this.status,
    required this.startedAt,
    this.args,
    this.summary,
    this.data,
    this.finishedAt,
  });

  final String id;
  final String name;
  final String label;
  AIToolStatus status;
  final Map<String, dynamic>? args;
  String? summary;
  Map<String, dynamic>? data;
  final DateTime startedAt;
  DateTime? finishedAt;

  Duration? get duration =>
      finishedAt == null ? null : finishedAt!.difference(startedAt);

  factory AIToolEvent.starting({
    required String id,
    required String name,
    Map<String, dynamic>? args,
  }) =>
      AIToolEvent(
        id: id,
        name: name,
        label: toolLabel(name),
        status: AIToolStatus.running,
        args: args,
        startedAt: DateTime.now(),
      );

  void complete({required bool ok, String? summary, Map<String, dynamic>? data}) {
    status = ok ? AIToolStatus.done : AIToolStatus.error;
    this.summary = summary;
    this.data = data;
    finishedAt = DateTime.now();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'label': label,
        'status': status.name,
        if (args != null) 'args': args,
        if (summary != null) 'summary': summary,
        if (data != null) 'data': data,
        'startedAt': startedAt.toIso8601String(),
        if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
      };

  factory AIToolEvent.fromJson(Map<String, dynamic> json) => AIToolEvent(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        label: (json['label'] ?? toolLabel((json['name'] ?? '').toString())).toString(),
        status: AIToolStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => AIToolStatus.done,
        ),
        args: (json['args'] as Map?)?.cast<String, dynamic>(),
        summary: json['summary'] as String?,
        data: (json['data'] as Map?)?.cast<String, dynamic>(),
        startedAt: DateTime.tryParse('${json['startedAt']}') ?? DateTime.now(),
        finishedAt: json['finishedAt'] == null
            ? null
            : DateTime.tryParse('${json['finishedAt']}'),
      );
}

class AIAttachmentMeta {
  const AIAttachmentMeta({required this.url, required this.name, required this.type});

  final String url;
  final String name;
  final String type;

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'url': url, 'name': name, 'type': type};

  factory AIAttachmentMeta.fromJson(Map<String, dynamic> json) => AIAttachmentMeta(
        url: (json['url'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        type: (json['type'] ?? 'file').toString(),
      );
}

enum AIRole { user, assistant }

class AIAgentMessage {
  AIAgentMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.images = const <String>[],
    this.sources = const <AISource>[],
    this.tools = const <AIToolEvent>[],
    this.attachments = const <AIAttachmentMeta>[],
    this.model,
    this.mode,
    this.notice,
    this.isError = false,
  });

  final String id;
  final AIRole role;
  String content;
  final DateTime timestamp;
  List<String> images;
  List<AISource> sources;
  List<AIToolEvent> tools;
  final List<AIAttachmentMeta> attachments;
  String? model;
  final AIMode? mode;
  String? notice;
  bool isError;

  bool get hasTools => tools.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        if (images.isNotEmpty) 'images': images,
        if (sources.isNotEmpty) 'sources': sources.map((s) => s.toJson()).toList(),
        if (tools.isNotEmpty) 'tools': tools.map((t) => t.toJson()).toList(),
        if (attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
        if (model != null) 'model': model,
        if (mode != null) 'mode': aiModeToJson(mode!),
        if (notice != null) 'notice': notice,
        if (isError) 'error': true,
      };

  factory AIAgentMessage.fromJson(Map<String, dynamic> json) => AIAgentMessage(
        id: (json['id'] ?? '').toString(),
        role: json['role'] == 'assistant' ? AIRole.assistant : AIRole.user,
        content: (json['content'] ?? '').toString(),
        timestamp: DateTime.tryParse('${json['timestamp']}') ?? DateTime.now(),
        images: ((json['images'] as List?) ?? const <dynamic>[])
            .map((e) => e.toString())
            .toList(),
        sources: ((json['sources'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((e) => AISource.fromJson(e.cast<String, dynamic>()))
            .toList(),
        tools: ((json['tools'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((e) => AIToolEvent.fromJson(e.cast<String, dynamic>()))
            .toList(),
        attachments: ((json['attachments'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((e) => AIAttachmentMeta.fromJson(e.cast<String, dynamic>()))
            .toList(),
        model: json['model'] as String?,
        mode: json['mode'] == null ? null : aiModeFromJson(json['mode'] as String?),
        notice: json['notice'] as String?,
        isError: json['error'] == true,
      );
}

/// `ai_computer_tasks` yozuvi — tasdiq oqimi uchun.
enum ComputerTaskStatus {
  pendingApproval,
  approved,
  running,
  done,
  failed,
  rejected,
  expired,
}

ComputerTaskStatus computerTaskStatusFromDb(String? value) {
  switch (value) {
    case 'pending_approval':
      return ComputerTaskStatus.pendingApproval;
    case 'approved':
      return ComputerTaskStatus.approved;
    case 'running':
      return ComputerTaskStatus.running;
    case 'done':
      return ComputerTaskStatus.done;
    case 'failed':
      return ComputerTaskStatus.failed;
    case 'rejected':
      return ComputerTaskStatus.rejected;
    default:
      return ComputerTaskStatus.expired;
  }
}

String computerTaskStatusToDb(ComputerTaskStatus status) {
  switch (status) {
    case ComputerTaskStatus.pendingApproval:
      return 'pending_approval';
    case ComputerTaskStatus.approved:
      return 'approved';
    case ComputerTaskStatus.running:
      return 'running';
    case ComputerTaskStatus.done:
      return 'done';
    case ComputerTaskStatus.failed:
      return 'failed';
    case ComputerTaskStatus.rejected:
      return 'rejected';
    case ComputerTaskStatus.expired:
      return 'expired';
  }
}

class ComputerTask {
  const ComputerTask({
    required this.id,
    required this.action,
    required this.status,
    this.payload,
    this.result,
    this.error,
    this.reason,
    this.expiresAt,
    this.createdAt,
  });

  final String id;
  final String action;
  final ComputerTaskStatus status;
  final Map<String, dynamic>? payload;
  final Map<String, dynamic>? result;
  final String? error;
  final String? reason;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get needsApproval =>
      status == ComputerTaskStatus.pendingApproval && !isExpired;

  factory ComputerTask.fromJson(Map<String, dynamic> json) => ComputerTask(
        id: (json['id'] ?? '').toString(),
        action: (json['action'] ?? '').toString(),
        status: computerTaskStatusFromDb(json['status'] as String?),
        payload: (json['payload'] as Map?)?.cast<String, dynamic>(),
        result: (json['result'] as Map?)?.cast<String, dynamic>(),
        error: json['error'] as String?,
        reason: json['reason'] as String?,
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.tryParse('${json['expires_at']}'),
        createdAt: json['created_at'] == null
            ? null
            : DateTime.tryParse('${json['created_at']}'),
      );
}
