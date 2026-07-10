import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../shared/widgets/user_avatar.dart';

class _Convo {
  final String id;
  final String type;
  final String? name;
  final String? avatarUrl;
  final String? otherDisplay;
  final String? otherUsername;
  _Convo({required this.id, required this.type, this.name, this.avatarUrl, this.otherDisplay, this.otherUsername});
  String label() => type == 'group' ? (name ?? 'Group chat') : (otherDisplay ?? otherUsername ?? 'User');
  IconData fallbackIcon() => type == 'channel' ? LucideIcons.megaphone : (type == 'group' ? LucideIcons.users : LucideIcons.user);
}

/// Ports `src/components/ForwardMessageDialog.tsx`.
class ForwardMessageDialog extends ConsumerStatefulWidget {
  const ForwardMessageDialog({super.key, required this.messageId, required this.messageContent});
  final String messageId;
  final String messageContent;

  static Future<void> show(BuildContext context, {required String messageId, required String messageContent}) =>
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, __) => ForwardMessageDialog(messageId: messageId, messageContent: messageContent),
        ),
      );

  @override
  ConsumerState<ForwardMessageDialog> createState() => _FwdState();
}

class _FwdState extends ConsumerState<ForwardMessageDialog> {
  final _client = Supabase.instance.client;
  final _search = TextEditingController();
  List<_Convo> _convos = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _forwarding = false;

  void _toggleConvo(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  @override
  void initState() { super.initState(); _fetch(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _fetch() async {
    final String? meId = ref.read(authProvider).user?.id;
    if (meId == null) { setState(() => _loading = false); return; }
    final String me = meId;
    try {
      final parts = await _client.from('conversation_participants').select('conversation_id').eq('user_id', me);// ignore: dead_code
      final ids = (parts as List).map((p) => p['conversation_id']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
      if (ids.isEmpty) { setState(() => _loading = false); return; }
      final convos = await _client.from('conversations').select('id, type, name, avatar_url, last_message_at').inFilter('id', ids).order('last_message_at', ascending: false);
      final list = <_Convo>[];
      for (final cv in (convos as List).cast<Map<String, dynamic>>()) {
        String? oDisplay, oUsername;
        if (cv['type'] == 'private') {
          final p = await _client.from('conversation_participants').select('user_id').eq('conversation_id', cv['id'] as String).neq('user_id', me).limit(1);// non-null me
          if ((p as List).isNotEmpty) {
            final pr = await _client.from('profiles').select('display_name, username, avatar_url').eq('id', (p.first['user_id']?.toString() ?? '')).maybeSingle();
            if (pr != null) { oDisplay = pr['display_name'] as String?; oUsername = pr['username'] as String?; }
          }
        }
        list.add(_Convo(id: cv['id'] as String, type: cv['type'] as String? ?? 'private', name: cv['name'] as String?, avatarUrl: cv['avatar_url'] as String?, otherDisplay: oDisplay, otherUsername: oUsername));
      }
      if (!mounted) return;
      setState(() { _convos = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forward() async {
    if (_selected.isEmpty || _forwarding) return;
    final me = ref.read(authProvider).user?.id;
    if (me == null) return;
    if (mounted) setState(() => _forwarding = true);
    try {
      final inserts = _selected.map((id) => {
            'conversation_id': id,
            'sender_id': me,
            'content': widget.messageContent,
            'forwarded_from_message_id': widget.messageId,
          }).toList();
      await _client.from('messages').insert(inserts);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Forwarded to ${_selected.length} chat${_selected.length == 1 ? '' : 's'}')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to forward')));
    } finally {
      if (mounted) setState(() => _forwarding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final q = _search.text.toLowerCase().trim();
    final shown = q.isEmpty ? _convos : _convos.where((cv) => cv.label().toLowerCase().contains(q)).toList();
    return Container(
      decoration: BoxDecoration(color: c.card, borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), border: Border.all(color: c.border)),
      child: Column(children: [
        Container(margin: const EdgeInsets.symmetric(vertical: 10), width: 40, height: 4, decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2))),
        const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 8), child: Row(children: [Icon(LucideIcons.send, size: 18), SizedBox(width: 8), Text('Forward to', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))])),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search\u2026',
              isDense: true,
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              filled: true,
              fillColor: c.muted.withValues(alpha: 0.4),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
              : shown.isEmpty
                  ? Center(child: Text('No conversations', style: TextStyle(color: c.mutedForeground)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: shown.length,
                      itemBuilder: (ctx, i) {
                        final cv = shown[i];
                        final sel = _selected.contains(cv.id);
                        return InkWell(
                          onTap: () => _toggleConvo(cv.id),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            child: Row(children: [
                              Checkbox(value: sel, onChanged: (v) => _toggleConvo(cv.id)),
                              UserAvatar(avatarUrl: cv.avatarUrl, fallback: cv.label()[0].toUpperCase(), size: 38),
                              const SizedBox(width: 10),
                              Expanded(child: Text(cv.label(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                              if (cv.type == 'channel') Icon(LucideIcons.megaphone, size: 14, color: c.mutedForeground)
                              else if (cv.type == 'group') Icon(LucideIcons.users, size: 14, color: c.mutedForeground),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _selected.isEmpty || _forwarding ? null : _forward,
                  icon: _forwarding ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(LucideIcons.send, size: 16),
                  label: Text('Forward${_selected.isEmpty ? '' : ' (${_selected.length})'}'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
