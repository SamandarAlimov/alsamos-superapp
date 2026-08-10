import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';

enum ChatType { private, group, channel, secret }
enum _Step { selectType, selectUsers, groupDetails }

class _Usr { final String id; final String? username; final String? displayName; final String? avatarUrl; final bool isOnline;
  _Usr({required this.id, this.username, this.displayName, this.avatarUrl, this.isOnline = false});
}

class CreateChatDialog extends StatefulWidget {
  final Future<dynamic> Function(String userId) onCreatePrivate;
  final Future<dynamic> Function(String name, List<String> memberIds) onCreateGroup;
  final Future<dynamic> Function(String name, String description)? onCreateChannel;
  const CreateChatDialog({super.key, required this.onCreatePrivate, required this.onCreateGroup, this.onCreateChannel});

  static Future<void> show(BuildContext context, {required Future<dynamic> Function(String) onCreatePrivate, required Future<dynamic> Function(String, List<String>) onCreateGroup, Future<dynamic> Function(String, String)? onCreateChannel}) {
    return showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AlsamosColors.of(context).card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
          child: CreateChatDialog(onCreatePrivate: onCreatePrivate, onCreateGroup: onCreateGroup, onCreateChannel: onCreateChannel),
        ),
      ),
    );
  }

  @override
  State<CreateChatDialog> createState() => _CreateChatDialogState();
}

class _CreateChatDialogState extends State<CreateChatDialog> {
  _Step _step = _Step.selectType;
  ChatType _type = ChatType.private;
  final _searchCtrl = TextEditingController();
  final _groupName = TextEditingController();
  final _groupDesc = TextEditingController();
  Timer? _searchDebounce;
  List<_Usr> _users = [];
  final Set<String> _selected = {};
  bool _loading = false;
  bool _creating = false;

  void _gotoGroupDetails() {
    HapticFeedback.lightImpact();
    setState(() {
      _step = _Step.groupDetails;
    });
  }

  void _toggleSelected(String userId) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(userId)) {
        _selected.remove(userId);
      } else {
        _selected.add(userId);
      }
    });
  }

  @override
  void initState() { super.initState(); }

  @override
  void dispose() { _searchDebounce?.cancel(); _searchCtrl.dispose(); _groupName.dispose(); _groupDesc.dispose(); super.dispose(); }

  Future<void> _fetchUsers() async {
    final supa = Supabase.instance.client;
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final q = _searchCtrl.text.trim();
      final base = supa.from('profiles').select('id, username, display_name, avatar_url, is_online').neq('id', uid);
      final filtered = q.isEmpty
          ? base
          : base.or('username.ilike.%$q%,display_name.ilike.%$q%');
      final rows = await filtered.limit(50);
      _users = (rows as List).map((r) => _Usr(id: r['id'], username: r['username'], displayName: r['display_name'], avatarUrl: r['avatar_url'], isOnline: r['is_online'] == true)).toList();
    } catch (_) { _users = []; }
    if (mounted) setState(() => _loading = false);
  }

  void _onSearch(String _) { _searchDebounce?.cancel(); _searchDebounce = Timer(const Duration(milliseconds: 250), _fetchUsers); }

  Future<void> _createPrivate(String userId) async {
    if (mounted) setState(() => _creating = true);
    try { await widget.onCreatePrivate(userId); if (mounted) Navigator.pop(context); }
    catch (e) { if (mounted) AppToast.error(context, friendlyError(e)); }
    finally { if (mounted) setState(() => _creating = false); }
  }

  Future<void> _createGroup() async {
    if (_groupName.text.trim().isEmpty || _selected.isEmpty) return;
    if (mounted) setState(() => _creating = true);
    try {
      if (_type == ChatType.channel && widget.onCreateChannel != null) {
        await widget.onCreateChannel!(_groupName.text.trim(), _groupDesc.text.trim());
      } else {
        await widget.onCreateGroup(_groupName.text.trim(), _selected.toList());
      }
      if (mounted) Navigator.pop(context);
    } catch (e) { if (mounted) AppToast.error(context, friendlyError(e)); }
    finally { if (mounted) setState(() => _creating = false); }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.all(16), child: Row(children: [
        if (_step != _Step.selectType)
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(LucideIcons.arrowLeft, size: 20), onPressed: () => setState(() => _step = _step == _Step.groupDetails ? _Step.selectUsers : _Step.selectType)),
        Expanded(child: Text(_step == _Step.selectType ? 'New chat' : (_step == _Step.selectUsers ? (_type == ChatType.private ? 'Select user' : 'Add members') : (_type == ChatType.channel ? 'New channel' : 'Group details')), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: colors.foreground))),
        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(LucideIcons.x, size: 20), onPressed: () => Navigator.pop(context)),
      ])),
      Divider(height: 1, color: colors.border),
      Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: _buildBody(colors, primary))),
      if (_step == _Step.selectUsers && _type != ChatType.private && _selected.isNotEmpty || _step == _Step.groupDetails)
        SafeArea(child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: colors.card, border: Border(top: BorderSide(color: colors.border))),
          child: ElevatedButton(
            onPressed: _creating
                ? null
                : (_step == _Step.selectUsers ? _gotoGroupDetails : _createGroup),
            style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: _creating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_step == _Step.selectUsers ? 'Next (${_selected.length})' : 'Create'),
          ),
        )),
    ]);
  }

  Widget _buildBody(AlsamosColors colors, Color primary) {
    if (_step == _Step.selectType) {
      return Column(children: [
        _typeRow(LucideIcons.user, 'Private chat', 'One-on-one conversation', primary, () { setState(() { _type = ChatType.private; _step = _Step.selectUsers; }); _fetchUsers(); }),
        _typeRow(LucideIcons.users, 'Group chat', 'Up to 200 people', const Color(0xFF3B82F6), () { setState(() { _type = ChatType.group; _step = _Step.selectUsers; }); _fetchUsers(); }),
        _typeRow(LucideIcons.megaphone, 'Channel', 'Broadcast to subscribers', const Color(0xFF8B5CF6), () { setState(() { _type = ChatType.channel; _step = _Step.selectUsers; }); _fetchUsers(); }),
        _typeRow(LucideIcons.lock, 'Secret chat', 'End-to-end encrypted', const Color(0xFFEF4444), () { setState(() { _type = ChatType.secret; _step = _Step.selectUsers; }); _fetchUsers(); }),
      ]);
    }
    if (_step == _Step.selectUsers) {
      return Column(children: [
        TextField(
          controller: _searchCtrl, onChanged: _onSearch,
          decoration: InputDecoration(hintText: 'Search users...', prefixIcon: const Icon(LucideIcons.search, size: 18), filled: true, fillColor: colors.muted, contentPadding: const EdgeInsets.symmetric(vertical: 8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
        ),
        const SizedBox(height: 12),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
        for (final u in _users)
          InkWell(
            onTap: _type == ChatType.private
                ? () => _createPrivate(u.id)
                : () => _toggleSelected(u.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                if (_type != ChatType.private) ...[
                  Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _selected.contains(u.id) ? primary : colors.border, width: 2), color: _selected.contains(u.id) ? primary : null), child: _selected.contains(u.id) ? const Icon(LucideIcons.check, size: 14, color: Colors.white) : null),
                  const SizedBox(width: 10),
                ],
                StoryAvatarRing(
                  userId: u.id,
                  avatarUrl: u.avatarUrl,
                  fallback: (u.displayName ?? u.username ?? '?')[0].toUpperCase(),
                  size: 40,
                  backgroundColor: primary,
                  showOnline: u.isOnline,
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u.displayName ?? u.username ?? 'Unknown', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.foreground)),
                  if (u.username != null) Text('@${u.username}', style: TextStyle(fontSize: 11.5, color: colors.mutedForeground)),
                ])),
              ]),
            ),
          ),
      ]);
    }
    // group details
    return Column(children: [
      TextField(controller: _groupName, decoration: InputDecoration(labelText: _type == ChatType.channel ? 'Channel name' : 'Group name', filled: true, fillColor: colors.muted, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      const SizedBox(height: 12),
      TextField(controller: _groupDesc, maxLines: 3, decoration: InputDecoration(labelText: 'Description (optional)', filled: true, fillColor: colors.muted, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      if (_type != ChatType.channel) Padding(padding: const EdgeInsets.only(top: 12), child: Text('${_selected.length} members selected', style: TextStyle(fontSize: 12, color: colors.mutedForeground))),
    ]);
  }

  Widget _typeRow(IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(LucideIcons.arrowRight, size: 18),
    );
  }
}
