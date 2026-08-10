import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../app/theme/app_theme.dart';
import 'mention_engine.dart';

class MentionAutocompleteWidget extends ConsumerStatefulWidget {
  final String query;
  final String? conversationId;
  final ValueChanged<MentionUser> onSelect;
  final VoidCallback? onClose;
  final double? maxHeight;

  const MentionAutocompleteWidget({
    super.key,
    required this.query,
    required this.onSelect,
    this.conversationId,
    this.onClose,
    this.maxHeight = 240,
  });

  @override
  ConsumerState<MentionAutocompleteWidget> createState() =>
      _MentionAutocompleteWidgetState();
}

class _MentionAutocompleteWidgetState
    extends ConsumerState<MentionAutocompleteWidget> {
  List<MentionUser> _users = const [];
  bool _loading = false;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _fetch(widget.query);
  }

  @override
  void didUpdateWidget(covariant MentionAutocompleteWidget old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _fetch(widget.query);
  }

  Future<void> _fetch(String q) async {
    setState(() => _loading = true);
    final engine = ref.read(mentionEngineProvider);
    final results = await engine.search(q, conversationId: widget.conversationId);
    if (!mounted) return;
    setState(() {
      _users = results;
      _selected = 0;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _users.isEmpty) return const SizedBox.shrink();
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: widget.maxHeight ?? 240),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _users.length,
              itemBuilder: (_, i) {
                final user = _users[i];
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _selected = i),
                  child: GestureDetector(
                    onTap: () => widget.onSelect(user),
                    child: Container(
                      color: i == _selected
                          ? c.accent.withValues(alpha: 0.15)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundImage: user.avatarUrl != null
                              ? NetworkImage(user.avatarUrl!)
                              : null,
                          backgroundColor: c.muted,
                          child: user.avatarUrl == null
                              ? Text(
                                  (user.displayName ?? user.username ?? 'U')
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: TextStyle(
                                      fontSize: 11, color: c.foreground),
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(children: [
                                Flexible(
                                  child: Text(
                                    user.displayName ?? user.username ?? '',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (user.isVerified) ...[
                                  const SizedBox(width: 4),
                                  Icon(LucideIcons.badgeCheck,
                                      size: 12, color: c.primary),
                                ],
                              ]),
                              if (user.username != null)
                                Text(
                                  '@${user.username}',
                                  style: TextStyle(
                                      fontSize: 11, color: c.mutedForeground),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
