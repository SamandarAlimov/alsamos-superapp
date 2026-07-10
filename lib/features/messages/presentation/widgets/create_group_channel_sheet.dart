import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/conversation_model.dart';
import '../providers/conversations_provider.dart';

/// Telegram-style "New Group/Channel" creation flow
class CreateGroupChannelSheet extends ConsumerStatefulWidget {
  final bool isChannel;
  final void Function(Conversation created) onCreated;

  const CreateGroupChannelSheet({
    super.key,
    required this.isChannel,
    required this.onCreated,
  });

  static void show(
    BuildContext context, {
    required bool isChannel,
    required void Function(Conversation) onCreated,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateGroupChannelSheet(isChannel: isChannel, onCreated: onCreated),
    );
  }

  @override
  ConsumerState<CreateGroupChannelSheet> createState() => _CreateGroupChannelSheetState();
}

class _CreateGroupChannelSheetState extends ConsumerState<CreateGroupChannelSheet> {
  // Steps: 0 = name, 1 = members
  int _step = 0;

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  final List<Map<String, dynamic>> _selectedMembers = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _loading = false;
  bool _creating = false;
  bool _isPublic = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final userId = ref.read(authProvider).user?.id;
      final res = await Supabase.instance.client
          .from('profiles')
          .select('id, username, display_name, avatar_url, is_verified')
          .or('username.ilike.%$q%,display_name.ilike.%$q%')
          .limit(20);
      setState(() {
        _searchResults = (res as List)
            .where((p) => p['id'] != userId && !_selectedMembers.any((m) => m['id'] == p['id']))
            .cast<Map<String, dynamic>>()
            .toList();
      });
    } catch (_) {
    } finally {
      setState(() => _loading = false);
    }
  }

  void _toggleMember(Map<String, dynamic> p) {
    setState(() {
      final idx = _selectedMembers.indexWhere((m) => m['id'] == p['id']);
      if (idx >= 0) {
        _selectedMembers.removeAt(idx);
      } else {
        _selectedMembers.add(p);
      }
    });
  }

  bool _isMemberSelected(Map<String, dynamic> p) =>
      _selectedMembers.any((m) => m['id'] == p['id']);

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _creating = true);
    try {
      final userId = ref.read(authProvider).user?.id;
      if (userId == null) return;
      final sb = Supabase.instance.client;
      final type = widget.isChannel ? 'channel' : 'group';
      final name = _nameCtrl.text.trim();
      final desc = _descCtrl.text.trim();

      // Create conversation
      final payload = {
        'type': type,
        'title': name,
        'description': desc.isEmpty ? null : desc,
        'created_by': userId,
      };
      Map<String, dynamic> convRes;
      try {
        convRes = await sb.from('conversations').insert({
          ...payload,
          'is_public': _isPublic,
          'visibility': _isPublic ? 'public' : 'private',
        }).select().single();
      } catch (_) {
        convRes = await sb.from('conversations').insert(payload).select().single();
      }

      final convId = convRes['id'] as String;

      // Add creator as participant (admin)
      final participants = [
        {'conversation_id': convId, 'user_id': userId, 'role': 'admin'},
        ..._selectedMembers.map((m) => {
              'conversation_id': convId,
              'user_id': m['id'] as String,
              'role': 'member',
            }),
      ];
      await sb.from('conversation_participants').insert(participants);

      // Refresh conversations
      await ref.read(conversationsProvider.notifier).load();
      final convs = ref.read(conversationsProvider).valueOrNull ?? [];
      final created = convs.where((c) => c.id == convId).firstOrNull;

      if (created != null && mounted) {
        widget.onCreated(created);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Xatolik: $e'), backgroundColor: Colors.red.shade600));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);

    return Container(
      height: mq.size.height * 0.92,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        // Handle bar
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          width: 36,
          height: 4,
          decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
        ),

        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(children: [
            if (_step == 1)
              IconButton(
                icon: const Icon(LucideIcons.arrowLeft, size: 20),
                onPressed: () => setState(() => _step = 0),
              ),
            Icon(
              widget.isChannel ? LucideIcons.megaphone : LucideIcons.users,
              color: theme.colorScheme.primary,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _step == 0
                    ? (widget.isChannel ? 'Yangi kanal' : 'Yangi guruh')
                    : 'A\'zolar qo\'shish',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.x),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),

        Divider(color: c.border, height: 1),

        // Step 0: Name & description
        if (_step == 0) ...[
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Avatar circle placeholder
                Center(
                  child: Stack(
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.isChannel ? LucideIcons.megaphone : LucideIcons.users,
                          color: theme.colorScheme.primary,
                          size: 40,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(LucideIcons.camera, size: 14, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                Text(
                  widget.isChannel ? 'Kanal nomi' : 'Guruh nomi',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  autofocus: true,
                  maxLength: 50,
                  decoration: InputDecoration(
                    hintText: widget.isChannel ? 'Masalan: Yangiliklar' : 'Masalan: Do\'stlar',
                    filled: true,
                    fillColor: c.muted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    counterStyle: TextStyle(color: c.mutedForeground, fontSize: 11),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 20),

                Text(
                  'Tavsif (ixtiyoriy)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descCtrl,
                  maxLines: 3,
                  maxLength: 255,
                  decoration: InputDecoration(
                    hintText: widget.isChannel
                        ? 'Bu kanal haqida qisqacha...'
                        : 'Guruh haqida qisqacha...',
                    filled: true,
                    fillColor: c.muted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    counterStyle: TextStyle(color: c.mutedForeground, fontSize: 11),
                  ),
                ),

                if (widget.isChannel) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(children: [
                      Icon(LucideIcons.info, color: theme.colorScheme.primary, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Kanallar ommaviy xabarlarni tarqatish uchun ishlatiladi. A\'zolar faqat o\'qiy oladi.',
                          style: TextStyle(fontSize: 13, color: c.mutedForeground, height: 1.4),
                        ),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.muted.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.border.withValues(alpha: 0.6)),
                  ),
                  child: Row(children: [
                    Icon(_isPublic ? LucideIcons.globe2 : LucideIcons.lock,
                        color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_isPublic ? 'Public' : 'Private',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        _isPublic
                            ? 'Postlar Home va Discover feedlarda ko\'rinishi mumkin'
                            : 'Faqat a\'zolar Messages ichida ko\'radi',
                        style: TextStyle(fontSize: 12, color: c.mutedForeground),
                      ),
                    ])),
                    Switch.adaptive(
                      value: _isPublic,
                      onChanged: (v) => setState(() => _isPublic = v),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, mq.viewInsets.bottom + 20),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _nameCtrl.text.trim().isEmpty
                    ? null
                    : () => setState(() => _step = 1),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Keyingi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  const Icon(LucideIcons.arrowRight, size: 18),
                ]),
              ),
            ),
          ),
        ],

        // Step 1: Add members
        if (_step == 1) ...[
          // Selected members chips
          if (_selectedMembers.isNotEmpty)
            SizedBox(
              height: 70,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                itemCount: _selectedMembers.length,
                itemBuilder: (_, i) {
                  final m = _selectedMembers[i];
                  final name = m['display_name'] as String? ?? m['username'] as String? ?? 'U';
                  final avatar = m['avatar_url'] as String?;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Stack(children: [
                        avatar != null
                            ? CircleAvatar(radius: 20, backgroundImage: NetworkImage(avatar))
                            : CircleAvatar(
                                radius: 20,
                                backgroundColor: theme.colorScheme.primary,
                                child: Text(name[0].toUpperCase(),
                                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                              ),
                        Positioned(
                          right: -2,
                          top: -2,
                          child: GestureDetector(
                            onTap: () => _toggleMember(m),
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                  color: Colors.red, shape: BoxShape.circle),
                              child: const Icon(LucideIcons.x, size: 11, color: Colors.white),
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 2),
                      Text(name.split(' ').first,
                          style: TextStyle(fontSize: 10, color: c.mutedForeground),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  );
                },
              ),
            ),

          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: 'Foydalanuvchi qidiring...',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                filled: true,
                fillColor: c.muted,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          Divider(color: c.border, height: 1),

          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                : _searchResults.isEmpty && _searchCtrl.text.length >= 2
                    ? Center(
                        child: Text('Topilmadi', style: TextStyle(color: c.mutedForeground)))
                    : _searchCtrl.text.isEmpty
                        ? Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(LucideIcons.search, size: 40, color: c.mutedForeground),
                              const SizedBox(height: 12),
                              Text('A\'zo qidiring',
                                  style: TextStyle(color: c.mutedForeground, fontSize: 15)),
                            ]),
                          )
                        : ListView.builder(
                            itemCount: _searchResults.length,
                            itemBuilder: (_, i) {
                              final p = _searchResults[i];
                              final name = p['display_name'] as String? ??
                                  p['username'] as String? ??
                                  'Unknown';
                              final avatar = p['avatar_url'] as String?;
                              final selected = _isMemberSelected(p);
                              return ListTile(
                                leading: avatar != null
                                    ? CircleAvatar(backgroundImage: NetworkImage(avatar))
                                    : CircleAvatar(
                                        backgroundColor: theme.colorScheme.primary,
                                        child: Text(name[0].toUpperCase(),
                                            style: const TextStyle(color: Colors.white))),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: p['username'] != null
                                    ? Text('@${p['username']}',
                                        style: TextStyle(color: c.mutedForeground, fontSize: 12))
                                    : null,
                                trailing: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: selected ? theme.colorScheme.primary : Colors.transparent,
                                    border: selected
                                        ? null
                                        : Border.all(color: c.border, width: 2),
                                  ),
                                  child: selected
                                      ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
                                      : null,
                                ),
                                onTap: () => _toggleMember(p),
                              );
                            },
                          ),
          ),

          // Create button
          Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, mq.viewInsets.bottom + 20),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _nameCtrl.text.trim().isEmpty || _creating ? null : _create,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _creating
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        widget.isChannel ? 'Kanal yaratish' : 'Guruh yaratish',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
