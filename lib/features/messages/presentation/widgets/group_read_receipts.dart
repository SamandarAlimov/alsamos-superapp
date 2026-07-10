import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/user_avatar.dart';

class GroupReadReceiptEntry {
  final String userId;
  final DateTime readAt;
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  GroupReadReceiptEntry({required this.userId, required this.readAt, this.displayName, this.username, this.avatarUrl});
}

// Group chat read receipts popover — ports messages/GroupReadReceipts.tsx
class GroupReadReceipts extends StatefulWidget {
  final String messageId;
  final String? senderId;
  final bool isMine;
  const GroupReadReceipts({super.key, required this.messageId, required this.senderId, required this.isMine});

  static Future<void> show(BuildContext context, {required String messageId, String? senderId, bool isMine = false}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AlsamosColors.of(context).card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => GroupReadReceipts(messageId: messageId, senderId: senderId, isMine: isMine),
    );
  }

  @override
  State<GroupReadReceipts> createState() => _GroupReadReceiptsState();
}

class _GroupReadReceiptsState extends State<GroupReadReceipts> {
  List<GroupReadReceiptEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final supa = Supabase.instance.client;
      var query = supa.from('message_reads').select('user_id, read_at').eq('message_id', widget.messageId);
      if (widget.senderId != null) query = query.neq('user_id', widget.senderId!);
      final rows = await query;
      final list = (rows as List);
      if (list.isEmpty) { if (mounted) setState(() { _entries = []; _loading = false; }); return; }
      final userIds = list.map((r) => r['user_id'] as String).toList();
      final profiles = await supa.from('profiles').select('id, display_name, username, avatar_url').inFilter('id', userIds);
      final byId = {for (final p in (profiles as List)) p['id']: p};
      _entries = list.map((r) {
        final p = byId[r['user_id']];
        return GroupReadReceiptEntry(
          userId: r['user_id'], readAt: DateTime.parse(r['read_at']),
          displayName: p?['display_name'], username: p?['username'], avatarUrl: p?['avatar_url'],
        );
      }).toList()..sort((a, b) => b.readAt.compareTo(a.readAt));
    } catch (_) { _entries = []; }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: colors.border, borderRadius: BorderRadius.circular(2))),
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(LucideIcons.eye, size: 18, color: primary),
        const SizedBox(width: 8),
        Text(_loading ? 'Read by...' : 'Read by ${_entries.length}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.foreground)),
      ])),
      Divider(height: 1, color: colors.border),
      if (_loading) const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())
      else if (_entries.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text('No reads yet', style: TextStyle(color: colors.mutedForeground)))
      else ConstrainedBox(constraints: const BoxConstraints(maxHeight: 360), child: ListView.builder(
          shrinkWrap: true,
          itemCount: _entries.length,
          itemBuilder: (_, i) {
            final e = _entries[i];
            final name = e.displayName ?? e.username ?? 'User';
            return ListTile(
              leading: UserAvatar(avatarUrl: e.avatarUrl, fallback: name[0].toUpperCase(), size: 38, backgroundColor: primary),
              title: Text(name, style: const TextStyle(fontSize: 14)),
              trailing: Text(DateFormat.Hm().format(e.readAt), style: TextStyle(fontSize: 11, color: colors.mutedForeground)),
            );
          },
        )),
    ]));
  }
}
