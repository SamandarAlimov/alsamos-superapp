import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/user_avatar.dart';

class _Conv {
  final String id;
  final String type;
  final String? name;
  final String? avatarUrl;
  _Conv({required this.id, required this.type, this.name, this.avatarUrl});
}

// Multi-select forward sheet — ports messages/TelegramForwardDialog.tsx.
class TelegramForwardDialog extends StatefulWidget {
  final List<String> messageIds;
  const TelegramForwardDialog({super.key, required this.messageIds});

  static Future<void> show(BuildContext context, {required List<String> messageIds}) {
    return showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AlsamosColors.of(context).card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
        builder: (_, sc) => TelegramForwardDialog(messageIds: messageIds),
      ),
    );
  }

  @override
  State<TelegramForwardDialog> createState() => _TelegramForwardDialogState();
}

class _TelegramForwardDialogState extends State<TelegramForwardDialog> {
  final _searchCtrl = TextEditingController();
  List<_Conv> _conversations = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _forwarding = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final supa = Supabase.instance.client;
    final uid = supa.auth.currentUser?.id;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final parts = await supa.from('conversation_participants').select('conversation_id').eq('user_id', uid).eq('is_archived', false);
      final ids = (parts as List).map((r) => r['conversation_id'] as String).toList();
      if (ids.isEmpty) { setState(() { _conversations = []; _loading = false; }); return; }
      final convs = await supa.from('conversations').select('*').inFilter('id', ids).order('last_message_at', ascending: false);
      final out = <_Conv>[];
      for (final c in (convs as List)) {
        String? name = c['name'] as String?;
        String? avatar = c['avatar_url'] as String?;
        if (c['type'] == 'private') {
          final others = await supa.from('conversation_participants').select('user_id').eq('conversation_id', c['id']).neq('user_id', uid).limit(1);
          if ((others as List).isNotEmpty) {
            final p = await supa.from('profiles').select('display_name, username, avatar_url').eq('id', others.first['user_id']).maybeSingle();
            if (p != null) { name = (p['display_name'] ?? p['username']) as String?; avatar = p['avatar_url'] as String?; }
          }
        }
        out.add(_Conv(id: c['id'], type: c['type'], name: name, avatarUrl: avatar));
      }
      if (mounted) setState(() { _conversations = out; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _forward() async {
    if (_selected.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _forwarding = true);
    final supa = Supabase.instance.client;
    final uid = supa.auth.currentUser?.id;
    try {
      for (final convId in _selected) {
        for (final mid in widget.messageIds) {
          await supa.from('messages').insert({'conversation_id': convId, 'sender_id': uid, 'content': '', 'forwarded_from_id': mid});
        }
      }
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Forwarded to ${_selected.length} chat(s)'))); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally { if (mounted) setState(() => _forwarding = false); }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final q = _searchCtrl.text.toLowerCase();
    final filtered = q.isEmpty ? _conversations : _conversations.where((c) => (c.name ?? '').toLowerCase().contains(q)).toList();

    return Column(children: [
      Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: colors.border, borderRadius: BorderRadius.circular(2))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
        Text('Forward to', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.foreground)),
        const Spacer(),
        if (_selected.isNotEmpty) Text('${_selected.length} selected', style: TextStyle(fontSize: 13, color: primary)),
      ])),
      Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 8), child: TextField(
        controller: _searchCtrl, onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Search chats...', prefixIcon: const Icon(LucideIcons.search, size: 18),
          filled: true, fillColor: colors.muted,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      )),
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : filtered.isEmpty
          ? Center(child: Text('No chats', style: TextStyle(color: colors.mutedForeground)))
          : ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final c = filtered[i];
                final sel = _selected.contains(c.id);
                final fallback = c.type == 'group' ? LucideIcons.users : (c.type == 'channel' ? LucideIcons.megaphone : null);
                return InkWell(
                  onTap: () { HapticFeedback.selectionClick(); setState(() { if (sel) {
                    _selected.remove(c.id);
                  } else {
                    _selected.add(c.id);
                  } }); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: sel ? primary.withValues(alpha: 0.08) : null,
                    child: Row(children: [
                      Container(width: 24, height: 24, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: sel ? primary : colors.border, width: 2), color: sel ? primary : null),
                        child: sel ? const Icon(LucideIcons.check, size: 14, color: Colors.white) : null),
                      const SizedBox(width: 12),
                      Container(width: 42, height: 42, decoration: BoxDecoration(shape: BoxShape.circle, color: fallback != null ? (c.type == 'group' ? const Color(0xFF3B82F6) : const Color(0xFF8B5CF6)) : null),
                        child: fallback != null ? Icon(fallback, color: Colors.white, size: 18) : UserAvatar(avatarUrl: c.avatarUrl, fallback: (c.name?.isNotEmpty ?? false) ? c.name![0].toUpperCase() : '?', size: 42, backgroundColor: primary)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(c.name ?? 'Unnamed', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: colors.foreground))),
                    ]),
                  ),
                );
              },
            )),
      if (_selected.isNotEmpty)
        SafeArea(child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: colors.card, border: Border(top: BorderSide(color: colors.border))),
          child: ElevatedButton.icon(
            onPressed: _forwarding ? null : _forward,
            icon: _forwarding ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(LucideIcons.send, size: 18),
            label: Text('Forward to ${_selected.length}'),
            style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        )),
    ]);
  }
}
