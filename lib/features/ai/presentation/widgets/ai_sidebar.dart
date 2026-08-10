import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/ai_models.dart';
import '../providers/ai_provider.dart';

class AiSidebar extends ConsumerStatefulWidget {
  final bool isMobile;
  const AiSidebar({super.key, this.isMobile = false});

  @override
  ConsumerState<AiSidebar> createState() => _AiSidebarState();
}

class _AiSidebarState extends ConsumerState<AiSidebar> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _projectsExpanded = false;
  bool _artifactsExpanded = false;
  bool _connectorsExpanded = false;
  bool _pluginsExpanded = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final state = ref.watch(aiProvider);
    final profile = ref.watch(authProvider).profile;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: c.sidebarBackground,
        border: Border(right: BorderSide(color: c.sidebarBorder)),
      ),
      child: Column(
        children: [
          _header(c),
          _newChatButton(c),
          _searchField(c),
          Expanded(child: _body(c, state)),
          _footer(c, profile),
        ],
      ),
    );
  }

  Widget _header(AlsamosColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.alsamosOrange, AppColors.alsamosOrangeDark],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.alsamosOrange.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(LucideIcons.sparkles, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Alsamos AI',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text('Premium Assistant',
                    style: TextStyle(fontSize: 10, color: c.mutedForeground)),
              ],
            ),
          ),
          if (widget.isMobile)
            IconButton(
              icon: const Icon(LucideIcons.x, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            )
          else
            IconButton(
              icon: const Icon(LucideIcons.panelLeftClose, size: 16),
              onPressed: () => ref.read(aiProvider.notifier).toggleSidebarCollapsed(),
              tooltip: 'Yopish',
            ),
        ],
      ),
    );
  }

  Widget _newChatButton(AlsamosColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            ref.read(aiProvider.notifier).startNew();
            if (widget.isMobile) Navigator.of(context).pop();
            HapticFeedback.lightImpact();
          },
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.alsamosOrange, AppColors.alsamosOrangeDark],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.alsamosOrange.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.plus, size: 16, color: Colors.white),
                SizedBox(width: 8),
                Text('Yangi suhbat',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField(AlsamosColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: SizedBox(
        height: 36,
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Suhbatlarni qidirish...',
            hintStyle: TextStyle(fontSize: 12, color: c.mutedForeground.withValues(alpha: 0.7)),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Icon(LucideIcons.search, size: 14, color: c.mutedForeground),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            filled: true,
            fillColor: c.muted.withValues(alpha: 0.5),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.border.withValues(alpha: 0.5)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AlsamosColors c, AiState state) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        _sectionHeader(c, LucideIcons.folderOpen, 'Loyihalar', _projectsExpanded,
            () => setState(() => _projectsExpanded = !_projectsExpanded)),
        if (_projectsExpanded) _projectsSection(c),
        _sectionHeader(c, LucideIcons.layoutGrid, 'Artefaktlar', _artifactsExpanded,
            () => setState(() => _artifactsExpanded = !_artifactsExpanded)),
        if (_artifactsExpanded) _artifactsSection(c),
        _sectionHeader(c, LucideIcons.plug, 'Ulanishlar', _connectorsExpanded,
            () => setState(() => _connectorsExpanded = !_connectorsExpanded)),
        if (_connectorsExpanded) _connectorsSection(c),
        _sectionHeader(c, LucideIcons.puzzle, 'Plaginlar', _pluginsExpanded,
            () => setState(() => _pluginsExpanded = !_pluginsExpanded)),
        if (_pluginsExpanded) _pluginsSection(c),
        const SizedBox(height: 8),
        _recentsHeader(c),
        ..._buildConversationGroups(c, state),
      ],
    );
  }

  Widget _sectionHeader(
      AlsamosColors c, IconData icon, String label, bool expanded, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Icon(expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                  size: 14, color: c.mutedForeground),
              const SizedBox(width: 8),
              Icon(icon, size: 14, color: c.mutedForeground),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c.mutedForeground,
                      letterSpacing: 0.3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _projectsSection(AlsamosColors c) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Column(
        children: [
          _emptyPlaceholder(c, "Loyihalar yo'q", 'Aloqador suhbatlarni tartibga soling'),
          const SizedBox(height: 4),
          _addButton(c, '+ Yangi loyiha', () {}),
        ],
      ),
    );
  }

  Widget _artifactsSection(AlsamosColors c) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: _emptyPlaceholder(c, "Artefaktlar yo'q", 'Yaratilgan hujjatlar shu yerda paydo bo\'ladi'),
    );
  }

  Widget _connectorsSection(AlsamosColors c) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Column(
        children: [
          _connectorTile(c, LucideIcons.shoppingBag, 'Alsamos Bozor', false),
          _connectorTile(c, LucideIcons.creditCard, 'Alsamos To\'lov', false),
          _connectorTile(c, LucideIcons.map, 'Alsamos Xarita', false),
          _connectorTile(c, LucideIcons.gitBranch, 'GitHub', false),
          _connectorTile(c, LucideIcons.globe, 'Google Drive', false),
        ],
      ),
    );
  }

  Widget _connectorTile(AlsamosColors c, IconData icon, String name, bool connected) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: c.mutedForeground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name, style: TextStyle(fontSize: 11, color: c.foreground)),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: connected ? const Color(0xFF22C55E) : c.mutedForeground.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pluginsSection(AlsamosColors c) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Column(
        children: [
          _pluginTile(c, 'Kod tekshiruvchi', true),
          _pluginTile(c, 'Hujjat yozuvchi', true),
          _pluginTile(c, 'Tarjimon', true),
        ],
      ),
    );
  }

  Widget _pluginTile(AlsamosColors c, String name, bool enabled) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(LucideIcons.puzzle, size: 12, color: enabled ? AppColors.alsamosOrange : c.mutedForeground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name, style: TextStyle(fontSize: 11, color: c.foreground)),
          ),
          Icon(
            enabled ? LucideIcons.toggleRight : LucideIcons.toggleLeft,
            size: 14,
            color: enabled ? AppColors.alsamosOrange : c.mutedForeground,
          ),
        ],
      ),
    );
  }

  Widget _recentsHeader(AlsamosColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Icon(LucideIcons.clock, size: 14, color: c.mutedForeground),
          const SizedBox(width: 8),
          Text('So\'nggi suhbatlar',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c.mutedForeground,
                  letterSpacing: 0.3)),
        ],
      ),
    );
  }

  List<Widget> _buildConversationGroups(AlsamosColors c, AiState state) {
    final filtered = state.conversations
        .where((conv) => conv.title.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    if (filtered.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              children: [
                Icon(LucideIcons.messageSquare, size: 24, color: c.mutedForeground.withValues(alpha: 0.4)),
                const SizedBox(height: 8),
                Text(
                  _query.isNotEmpty ? 'Natija topilmadi' : "Hali suhbatlar yo'q",
                  style: TextStyle(fontSize: 11, color: c.mutedForeground),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    final now = DateTime.now();
    final today = <AiConversation>[];
    final yesterday = <AiConversation>[];
    final week = <AiConversation>[];
    final month = <AiConversation>[];
    final older = <AiConversation>[];

    for (final conv in filtered) {
      final diff = now.difference(conv.updatedAt).inDays;
      if (diff == 0) {
        today.add(conv);
      } else if (diff == 1) {
        yesterday.add(conv);
      } else if (diff < 7) {
        week.add(conv);
      } else if (diff < 30) {
        month.add(conv);
      } else {
        older.add(conv);
      }
    }

    final widgets = <Widget>[];
    if (today.isNotEmpty) {
      widgets.add(_dateLabel(c, 'Bugun'));
      widgets.addAll(today.map((conv) => _convTile(c, conv, state)));
    }
    if (yesterday.isNotEmpty) {
      widgets.add(_dateLabel(c, 'Kecha'));
      widgets.addAll(yesterday.map((conv) => _convTile(c, conv, state)));
    }
    if (week.isNotEmpty) {
      widgets.add(_dateLabel(c, 'Shu hafta'));
      widgets.addAll(week.map((conv) => _convTile(c, conv, state)));
    }
    if (month.isNotEmpty) {
      widgets.add(_dateLabel(c, 'Shu oy'));
      widgets.addAll(month.map((conv) => _convTile(c, conv, state)));
    }
    if (older.isNotEmpty) {
      widgets.add(_dateLabel(c, 'Avvalgi'));
      widgets.addAll(older.map((conv) => _convTile(c, conv, state)));
    }
    return widgets;
  }

  Widget _dateLabel(AlsamosColors c, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: c.mutedForeground.withValues(alpha: 0.7))),
    );
  }

  Widget _convTile(AlsamosColors c, AiConversation conv, AiState state) {
    final selected = conv.id == state.currentConversationId;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          ref.read(aiProvider.notifier).openConversation(conv);
          if (widget.isMobile) Navigator.of(context).pop();
        },
        onLongPress: () => _showConvMenu(c, conv),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? c.sidebarAccent : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                conv.type == 'imagine' ? LucideIcons.image : LucideIcons.messageSquare,
                size: 14,
                color: selected ? AppColors.alsamosOrange : c.mutedForeground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  conv.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? c.foreground : c.sidebarForeground,
                  ),
                ),
              ),
              if (selected)
                InkWell(
                  onTap: () => _showConvMenu(c, conv),
                  child: Icon(LucideIcons.moreHorizontal, size: 14, color: c.mutedForeground),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConvMenu(AlsamosColors c, AiConversation conv) {
    showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(LucideIcons.pin, size: 18, color: c.foreground),
              title: const Text('Pin qilish', style: TextStyle(fontSize: 14)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: Icon(LucideIcons.pencil, size: 18, color: c.foreground),
              title: const Text('Nomini o\'zgartirish', style: TextStyle(fontSize: 14)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: Icon(LucideIcons.folderInput, size: 18, color: c.foreground),
              title: const Text('Loyihaga ko\'chirish', style: TextStyle(fontSize: 14)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: Icon(LucideIcons.download, size: 18, color: c.foreground),
              title: const Text('Eksport qilish', style: TextStyle(fontSize: 14)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: Icon(LucideIcons.trash2, size: 18, color: c.destructive),
              title: Text("O'chirish", style: TextStyle(color: c.destructive, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                ref.read(aiProvider.notifier).deleteConversation(conv.id);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _emptyPlaceholder(AlsamosColors c, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, color: c.mutedForeground)),
          Text(subtitle,
              style: TextStyle(fontSize: 10, color: c.mutedForeground.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _addButton(AlsamosColors c, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.alsamosOrange,
                  fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }

  Widget _footer(AlsamosColors c, dynamic profile) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.sidebarBorder)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: c.muted,
            backgroundImage: (profile?.avatarUrl?.isNotEmpty == true)
                ? CachedNetworkImageProvider(profile!.avatarUrl!)
                : null,
            child: (profile?.avatarUrl?.isNotEmpty != true)
                ? Icon(LucideIcons.user, size: 14, color: c.mutedForeground)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile?.displayName ?? profile?.username ?? 'Foydalanuvchi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text('Premium', style: TextStyle(fontSize: 10, color: c.mutedForeground)),
              ],
            ),
          ),
          Icon(LucideIcons.settings, size: 14, color: c.mutedForeground),
        ],
      ),
    );
  }
}
