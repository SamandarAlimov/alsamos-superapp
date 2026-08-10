import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../data/models/conversation_admin_model.dart';
import '../providers/conversations_provider.dart';
import '../providers/conversation_admin_provider.dart';
import '../../../../shared/widgets/app_toast.dart';

class ConversationAdminPanel extends ConsumerStatefulWidget {
  const ConversationAdminPanel({
    super.key,
    required this.conversationId,
    required this.title,
  });

  final String conversationId;
  final String title;

  static Future<void> show(
    BuildContext context, {
    required String conversationId,
    required String title,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ConversationAdminPanel(
        conversationId: conversationId,
        title: title,
      ),
    );
  }

  @override
  ConsumerState<ConversationAdminPanel> createState() =>
      _ConversationAdminPanelState();
}

class _ConversationAdminPanelState
    extends ConsumerState<ConversationAdminPanel> {
  final _memberSearch = TextEditingController();
  int _slowModeSeconds = 0;

  @override
  void dispose() {
    _memberSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final members =
        ref.watch(conversationMembersProvider(widget.conversationId));
    final stats = ref.watch(conversationStatsProvider(widget.conversationId));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      maxChildSize: 0.96,
      minChildSize: 0.45,
      builder: (context, controller) => DefaultTabController(
        length: 6,
        child: Column(
          children: [
            ListTile(
              title: Text(widget.title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Guruh/Kanal boshqaruvi'),
              trailing: IconButton(
                icon: const Icon(LucideIcons.x),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'A’zolar'),
                Tab(text: 'Cheklovlar'),
                Tab(text: 'Slow mode'),
                Tab(text: 'Statistika'),
                Tab(text: 'Log/Report'),
                Tab(text: 'Ulanishlar'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _membersTab(controller, members),
                  _restrictionsTab(controller),
                  _slowModeTab(),
                  _statsTab(stats),
                  _logAndReportsTab(controller),
                  _linkGroupTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _membersTab(
    ScrollController controller,
    AsyncValue<List<ConversationMember>> members,
  ) {
    final query = _memberSearch.text.toLowerCase();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _memberSearch,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(LucideIcons.search),
              hintText: 'A’zolarni qidirish',
            ),
          ),
        ),
        Expanded(
          child: members.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(e.toString())),
            data: (items) {
              final filtered = query.isEmpty
                  ? items
                  : items.where((m) => m.title.toLowerCase().contains(query));
              return ListView(
                controller: controller,
                children: [
                  for (final member in filtered)
                    ListTile(
                      leading:
                          const CircleAvatar(child: Icon(LucideIcons.user)),
                      title: Text(member.title),
                      subtitle: Text(member.role),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) =>
                            _applyMemberAction(member.userId, value),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'restrict', child: Text('Restrict')),
                          PopupMenuItem(value: 'ban', child: Text('Ban')),
                          PopupMenuItem(
                              value: 'unrestrict', child: Text('Unrestrict')),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _restrictionsTab(ScrollController controller) {
    final restrictions =
        ref.watch(conversationRestrictionsProvider(widget.conversationId));
    return restrictions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (items) => ListView(
        controller: controller,
        children: [
          for (final item in items)
            ListTile(
              leading: Icon(item.kind == 'ban'
                  ? LucideIcons.ban
                  : LucideIcons.userRoundMinus),
              title: Text('${item.kind}: ${item.userId}'),
              subtitle: Text(item.until?.toLocal().toString() ?? 'doimiy'),
              trailing: IconButton(
                icon: const Icon(LucideIcons.x),
                onPressed: () => _removeRestriction(item.userId, item.kind),
              ),
            ),
        ],
      ),
    );
  }

  Widget _slowModeTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Xabar yuborish oralig‘i'),
          Slider(
            min: 0,
            max: 300,
            divisions: 10,
            label: _slowModeSeconds == 0 ? 'O‘chiq' : '$_slowModeSeconds s',
            value: _slowModeSeconds.toDouble(),
            onChanged: (value) =>
                setState(() => _slowModeSeconds = value.round()),
          ),
          FilledButton.icon(
            onPressed: () async {
              await ref
                  .read(conversationAdminRepositoryProvider)
                  .setSlowMode(widget.conversationId, _slowModeSeconds);
              if (mounted) {
                AppToast.success(context, "Slow mode saqlandi");
              }
            },
            icon: const Icon(LucideIcons.timer),
            label: const Text('Saqlash'),
          ),
        ],
      ),
    );
  }

  Widget _statsTab(AsyncValue stats) {
    return stats.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (s) => GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        childAspectRatio: 1.6,
        children: [
          _stat('A’zolar', s.members),
          _stat('Xabarlar', s.messages),
          _stat('Ko‘rishlar', s.views),
          _stat('7 kun o‘sish', s.growth7d),
          _stat('Reportlar', s.reports),
        ],
      ),
    );
  }

  Widget _logAndReportsTab(ScrollController controller) {
    final log = ref.watch(conversationAdminLogProvider(widget.conversationId));
    final reports =
        ref.watch(conversationReportsProvider(widget.conversationId));
    return ListView(
      controller: controller,
      children: [
        const ListTile(title: Text('Admin log')),
        log.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ListTile(title: Text(e.toString())),
          data: (items) => Column(
            children: [
              for (final item in items.take(20))
                ListTile(
                  dense: true,
                  leading: const Icon(LucideIcons.history),
                  title: Text(item.action),
                  subtitle: Text(item.createdAt?.toLocal().toString() ?? ''),
                ),
            ],
          ),
        ),
        const Divider(),
        const ListTile(title: Text('Moderatsiya queue')),
        reports.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ListTile(title: Text(e.toString())),
          data: (items) => Column(
            children: [
              for (final item in items)
                ListTile(
                  leading: const Icon(LucideIcons.flag),
                  title: Text(item.reason),
                  subtitle: Text(item.status),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.check),
                        onPressed: () => _resolveReport(item.id, 'resolved'),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.trash2),
                        onPressed: () => _resolveReport(item.id, 'removed'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _linkGroupTab() {
    final convAsync = ref.watch(conversationsProvider);
    final conversation = convAsync.value?.where((c) => c.id == widget.conversationId).firstOrNull;
    if (conversation == null || conversation.type != 'channel') {
      return const Center(child: Text('Faqat kanallarga guruh ulash mumkin.'));
    }

    final groups = convAsync.value?.where((c) => c.type == 'group').toList() ?? [];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Kanal muhokamasi uchun guruh ulanish',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          if (conversation.linkedGroupId != null) ...[
            Text('Ulangan guruh: ${groups.where((g) => g.id == conversation.linkedGroupId).firstOrNull?.name ?? "Noma'lum"}'),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () async {
                await ref.read(conversationAdminRepositoryProvider).unlinkGroup(widget.conversationId);
                ref.invalidate(conversationsProvider);
              },
              icon: const Icon(LucideIcons.unlink),
              label: const Text('Guruhni uzish'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
            ),
          ] else ...[
            const Text('O‘zingiz a’zo bo‘lgan guruhni tanlang:'),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: groups.length,
                itemBuilder: (context, index) {
                  final g = groups[index];
                  return ListTile(
                    title: Text(g.name ?? 'Group'),
                    trailing: const Text('Ulash'),
                    onTap: () async {
                      await ref.read(conversationAdminRepositoryProvider).linkGroup(widget.conversationId, g.id);
                      ref.invalidate(conversationsProvider);
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, int value) => Card(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value.toString(),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              Text(label),
            ],
          ),
        ),
      );

  Future<void> _applyMemberAction(String userId, String action) async {
    final repo = ref.read(conversationAdminRepositoryProvider);
    if (action == 'unrestrict') {
      await repo.removeRestriction(
          conversationId: widget.conversationId, userId: userId, kind: 'ban');
      await repo.removeRestriction(
          conversationId: widget.conversationId,
          userId: userId,
          kind: 'restrict');
    } else {
      await repo.restrictUser(
        conversationId: widget.conversationId,
        userId: userId,
        kind: action,
        reason: 'admin_action',
      );
    }
    ref.invalidate(conversationRestrictionsProvider(widget.conversationId));
  }

  Future<void> _removeRestriction(String userId, String kind) async {
    await ref.read(conversationAdminRepositoryProvider).removeRestriction(
          conversationId: widget.conversationId,
          userId: userId,
          kind: kind,
        );
    ref.invalidate(conversationRestrictionsProvider(widget.conversationId));
  }

  Future<void> _resolveReport(String reportId, String action) async {
    await ref
        .read(conversationAdminRepositoryProvider)
        .resolveReport(reportId, action);
    ref.invalidate(conversationReportsProvider(widget.conversationId));
  }
}
