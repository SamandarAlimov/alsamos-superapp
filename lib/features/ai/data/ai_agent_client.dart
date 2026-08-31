import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/ai_capabilities.dart';

/// `ai-agent` edge funksiyasining SSE hodisalari.
/// Kontrakt: socialalsamos `docs/AI_PLATFORM_SPEC.md` (v1.0.0).
sealed class AgentEvent {
  const AgentEvent();

  static AgentEvent? fromJson(Map<String, dynamic> json) {
    switch (json['type'] as String?) {
      case 'meta':
        return AgentMeta(
          model: json['model'] as String? ?? '',
          task: json['task'] as String?,
          language: json['language'] as String?,
        );
      case 'delta':
        return AgentDelta(json['text'] as String? ?? '');
      case 'tool_call':
        return AgentToolCall(
          id: json['id'] as String? ?? '',
          name: json['name'] as String? ?? '',
          args: (json['args'] as Map?)?.cast<String, dynamic>(),
        );
      case 'tool_result':
        return AgentToolResult(
          id: json['id'] as String? ?? '',
          name: json['name'] as String? ?? '',
          ok: json['ok'] as bool? ?? false,
          summary: json['summary'] as String?,
          data: (json['data'] as Map?)?.cast<String, dynamic>(),
        );
      case 'notice':
        return AgentNotice(json['message'] as String? ?? '');
      case 'error':
        return AgentError(json['message'] as String? ?? 'Xatolik');
      default:
        return null;
    }
  }
}

class AgentMeta extends AgentEvent {
  const AgentMeta({required this.model, this.task, this.language});
  final String model;
  final String? task;
  final String? language;
}

class AgentDelta extends AgentEvent {
  const AgentDelta(this.text);
  final String text;
}

class AgentToolCall extends AgentEvent {
  const AgentToolCall({required this.id, required this.name, this.args});
  final String id;
  final String name;
  final Map<String, dynamic>? args;
}

class AgentToolResult extends AgentEvent {
  const AgentToolResult({
    required this.id,
    required this.name,
    required this.ok,
    this.summary,
    this.data,
  });
  final String id;
  final String name;
  final bool ok;
  final String? summary;
  final Map<String, dynamic>? data;

  String? get imageUrl => data?['imageUrl'] as String?;
  String? get jobId => data?['jobId'] as String?;
  String? get taskId => data?['taskId'] as String?;
  List<Map<String, dynamic>> get sources =>
      ((data?['sources'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
}

class AgentNotice extends AgentEvent {
  const AgentNotice(this.message);
  final String message;
}

class AgentError extends AgentEvent {
  const AgentError(this.message);
  final String message;
}

class AgentChatMessage {
  const AgentChatMessage({required this.role, required this.content});
  final String role; // 'user' | 'assistant'
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class SandboxRun {
  const SandboxRun({
    required this.ok,
    required this.logs,
    required this.durationMs,
    this.result,
    this.error,
  });

  final bool ok;
  final List<String> logs;
  final int durationMs;
  final dynamic result;
  final String? error;

  factory SandboxRun.fromJson(Map<String, dynamic> json) => SandboxRun(
        ok: json['ok'] as bool? ?? false,
        logs: ((json['logs'] as List?) ?? const <dynamic>[])
            .map((e) => e.toString())
            .toList(),
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        result: json['result'],
        error: json['error'] as String?,
      );
}

/// Edge funksiyalari uchun klient. Web reposidagi `src/lib/ai/agentClient.ts`
/// bilan bir xil so'rov/hodisa formatidan foydalanadi.
class AiAgentClient {
  AiAgentClient({http.Client? httpClient, SupabaseClient? supabase})
      : _http = httpClient ?? http.Client(),
        _supabase = supabase ?? Supabase.instance.client;

  final http.Client _http;
  final SupabaseClient _supabase;

  static const String _agentFunction = 'ai-agent';
  static const String _sandboxFunction = 'code-sandbox';

  Uri _functionUri(String name) {
    // Diqqat: to'liq URL literalidan qochamiz, bo'laklardan yig'amiz.
    final base = _supabase.functionsUrl.endsWith('/')
        ? _supabase.functionsUrl.substring(0, _supabase.functionsUrl.length - 1)
        : _supabase.functionsUrl;
    return Uri.parse('$base/$name');
  }

  Map<String, String> _headers() {
    final session = _supabase.auth.currentSession;
    return <String, String>{
      'Content-Type': 'application/json',
      if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
      'apikey': _supabase.supabaseKey,
      'Accept': 'text/event-stream',
    };
  }

  /// `ai-agent` ni oqim (SSE) rejimida chaqiradi.
  Stream<AgentEvent> streamAgent({
    required List<AgentChatMessage> messages,
    AIMode mode = AIMode.chat,
    ModelId model = ModelId.auto,
    List<ToolGroupId> toolGroups = kDefaultToolGroups,
    String? conversationId,
  }) async* {
    final request = http.Request('POST', _functionUri(_agentFunction))
      ..headers.addAll(_headers())
      ..body = jsonEncode(<String, dynamic>{
        'messages': messages.map((m) => m.toJson()).toList(),
        'mode': aiModeToJson(mode),
        'model': modelIdToJson(model),
        'toolGroups': toolGroups.map(toolGroupIdToJson).toList(),
        if (conversationId != null) 'conversationId': conversationId,
        'contractVersion': aiContractVersion,
      });

    final response = await _http.send(request);

    if (response.statusCode >= 400) {
      final body = await response.stream.bytesToString();
      String message = "AI xizmati bilan xatolik (${response.statusCode})";
      try {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        message = (decoded['error'] ?? decoded['message'] ?? message).toString();
      } catch (_) {
        /* matn emas — standart xabar */
      }
      yield AgentError(message);
      return;
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty || line.startsWith(':')) continue;
      if (!line.startsWith('data: ')) continue;
      final payload = line.substring(6).trim();
      if (payload == '[DONE]') return;
      try {
        final json = jsonDecode(payload) as Map<String, dynamic>;
        final event = AgentEvent.fromJson(json);
        if (event != null) yield event;
      } catch (_) {
        // Yarim kelgan bo'lak — e'tiborsiz qoldiramiz.
      }
    }
  }

  /// Kodni server sandbox'ida ishga tushiradi (`code-sandbox`).
  Future<SandboxRun> runInSandbox(String code, {int timeoutMs = 5000}) async {
    final response = await _http.post(
      _functionUri(_sandboxFunction),
      headers: <String, String>{
        ..._headers(),
        'Accept': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{'code': code, 'timeoutMs': timeoutMs}),
    );

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return const SandboxRun(
        ok: false,
        logs: <String>[],
        durationMs: 0,
        error: 'Sandbox javobi tushunarsiz',
      );
    }
    return SandboxRun.fromJson(decoded);
  }

  void dispose() => _http.close();
}
