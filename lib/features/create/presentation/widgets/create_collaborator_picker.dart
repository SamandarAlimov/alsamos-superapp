import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../data/models/create_collaborator.dart';

typedef CreateCollaboratorSearch = Future<List<CreateCollaborator>> Function(
  String query,
);

typedef CreateCollaboratorError = void Function(Object error);

Future<CreateCollaborator?> showCreateCollaboratorPicker({
  required BuildContext context,
  required CreateCollaboratorSearch onSearch,
  required CreateCollaboratorError onError,
}) {
  return showModalBottomSheet<CreateCollaborator>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _CreateCollaboratorPickerSheet(
      onSearch: onSearch,
      onError: onError,
    ),
  );
}

class CreateCollaboratorsSection extends StatelessWidget {
  const CreateCollaboratorsSection({
    super.key,
    required this.collaborators,
    required this.onAdd,
    required this.onRemove,
  });

  final List<CreateCollaborator> collaborators;
  final VoidCallback onAdd;
  final ValueChanged<CreateCollaborator> onRemove;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.users, size: 18, color: c.mutedForeground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Hamkorlar',
                  style: TextStyle(
                    color: c.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(LucideIcons.plus, size: 15),
                label: const Text('Qo\'shish'),
              ),
            ],
          ),
          if (collaborators.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: collaborators
                  .map(
                    (user) => InputChip(
                      avatar: StoryAvatarRing(
                        userId: user.id,
                        avatarUrl: user.avatarUrl,
                        fallback: _fallbackFor(user),
                        size: 22,
                      ),
                      label: Text(
                        '@${user.username}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onDeleted: () => onRemove(user),
                      deleteIcon: const Icon(LucideIcons.x, size: 13),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _CreateCollaboratorPickerSheet extends StatefulWidget {
  const _CreateCollaboratorPickerSheet({
    required this.onSearch,
    required this.onError,
  });

  final CreateCollaboratorSearch onSearch;
  final CreateCollaboratorError onError;

  @override
  State<_CreateCollaboratorPickerSheet> createState() =>
      _CreateCollaboratorPickerSheetState();
}

class _CreateCollaboratorPickerSheetState
    extends State<_CreateCollaboratorPickerSheet> {
  final _search = TextEditingController();
  var _loading = false;
  var _results = <CreateCollaborator>[];
  var _requestId = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    final requestId = ++_requestId;
    final q = query.trim().replaceFirst(RegExp(r'^@'), '');
    if (q.length < 2) {
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);
    try {
      final users = await widget.onSearch(q);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = users;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _loading = false);
      widget.onError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          top: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 14,
        ),
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.users,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hamkor qo\'shish',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.foreground,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(LucideIcons.x),
                ),
              ],
            ),
            TextField(
              key: const Key('create-collaborator-search-field'),
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(LucideIcons.search, size: 16),
                hintText: 'Username yoki ism...',
                filled: true,
                fillColor: c.muted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _searchUsers,
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: c.border),
                  itemBuilder: (_, index) {
                    final user = _results[index];
                    return Material(
                      color: Colors.transparent,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: StoryAvatarRing(
                          userId: user.id,
                          avatarUrl: user.avatarUrl,
                          fallback: _fallbackFor(user),
                          size: 36,
                        ),
                        title: Text(user.displayName),
                        subtitle: Text('@${user.username}'),
                        trailing: const Icon(LucideIcons.plus, size: 18),
                        onTap: () => Navigator.pop(context, user),
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

String _fallbackFor(CreateCollaborator user) =>
    user.displayName.isEmpty ? 'U' : user.displayName[0].toUpperCase();
