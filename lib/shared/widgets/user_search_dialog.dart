import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app/theme/app_theme.dart';
import 'user_avatar.dart';
import 'verified_badge.dart';

/// 1:1 port of web `UserSearchDialog.tsx`.
/// Debounced user search with follow/unfollow toggle inline.
class UserSearchDialog {
  static Future<void> show(
    BuildContext context, {
    required Future<List<UserSearchResult>> Function(String query) onQuery,
    Future<bool> Function(String userId)? onFollow,
    Future<bool> Function(String userId)? onUnfollow,
  }) {
    return showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: _UserSearch(
          onQuery: onQuery,
          onFollow: onFollow,
          onUnfollow: onUnfollow,
        ),
      ),
    );
  }
}

class UserSearchResult {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool isVerified;
  final bool isFollowing;
  final String? bio;
  const UserSearchResult({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.isVerified = false,
    this.isFollowing = false,
    this.bio,
  });

  UserSearchResult copyWith({bool? isFollowing}) => UserSearchResult(
        id: id,
        username: username,
        displayName: displayName,
        avatarUrl: avatarUrl,
        isVerified: isVerified,
        isFollowing: isFollowing ?? this.isFollowing,
        bio: bio,
      );
}

class _UserSearch extends StatefulWidget {
  final Future<List<UserSearchResult>> Function(String) onQuery;
  final Future<bool> Function(String)? onFollow;
  final Future<bool> Function(String)? onUnfollow;
  const _UserSearch(
      {required this.onQuery, this.onFollow, this.onUnfollow});
  @override
  State<_UserSearch> createState() => _UserSearchState();
}

class _UserSearchState extends State<_UserSearch> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<UserSearchResult> _results = [];
  bool _loading = false;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _loading = true);
      try {
        final r = await widget.onQuery(v.trim());
        if (!mounted) return;
        setState(() {
          _results = r;
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _loading = false);
      }
    });
  }

  Future<void> _toggle(int i) async {
    final r = _results[i];
    final fut = r.isFollowing
        ? widget.onUnfollow?.call(r.id) ?? Future.value(false)
        : widget.onFollow?.call(r.id) ?? Future.value(false);
    final ok = await fut;
    if (ok && mounted) {
      setState(() => _results[i] = r.copyWith(isFollowing: !r.isFollowing));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Text('Foydalanuvchi qidirish',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _ctrl,
                onChanged: _onChanged,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Ism, @username yoki bio bo\'yicha...',
                  prefixIcon: Icon(LucideIcons.search,
                      size: 18, color: c.mutedForeground),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _ctrl.clear();
                            _onChanged('');
                          },
                        ),
                  filled: true,
                  fillColor: c.muted.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _query.isEmpty
                                    ? LucideIcons.users
                                    : LucideIcons.search,
                                size: 40,
                                color: c.mutedForeground,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _query.isEmpty
                                    ? 'Qidirish uchun yozing'
                                    : '"$_query" topilmadi',
                                style: TextStyle(color: c.mutedForeground),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _results.length,
                          itemBuilder: (_, i) {
                            final r = _results[i];
                            return InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/user/${r.username}');
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    UserAvatar(
                                      avatarUrl: r.avatarUrl,
                                      fallback: r.displayName.isNotEmpty
                                          ? r.displayName[0].toUpperCase()
                                          : '?',
                                      size: 44,
                                      userId: r.id,
                                      showOnline: true,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  r.displayName,
                                                  style: theme
                                                      .textTheme.bodyMedium
                                                      ?.copyWith(
                                                          fontWeight:
                                                              FontWeight
                                                                  .w600),
                                                  overflow: TextOverflow
                                                      .ellipsis,
                                                ),
                                              ),
                                              if (r.isVerified) ...[
                                                const SizedBox(width: 4),
                                                const VerifiedBadge(
                                                    size: 14),
                                              ],
                                            ],
                                          ),
                                          Text(
                                            '@${r.username}',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                    color:
                                                        c.mutedForeground),
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                          if (r.bio != null &&
                                              r.bio!.isNotEmpty)
                                            Text(
                                              r.bio!,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                      color: c
                                                          .mutedForeground),
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: () => _toggle(i),
                                      icon: Icon(
                                        r.isFollowing
                                            ? LucideIcons.userMinus
                                            : LucideIcons.userPlus,
                                        size: 14,
                                      ),
                                      label: Text(
                                        r.isFollowing
                                            ? 'Olib tashlash'
                                            : 'Kuzatish',
                                        style:
                                            const TextStyle(fontSize: 12),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: r.isFollowing
                                            ? c.mutedForeground
                                            : theme.colorScheme.primary,
                                        side: BorderSide(
                                          color: r.isFollowing
                                              ? c.border
                                              : theme.colorScheme.primary,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
