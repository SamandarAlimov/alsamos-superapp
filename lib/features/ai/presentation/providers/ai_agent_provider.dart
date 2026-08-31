import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/ai_agent_client.dart';
import '../../domain/ai_capabilities.dart';
import '../../domain/ai_message.dart';

/// Agent klienti (SSE + sandbox).
final aiAgentClientProvider = Provider<AiAgentClient>((ref) {
  final client = AiAgentClient();
  ref.onDispose(client.dispose);
  return client;
});

/// Foydalanuvchi tanlagan rejim / model / vosita guruhlari.
class AiAgentSettings {
  const AiAgentSettings({
    this.mode = AIMode.chat,
    this.model = ModelId.auto,
    this.toolGroups = kDefaultToolGroups,
  });

  final AIMode mode;
  final ModelId model;
  final List<ToolGroupId> toolGroups;

  bool isEnabled(ToolGroupId id) => toolGroups.contains(id);

  /// Serverga yuboriladigan yakuniy guruhlar (agent rejimi hisobga olinadi).
  List<ToolGroupId> get effectiveGroups => groupsForMode(mode, toolGroups);

  String get modelLabel => kModelOptions
      .firstWhere((o) => o.id == model, orElse: () => kModelOptions.first)
      .label;

  AiAgentSettings copyWith({
    AIMode? mode,
    ModelId? model,
    List<ToolGroupId>? toolGroups,
  }) =>
      AiAgentSettings(
        mode: mode ?? this.mode,
        model: model ?? this.model,
        toolGroups: toolGroups ?? this.toolGroups,
      );
}

class AiAgentSettingsNotifier extends StateNotifier<AiAgentSettings> {
  AiAgentSettingsNotifier() : super(const AiAgentSettings());

  void setMode(AIMode mode) => state = state.copyWith(mode: mode);

  void setModel(ModelId model) => state = state.copyWith(model: model);

  void toggleGroup(ToolGroupId id, bool enabled) {
    final next = <ToolGroupId>{...state.toolGroups};
    if (enabled) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = state.copyWith(toolGroups: next.toList());
  }

  void enableGroups(Iterable<ToolGroupId> ids) {
    final next = <ToolGroupId>{...state.toolGroups, ...ids};
    state = state.copyWith(toolGroups: next.toList());
  }

  void reset() => state = const AiAgentSettings();
}

final aiAgentSettingsProvider =
    StateNotifierProvider<AiAgentSettingsNotifier, AiAgentSettings>(
  (ref) => AiAgentSettingsNotifier(),
);

/// Tasdiq kutayotgan kompyuter vazifalari.
final pendingComputerTasksProvider =
    FutureProvider.autoDispose<List<ComputerTask>>((ref) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return const <ComputerTask>[];

  final rows = await supabase
      .from('ai_computer_tasks')
      .select()
      .eq('user_id', userId)
      .eq('status', 'pending_approval')
      .order('created_at', ascending: false)
      .limit(10);

  return (rows as List)
      .whereType<Map>()
      .map((row) => ComputerTask.fromJson(row.cast<String, dynamic>()))
      .where((task) => !task.isExpired)
      .toList();
});

/// Vazifani tasdiqlash / rad etish amallari.
class ComputerTaskActions {
  ComputerTaskActions(this._ref);

  final Ref _ref;
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<void> approve(String taskId) async {
    await _supabase
        .from('ai_computer_tasks')
        .update(<String, dynamic>{
          'status': computerTaskStatusToDb(ComputerTaskStatus.approved),
          'approved_at': DateTime.now().toIso8601String(),
        })
        .eq('id', taskId)
        .eq('status', computerTaskStatusToDb(ComputerTaskStatus.pendingApproval));
    _ref.invalidate(pendingComputerTasksProvider);
  }

  Future<void> reject(String taskId, {String? reason}) async {
    await _supabase
        .from('ai_computer_tasks')
        .update(<String, dynamic>{
          'status': computerTaskStatusToDb(ComputerTaskStatus.rejected),
          if (reason != null) 'reason': reason,
        })
        .eq('id', taskId)
        .eq('status', computerTaskStatusToDb(ComputerTaskStatus.pendingApproval));
    _ref.invalidate(pendingComputerTasksProvider);
  }
}

final computerTaskActionsProvider =
    Provider<ComputerTaskActions>((ref) => ComputerTaskActions(ref));
