import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/app_colors.dart';
import 'user_avatar.dart';

/// 1:1 port of web `SharePostDialog.tsx`.
/// Tabs: Conversations (in-app share) | External (copy/Twitter/Facebook/WhatsApp/Email).
class SharePostDialog {
  static Future<void> show(
    BuildContext context, {
    required String postId,
    String? postContent,
    List<ShareConversation> conversations = const [],
    void Function(List<String> conversationIds, String? message)? onSendToChats,
    void Function(String channel)? onExternalShare,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(
        postId: postId,
        postContent: postContent,
        conversations: conversations,
        onSendToChats: onSendToChats,
        onExternalShare: onExternalShare,
      ),
    );
  }
}

class ShareConversation {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? subtitle;
  const ShareConversation({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.subtitle,
  });
}

class _ShareSheet extends StatefulWidget {
  final String postId;
  final String? postContent;
  final List<ShareConversation> conversations;
  final void Function(List<String>, String?)? onSendToChats;
  final void Function(String)? onExternalShare;
  const _ShareSheet({
    required this.postId,
    this.postContent,
    required this.conversations,
    this.onSendToChats,
    this.onExternalShare,
  });
  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  String _query = '';
  final Set<String> _selected = {};
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  String get _shareUrl => 'https://alsamos.app/post/${widget.postId}';

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: c.mutedForeground.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
              child: Row(
                children: [
                  Text(
                    'Ulashish',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              labelColor: theme.colorScheme.primary,
              indicatorColor: theme.colorScheme.primary,
              unselectedLabelColor: c.mutedForeground,
              tabs: const [
                Tab(text: 'Suhbat'),
                Tab(text: 'Tashqi'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _conversationsTab(scroll),
                  _externalTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conversationsTab(ScrollController scroll) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    final filtered = widget.conversations.where((v) {
      if (_query.isEmpty) return true;
      return v.name.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Suhbat qidirish...',
              prefixIcon:
                  Icon(LucideIcons.search, size: 18, color: c.mutedForeground),
              filled: true,
              fillColor: c.muted.withValues(alpha: 0.4),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _query.isEmpty
                        ? 'Suhbat yo\'q'
                        : '"$_query" topilmadi',
                    style: TextStyle(color: c.mutedForeground),
                  ),
                )
              : ListView.builder(
                  controller: scroll,
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final conv = filtered[i];
                    final isSelected = _selected.contains(conv.id);
                    return InkWell(
                      onTap: () => setState(() {
                        if (isSelected) {
                          _selected.remove(conv.id);
                        } else {
                          _selected.add(conv.id);
                        }
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Checkbox(
                              value: isSelected,
                              onChanged: (_) => setState(() {
                                if (isSelected) {
                                  _selected.remove(conv.id);
                                } else {
                                  _selected.add(conv.id);
                                }
                              }),
                              activeColor: theme.colorScheme.primary,
                            ),
                            UserAvatar(
                              avatarUrl: conv.avatarUrl,
                              fallback: conv.name.isNotEmpty
                                  ? conv.name[0].toUpperCase()
                                  : '?',
                              size: 40,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    conv.name,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (conv.subtitle != null)
                                    Text(
                                      conv.subtitle!,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: c.mutedForeground),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_selected.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _msgCtrl,
              decoration: InputDecoration(
                hintText: 'Xabar qo\'shish (ixtiyoriy)...',
                filled: true,
                fillColor: c.muted.withValues(alpha: 0.4),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(LucideIcons.send, size: 18),
                label: Text('${_selected.length} ta suhbatga yuborish'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  widget.onSendToChats
                      ?.call(_selected.toList(), _msgCtrl.text.trim());
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Yuborildi: ${_selected.length} ta suhbat')),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _externalTab() {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);

    final channels = [
      _ExtChannel('copy', _copied ? LucideIcons.check : LucideIcons.copy,
          _copied ? 'Nusxalandi' : 'Havolani nusxalash', _copied ? Colors.green : null),
      _ExtChannel('twitter', Icons.alternate_email, 'Twitter', const Color(0xFF1DA1F2)),
      _ExtChannel('facebook', Icons.facebook, 'Facebook', const Color(0xFF1877F2)),
      _ExtChannel('whatsapp', LucideIcons.messageCircle, 'WhatsApp', const Color(0xFF25D366)),
      _ExtChannel('email', LucideIcons.mail, 'Email', null),
      _ExtChannel('link', LucideIcons.link2, 'Boshqa...', null),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // url preview
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.link2, size: 16, color: c.mutedForeground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _shareUrl,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // grid of channels
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: channels.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (_, i) {
              final ch = channels[i];
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  if (ch.id == 'copy') {
                    await Clipboard.setData(ClipboardData(text: _shareUrl));
                    setState(() => _copied = true);
                    Future.delayed(const Duration(seconds: 2),
                        () => mounted ? setState(() => _copied = false) : null);
                  } else {
                    widget.onExternalShare?.call(ch.id);
                    if (mounted) Navigator.pop(context);
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: c.muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(ch.icon, size: 28, color: ch.color ?? theme.colorScheme.primary),
                      const SizedBox(height: 8),
                      Text(
                        ch.label,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.alsamosOrange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.alsamosOrange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.info,
                    size: 16, color: AppColors.alsamosOrange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Havola Alsamos hisobsiz ham ochiladi',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.alsamosOrange),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtChannel {
  final String id;
  final IconData icon;
  final String label;
  final Color? color;
  const _ExtChannel(this.id, this.icon, this.label, this.color);
}
