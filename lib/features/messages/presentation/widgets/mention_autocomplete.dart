import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../../../shared/widgets/verified_badge.dart';

class MentionUser {
  final String id; final String? username; final String? displayName; final String? avatarUrl; final bool isVerified;
  MentionUser({required this.id, this.username, this.displayName, this.avatarUrl, this.isVerified = false});
}

/// Ports `src/components/MentionAutocomplete.tsx` — @-mention picker over profiles.
class MentionAutocomplete extends StatefulWidget {
  const MentionAutocomplete({super.key, required this.query, required this.onSelect, this.maxResults = 6});
  final String query;
  final ValueChanged<String> onSelect; // passes username
  final int maxResults;

  @override
  State<MentionAutocomplete> createState() => _MentionAutocompleteState();
}

class _MentionAutocompleteState extends State<MentionAutocomplete> {
  final _client = Supabase.instance.client;
  Timer? _debounce;
  bool _loading = false;
  List<MentionUser> _users = [];

  @override
  void didUpdateWidget(covariant MentionAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) _schedule();
  }

  @override
  void initState() { super.initState(); _schedule(); }
  @override
  void dispose() { _debounce?.cancel(); super.dispose(); }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _fetch);
  }

  Future<void> _fetch() async {
    final q = widget.query.trim();
    if (q.isEmpty) { setState(() => _users = []); return; }
    if (mounted) setState(() => _loading = true);
    try {
      final rows = await _client.from('profiles')
          .select('id, username, display_name, avatar_url, is_verified')
          .or('username.ilike.%$q%,display_name.ilike.%$q%')
          .limit(widget.maxResults);
      _users = (rows as List).map((r) => MentionUser(
        id: r['id'] as String,
        username: r['username'] as String?,
        displayName: r['display_name'] as String?,
        avatarUrl: r['avatar_url'] as String?,
        isVerified: r['is_verified'] as bool? ?? false,
      )).toList();
    } catch (_) { _users = []; }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    if (widget.query.isEmpty || (_users.isEmpty && !_loading)) return const SizedBox.shrink();
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      color: c.card,
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 320, maxHeight: 280),
        decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(10)),
        child: _loading
            ? const Padding(padding: EdgeInsets.all(14), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
            : ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _users.length,
                itemBuilder: (_, i) {
                  final u = _users[i];
                  return InkWell(
                    onTap: () { if (u.username != null) widget.onSelect(u.username!); },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(children: [
                        StoryAvatarRing(
                          userId: u.id,
                          avatarUrl: u.avatarUrl,
                          fallback: (u.displayName ?? u.username ?? 'U')[0].toUpperCase(),
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text(u.displayName ?? u.username ?? 'User', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                              if (u.isVerified) const Padding(padding: EdgeInsets.only(left: 4), child: VerifiedBadge(size: 12)),
                            ]),
                            if (u.username != null) Text('@${u.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.mutedForeground)),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
