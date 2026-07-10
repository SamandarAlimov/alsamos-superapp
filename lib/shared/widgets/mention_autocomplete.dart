// v32: MentionAutocomplete overlay — port of web `MentionAutocomplete.tsx` (165L).
// `profiles` jadval `username`/`display_name` ilike orqali qidiriladi.
// Compose maydoni ostida overlay sifatida ko'rsatiladi (chat + post compose).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/theme/app_theme.dart';
import 'user_avatar.dart';
import 'verified_badge.dart';

class MentionSuggestion {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final bool isVerified;
  const MentionSuggestion({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.isVerified = false,
  });
}

class MentionAutocomplete extends StatefulWidget {
  final String query;
  final ValueChanged<String> onSelect;
  final VoidCallback onClose;
  final double? top;
  final double? left;
  final double? right;
  final double? maxWidth;
  const MentionAutocomplete({
    super.key,
    required this.query,
    required this.onSelect,
    required this.onClose,
    this.top,
    this.left,
    this.right,
    this.maxWidth = 280,
  });

  @override
  State<MentionAutocomplete> createState() => _MentionAutocompleteState();
}

class _MentionAutocompleteState extends State<MentionAutocomplete> {
  List<MentionSuggestion> _users = const [];
  bool _loading = false;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _fetch(widget.query);
  }

  @override
  void didUpdateWidget(covariant MentionAutocomplete old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _fetch(widget.query);
  }

  Future<void> _fetch(String q) async {
    if (q.isEmpty) {
      setState(() => _users = const []);
      return;
    }
    setState(() => _loading = true);
    try {
      final esc = q.replaceAll('%', '');
      final res = await Supabase.instance.client
          .from('profiles')
          .select('id, username, display_name, avatar_url, is_verified')
          .or('username.ilike.%$esc%,display_name.ilike.%$esc%')
          .limit(6);
      final list = (res as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .map((m) => MentionSuggestion(
                id: m['id'] as String,
                username: m['username'] as String?,
                displayName: m['display_name'] as String?,
                avatarUrl: m['avatar_url'] as String?,
                isVerified: (m['is_verified'] as bool?) ?? false,
              ))
          .toList();
      if (!mounted) return;
      setState(() {
        _users = list;
        _selected = 0;
      });
    } catch (_) {
      if (mounted) setState(() => _users = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _initialOf(MentionSuggestion u) {
    final base = u.displayName ?? u.username ?? 'U';
    return base.isEmpty ? 'U' : base[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.query.isEmpty) return const SizedBox.shrink();
    if (!_loading && _users.isEmpty) return const SizedBox.shrink();
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return Positioned(
      top: widget.top,
      left: widget.left,
      right: widget.right,
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: widget.maxWidth ?? 280, minWidth: 200),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < _users.length; i++)
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => _selected = i),
                        child: GestureDetector(
                          onTap: () {
                            final u = _users[i].username;
                            if (u != null) widget.onSelect(u);
                          },
                          child: Container(
                            color: i == _selected
                                ? c.accent.withValues(alpha: 0.15)
                                : Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(children: [
                              UserAvatar(
                                avatarUrl: _users[i].avatarUrl,
                                fallback: _initialOf(_users[i]),
                                size: 28,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(children: [
                                      Flexible(
                                        child: Text(
                                          _users[i].displayName ??
                                              _users[i].username ??
                                              '',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (_users[i].isVerified) ...[
                                        const SizedBox(width: 4),
                                        const VerifiedBadge(size: 12),
                                      ],
                                    ]),
                                    if (_users[i].username != null)
                                      Text('@${_users[i].username}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: c.mutedForeground),
                                          overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
