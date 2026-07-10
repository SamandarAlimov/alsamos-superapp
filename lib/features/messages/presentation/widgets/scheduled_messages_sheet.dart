import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';

class ScheduledMessage {
  final String id;
  final String? content;
  final String? mediaType;
  final DateTime scheduledFor;
  ScheduledMessage({required this.id, this.content, this.mediaType, required this.scheduledFor});
}

class ScheduledMessagesSheet extends StatefulWidget {
  final String conversationId;
  const ScheduledMessagesSheet({super.key, required this.conversationId});

  static Future<void> show(BuildContext context, String conversationId) {
    return showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AlsamosColors.of(context).card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.95, expand: false,
        builder: (_, sc) => ScheduledMessagesSheet(conversationId: conversationId),
      ),
    );
  }

  @override
  State<ScheduledMessagesSheet> createState() => _ScheduledMessagesSheetState();
}

class _ScheduledMessagesSheetState extends State<ScheduledMessagesSheet> {
  bool _loading = true;
  List<ScheduledMessage> _items = [];
  String? _deletingId;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final supa = Supabase.instance.client;
      final uid = supa.auth.currentUser?.id;
      final rows = await supa.from('scheduled_messages').select('*').eq('conversation_id', widget.conversationId).eq('sender_id', uid ?? '').order('scheduled_for', ascending: true);
      _items = (rows as List).map((r) => ScheduledMessage(id: r['id'], content: r['content'], mediaType: r['media_type'], scheduledFor: DateTime.parse(r['scheduled_for']))).toList();
    } catch (_) { _items = []; }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _cancel(String id) async {
    HapticFeedback.lightImpact();
    setState(() => _deletingId = id);
    try {
      await Supabase.instance.client.from('scheduled_messages').delete().eq('id', id);
      _items.removeWhere((m) => m.id == id);
    } catch (_) {}
    if (mounted) setState(() => _deletingId = null);
  }

  IconData? _mediaIcon(String? t) {
    if (t == null) return null;
    if (t.startsWith('image')) return LucideIcons.image;
    if (t.startsWith('video')) return LucideIcons.video;
    if (t == 'voice' || t.startsWith('audio')) return LucideIcons.mic;
    return LucideIcons.fileText;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final groups = <String, List<ScheduledMessage>>{};
    for (final m in _items) {
      final key = DateFormat('yyyy-MM-dd').format(m.scheduledFor);
      groups.putIfAbsent(key, () => []).add(m);
    }

    return Column(children: [
      Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: colors.border, borderRadius: BorderRadius.circular(2))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [
        Icon(LucideIcons.clock, size: 20, color: colors.foreground),
        const SizedBox(width: 8),
        Text('Scheduled messages', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: colors.foreground)),
      ])),
      Divider(height: 1, color: colors.border),
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : _items.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.clock, size: 48, color: colors.mutedForeground.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text('No scheduled messages', style: TextStyle(color: colors.mutedForeground)),
              const SizedBox(height: 4),
              Text('Long press the send button to schedule', style: TextStyle(fontSize: 12, color: colors.mutedForeground.withValues(alpha: 0.7))),
            ]))
          : ListView(padding: const EdgeInsets.all(12), children: [
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(DateFormat('EEEE, MMMM d').format(DateTime.parse(entry.key)), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.mutedForeground)),
                ),
                for (final m in entry.value)
                  Opacity(opacity: _deletingId == m.id ? 0.5 : 1, child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: colors.muted.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(LucideIcons.clock, size: 13, color: primary),
                          const SizedBox(width: 6),
                          Text(DateFormat.jm().format(m.scheduledFor), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary)),
                          if (_mediaIcon(m.mediaType) != null) Padding(padding: const EdgeInsets.only(left: 8), child: Icon(_mediaIcon(m.mediaType), size: 13, color: colors.mutedForeground)),
                        ]),
                        if (m.content != null && m.content!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(m.content!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: colors.foreground))),
                      ])),
                      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(LucideIcons.trash2, size: 16, color: Color(0xFFEF4444)), onPressed: _deletingId == m.id ? null : () => _cancel(m.id)),
                    ]),
                  )),
              ],
            ])),
    ]);
  }
}
