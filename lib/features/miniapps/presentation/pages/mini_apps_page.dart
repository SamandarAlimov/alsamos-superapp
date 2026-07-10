import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/mini_app_model.dart';
import '../providers/miniapps_provider.dart';
import 'mini_app_browser_page.dart';

/// Pixel-perfect Flutter port of web `MiniAppsPage.tsx` (927 lines).
class MiniAppsPage extends ConsumerStatefulWidget {
  const MiniAppsPage({super.key});
  @override
  ConsumerState<MiniAppsPage> createState() => _MiniAppsPageState();
}

class _MiniAppsPageState extends ConsumerState<MiniAppsPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _activeCat = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // --------------------------- actions ---------------------------

  String _catLabel(String id) => miniAppCategories
      .firstWhere((c) => c.id == id, orElse: () => miniAppCategories.last)
      .label;

  void _openApp(MiniApp app) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MiniAppBrowserPage(app: app)),
    );
  }

  Future<void> _confirmDelete(MiniApp app) async {
    final c = AlsamosColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Mini App o'chirilsinmi?",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: Text(
          "\"${app.name}\" mini ilovasi butunlay o'chiriladi. Bu amalni qaytarib bo'lmaydi.",
          style: TextStyle(color: c.mutedForeground, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: const Text("O'chirish"),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(miniAppsProvider.notifier).delete(app.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Mini app o'chirildi")),
        );
      }
    }
  }

  // --------------------------- detail sheet ---------------------------

  void _showDetail(MiniApp app) {
    HapticFeedback.selectionClick();
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final me = ref.read(authProvider).profile;
    final isOwner = me != null && me.id == app.userId;
    final isWide = MediaQuery.of(context).size.width >= 768;

    if (isWide) {
      showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.7),
        builder: (_) => Dialog(
          backgroundColor: c.background.withValues(alpha: 0.95),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _DetailSheetBody(
              app: app,
              isOwner: isOwner,
              c: c,
              primary: primary,
              showHandle: false,
              onClose: () => Navigator.pop(context),
              onOpen: () {
                Navigator.pop(context);
                _openApp(app);
              },
              onEdit: () {
                Navigator.pop(context);
                _showFormDialog(editing: app);
              },
              onDelete: () {
                Navigator.pop(context);
                _confirmDelete(app);
              },
              catLabel: _catLabel(app.category),
            ),
          ),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: c.background.withValues(alpha: 0.97),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: c.border.withValues(alpha: 0.5)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
          ),
          child: _DetailSheetBody(
            app: app,
            isOwner: isOwner,
            c: c,
            primary: primary,
            showHandle: true,
            onClose: () => Navigator.pop(context),
            onOpen: () {
              Navigator.pop(context);
              _openApp(app);
            },
            onEdit: () {
              Navigator.pop(context);
              _showFormDialog(editing: app);
            },
            onDelete: () {
              Navigator.pop(context);
              _confirmDelete(app);
            },
            catLabel: _catLabel(app.category),
          ),
        ),
      ),
    );
  }

  // --------------------------- create/edit dialog ---------------------------

  Future<void> _showFormDialog({MiniApp? editing}) async {
    final me = ref.read(authProvider).profile;
    if (me == null) return;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => _MiniAppFormDialog(
        editing: editing,
        userId: me.id,
      ),
    );
  }

  // --------------------------- build ---------------------------

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final me = ref.watch(authProvider).profile;
    final state = ref.watch(miniAppsProvider);

    final apps = state.apps;
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = apps.where((a) {
      final matchCat = _activeCat == 'all' || a.category == _activeCat;
      final matchQ = q.isEmpty ||
          a.name.toLowerCase().contains(q) ||
          (a.description ?? '').toLowerCase().contains(q);
      return matchCat && matchQ;
    }).toList();

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1024), // max-w-5xl
            child: LayoutBuilder(
              builder: (ctx, cons) {
                final w = cons.maxWidth;
                final hPad = w < 640 ? 12.0 : (w < 768 ? 16.0 : 24.0);
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 0),
                      sliver: SliverToBoxAdapter(
                        child: _Header(
                          c: c,
                          primary: primary,
                          canCreate: me != null,
                          onCreate: () => _showFormDialog(),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 0),
                      sliver: SliverToBoxAdapter(
                        child: _SearchField(
                          controller: _searchCtrl,
                          onChanged: () => setState(() {}),
                          onClear: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                          c: c,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(0, 16, 0, 0),
                      sliver: SliverToBoxAdapter(
                        child: _CategoriesRow(
                          horizontalPadding: hPad,
                          activeCat: _activeCat,
                          onSelect: (id) {
                            HapticFeedback.selectionClick();
                            setState(() => _activeCat = id);
                          },
                          c: c,
                          primary: primary,
                        ),
                      ),
                    ),
                    if (state.isLoading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (filtered.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyState(
                          c: c,
                          isSearching: q.isNotEmpty,
                          canCreate: me != null,
                          onCreate: () => _showFormDialog(),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 96),
                        sliver: SliverGrid(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: w < 640
                                ? 3
                                : (w < 768 ? 4 : (w < 1024 ? 5 : 6)),
                            mainAxisSpacing: w < 640 ? 8 : 12,
                            crossAxisSpacing: w < 640 ? 8 : 12,
                            childAspectRatio: 0.82,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => _AppTile(
                              app: filtered[i],
                              onTap: () => _showDetail(filtered[i]),
                              c: c,
                              primary: primary,
                              compact: w < 640,
                            ),
                            childCount: filtered.length,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ============================== HEADER ==============================

class _Header extends StatelessWidget {
  const _Header({
    required this.c,
    required this.primary,
    required this.canCreate,
    required this.onCreate,
  });
  final AlsamosColors c;
  final Color primary;
  final bool canCreate;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final titleSize = w < 640 ? 20.0 : (w < 768 ? 24.0 : 30.0);
    final subSize = w < 640 ? 11.0 : 13.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mini Apps',
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  color: c.foreground,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "O'z ilovangizni yarating yoki boshqalarnikini kashf qiling",
                style: TextStyle(
                  fontSize: subSize,
                  color: c.mutedForeground,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        if (canCreate)
          FilledButton.icon(
            onPressed: () {
              HapticFeedback.mediumImpact();
              onCreate();
            },
            icon: const Icon(LucideIcons.plus, size: 16),
            label: Text(w < 640 ? '' : 'Yaratish'),
            style: FilledButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                  horizontal: w < 640 ? 12 : 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              minimumSize: const Size(44, 40),
            ),
          ),
      ],
    );
  }
}

// ============================== SEARCH ==============================

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.c,
  });
  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onClear;
  final AlsamosColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border.withValues(alpha: 0.5)),
      ),
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        style: TextStyle(color: c.foreground, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Mini app qidirish...',
          hintStyle:
              TextStyle(color: c.mutedForeground, fontSize: 14),
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(LucideIcons.search,
                size: 16, color: c.mutedForeground),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(LucideIcons.x,
                      size: 16, color: c.mutedForeground),
                  onPressed: onClear,
                ),
          border: InputBorder.none,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        ),
      ),
    );
  }
}

// ============================== CATEGORIES ==============================

class _CategoriesRow extends StatelessWidget {
  const _CategoriesRow({
    required this.horizontalPadding,
    required this.activeCat,
    required this.onSelect,
    required this.c,
    required this.primary,
  });
  final double horizontalPadding;
  final String activeCat;
  final ValueChanged<String> onSelect;
  final AlsamosColors c;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        itemCount: miniAppCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = miniAppCategories[i];
          final active = activeCat == cat.id;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            child: Material(
              color: active ? primary : c.card.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelect(cat.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active
                          ? primary
                          : c.border.withValues(alpha: 0.5),
                    ),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: primary.withValues(alpha: 0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    cat.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : c.mutedForeground,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================== EMPTY STATE ==============================

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.c,
    required this.isSearching,
    required this.canCreate,
    required this.onCreate,
  });
  final AlsamosColors c;
  final bool isSearching;
  final bool canCreate;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.appWindow,
              size: 64,
              color: c.mutedForeground.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              isSearching ? 'Hech narsa topilmadi' : "Hali mini app yo'q",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: c.foreground,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isSearching
                  ? "Boshqa kalit so'z bilan qidiring"
                  : "Birinchi bo'lib o'z mini appingizni yarating!",
              style: TextStyle(fontSize: 14, color: c.mutedForeground),
              textAlign: TextAlign.center,
            ),
            if (!isSearching && canCreate) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onCreate,
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Mini App yaratish'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================== APP TILE ==============================

class _AppTile extends StatefulWidget {
  const _AppTile({
    required this.app,
    required this.onTap,
    required this.c,
    required this.primary,
    required this.compact,
  });
  final MiniApp app;
  final VoidCallback onTap;
  final AlsamosColors c;
  final Color primary;
  final bool compact;

  @override
  State<_AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<_AppTile> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final iconBox = widget.compact ? 44.0 : 56.0;
    final iconImg = widget.compact ? 32.0 : 40.0;
    final nameSize = widget.compact ? 11.0 : 13.0;
    final ratingSize = widget.compact ? 9.0 : 10.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: _pressed ? 0.95 : (_hover ? 1.02 : 1.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              color: _hover
                  ? widget.c.card.withValues(alpha: 0.7)
                  : widget.c.card.withValues(alpha: 0.4),
              borderRadius:
                  BorderRadius.circular(widget.compact ? 12 : 16),
              border: Border.all(
                color: _hover
                    ? widget.primary.withValues(alpha: 0.4)
                    : widget.c.border.withValues(alpha: 0.5),
              ),
              boxShadow: _hover
                  ? [
                      BoxShadow(
                        color: widget.primary.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : null,
            ),
            padding: EdgeInsets.all(widget.compact ? 10 : 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: iconBox,
                  height: iconBox,
                  decoration: BoxDecoration(
                    color: widget.c.muted.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(
                        widget.compact ? 12 : 16),
                    border: Border.all(
                        color: widget.c.border.withValues(alpha: 0.3)),
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(widget.compact ? 12 : 16),
                    child: widget.app.iconUrl != null &&
                            widget.app.iconUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.app.iconUrl!,
                            width: iconImg,
                            height: iconImg,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Icon(
                              LucideIcons.globe,
                              size: widget.compact ? 20 : 28,
                              color: widget.primary,
                            ),
                          )
                        : Icon(
                            LucideIcons.globe,
                            size: widget.compact ? 20 : 28,
                            color: widget.primary,
                          ),
                  ),
                ),
                SizedBox(height: widget.compact ? 8 : 10),
                Text(
                  widget.app.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: nameSize,
                    fontWeight: FontWeight.w600,
                    color: widget.c.foreground,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: widget.compact ? 2 : 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.star,
                        size: 11, color: Color(0xFFFBBF24)),
                    const SizedBox(width: 3),
                    Text(
                      widget.app.rating.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: ratingSize,
                        color: widget.c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================== DETAIL SHEET BODY ==============================

class _DetailSheetBody extends StatelessWidget {
  const _DetailSheetBody({
    required this.app,
    required this.isOwner,
    required this.c,
    required this.primary,
    required this.showHandle,
    required this.onClose,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.catLabel,
  });
  final MiniApp app;
  final bool isOwner;
  final AlsamosColors c;
  final Color primary;
  final bool showHandle;
  final VoidCallback onClose;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String catLabel;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHandle)
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: c.mutedForeground.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          // Title row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: c.muted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: c.border.withValues(alpha: 0.3)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: app.iconUrl != null && app.iconUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: app.iconUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Icon(
                              LucideIcons.globe,
                              size: 32,
                              color: primary),
                        )
                      : Icon(LucideIcons.globe,
                          size: 32, color: primary),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.name,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: c.foreground,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      app.description == null ||
                              app.description!.trim().isEmpty
                          ? 'Tavsif mavjud emas'
                          : app.description!,
                      style: TextStyle(
                        fontSize: 13,
                        color: c.mutedForeground,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onClose,
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    child: Icon(LucideIcons.x,
                        size: 18, color: c.mutedForeground),
                  ),
                ),
              ),
            ],
          ),
          // Author + category row
          if (app.authorName != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.muted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: c.border.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: c.muted,
                    child: Text(
                      app.authorName!.isNotEmpty
                          ? app.authorName![0].toUpperCase()
                          : 'U',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.foreground),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.authorName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.foreground,
                          ),
                        ),
                        if (app.authorUsername != null)
                          Text(
                            '@${app.authorUsername}',
                            style: TextStyle(
                                fontSize: 11, color: c.mutedForeground),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.muted.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      catLabel,
                      style: TextStyle(
                        fontSize: 10,
                        color: c.mutedForeground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Stats row
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: c.border.withValues(alpha: 0.5)),
                bottom: BorderSide(color: c.border.withValues(alpha: 0.5)),
              ),
            ),
            child: Row(
              children: [
                _StatCell(
                  icon: LucideIcons.star,
                  iconColor: const Color(0xFFFBBF24),
                  value: app.rating.toStringAsFixed(1),
                  label: 'Reyting',
                  c: c,
                ),
                _StatDivider(c: c),
                _StatCell(
                  value: '${app.usersCount}',
                  label: 'Foydalanuvchilar',
                  c: c,
                ),
                _StatDivider(c: c),
                _StatCell(
                  value: 'Bepul',
                  label: 'Narxi',
                  c: c,
                ),
              ],
            ),
          ),
          // Open button
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(LucideIcons.appWindow, size: 18),
              label: const Text('Ochish'),
              style: FilledButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (isOwner) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(LucideIcons.edit2, size: 14),
                    label: const Text('Tahrirlash'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.foreground,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      side: BorderSide(
                          color: c.border.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(LucideIcons.trash2,
                        size: 14, color: Color(0xFFEF4444)),
                    label: const Text(
                      "O'chirish",
                      style: TextStyle(color: Color(0xFFEF4444)),
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    this.icon,
    this.iconColor,
    required this.value,
    required this.label,
    required this.c,
  });
  final IconData? icon;
  final Color? iconColor;
  final String value;
  final String label;
  final AlsamosColors c;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 4),
              ],
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: c.foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
                fontSize: 11, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider({required this.c});
  final AlsamosColors c;
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 32,
        color: c.border.withValues(alpha: 0.5),
      );
}

// ============================== CREATE/EDIT DIALOG ==============================

class _MiniAppFormDialog extends ConsumerStatefulWidget {
  const _MiniAppFormDialog({
    required this.editing,
    required this.userId,
  });
  final MiniApp? editing;
  final String userId;

  @override
  ConsumerState<_MiniAppFormDialog> createState() =>
      _MiniAppFormDialogState();
}

class _MiniAppFormDialogState extends ConsumerState<_MiniAppFormDialog> {
  late final TextEditingController nameCtrl;
  late final TextEditingController urlCtrl;
  late final TextEditingController descCtrl;
  late final TextEditingController iconUrlCtrl;
  late String _cat;
  File? _pickedIcon;
  String? _existingIconUrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    nameCtrl = TextEditingController(text: e?.name ?? '');
    urlCtrl = TextEditingController(text: e?.url ?? '');
    descCtrl = TextEditingController(text: e?.description ?? '');
    iconUrlCtrl = TextEditingController(text: e?.iconUrl ?? '');
    _cat = e?.category ?? 'other';
    _existingIconUrl = e?.iconUrl;
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    urlCtrl.dispose();
    descCtrl.dispose();
    iconUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    HapticFeedback.selectionClick();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 90,
    );
    if (picked == null) return;
    setState(() {
      _pickedIcon = File(picked.path);
      _existingIconUrl = null;
      iconUrlCtrl.clear();
    });
  }

  void _removeIcon() {
    setState(() {
      _pickedIcon = null;
      _existingIconUrl = null;
      iconUrlCtrl.clear();
    });
  }

  Future<void> _submit() async {
    final name = nameCtrl.text.trim();
    final url = urlCtrl.text.trim();
    if (name.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nom va URL kiritilishi shart')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      String? iconUrl =
          iconUrlCtrl.text.trim().isEmpty ? null : iconUrlCtrl.text.trim();
      if (_pickedIcon != null) {
        final repo = ref.read(miniAppsRepositoryProvider);
        iconUrl = await repo.uploadIcon(
            userId: widget.userId, file: _pickedIcon!);
      } else if (_existingIconUrl != null && iconUrl == null) {
        iconUrl = _existingIconUrl;
      }

      final notifier = ref.read(miniAppsProvider.notifier);
      if (widget.editing == null) {
        await notifier.create(
          name: name,
          url: url,
          description:
              descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
          iconUrl: iconUrl,
          category: _cat,
        );
      } else {
        await notifier.update(
          id: widget.editing!.id,
          name: name,
          url: url,
          description:
              descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
          iconUrl: iconUrl,
          category: _cat,
        );
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.editing == null
                ? 'Mini app yaratildi'
                : 'Mini app saqlandi'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xatolik: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final isEdit = widget.editing != null;

    return Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 448),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit ? 'Mini App tahrirlash' : 'Mini App yaratish',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: c.foreground,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(LucideIcons.x,
                        size: 18, color: c.mutedForeground),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FieldLabel('Nom *', c: c),
              const SizedBox(height: 6),
              _AppTextField(
                controller: nameCtrl,
                hint: 'Masalan: Islom.uz',
                c: c,
              ),
              const SizedBox(height: 14),
              _FieldLabel('URL *', c: c),
              const SizedBox(height: 6),
              _AppTextField(
                controller: urlCtrl,
                hint: 'https://example.com',
                keyboard: TextInputType.url,
                c: c,
              ),
              const SizedBox(height: 14),
              _FieldLabel('Tavsif', c: c),
              const SizedBox(height: 6),
              _AppTextField(
                controller: descCtrl,
                hint: 'Qisqa tavsif...',
                maxLines: 2,
                c: c,
              ),
              const SizedBox(height: 14),
              _FieldLabel('Ikonka (rasm yuklash)', c: c),
              const SizedBox(height: 6),
              _IconPicker(
                pickedFile: _pickedIcon,
                existingUrl: _existingIconUrl,
                onPick: _pickIcon,
                onRemove: _removeIcon,
                c: c,
                primary: primary,
              ),
              if (_pickedIcon == null && _existingIconUrl == null) ...[
                const SizedBox(height: 8),
                _AppTextField(
                  controller: iconUrlCtrl,
                  hint: 'Yoki URL kiriting: https://example.com/icon.png',
                  keyboard: TextInputType.url,
                  c: c,
                ),
              ],
              const SizedBox(height: 14),
              _FieldLabel('Kategoriya', c: c),
              const SizedBox(height: 6),
              _CategoryDropdown(
                value: _cat,
                onChanged: (v) => setState(() => _cat = v ?? 'other'),
                c: c,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(isEdit ? LucideIcons.edit2 : LucideIcons.plus,
                          size: 16),
                  label: Text(isEdit ? 'Saqlash' : 'Yaratish'),
                  style: FilledButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {required this.c});
  final String text;
  final AlsamosColors c;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: c.foreground,
        ),
      );
}

class _AppTextField extends StatelessWidget {
  const _AppTextField({
    required this.controller,
    required this.hint,
    required this.c,
    this.keyboard,
    this.maxLines = 1,
  });
  final TextEditingController controller;
  final String hint;
  final AlsamosColors c;
  final TextInputType? keyboard;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      maxLines: maxLines,
      style: TextStyle(fontSize: 14, color: c.foreground),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14, color: c.mutedForeground),
        filled: true,
        fillColor: c.background.withValues(alpha: 0.6),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: c.border.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: c.border.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary, width: 1.2),
        ),
      ),
    );
  }
}

class _IconPicker extends StatelessWidget {
  const _IconPicker({
    required this.pickedFile,
    required this.existingUrl,
    required this.onPick,
    required this.onRemove,
    required this.c,
    required this.primary,
  });
  final File? pickedFile;
  final String? existingUrl;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final AlsamosColors c;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    if (pickedFile != null) {
      return Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              pickedFile!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onRemove,
            icon: const Icon(LucideIcons.x, size: 13),
            label: const Text("O'chirish"),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.foreground,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              side: BorderSide(color: c.border),
            ),
          ),
        ],
      );
    }
    if (existingUrl != null && existingUrl!.isNotEmpty) {
      return Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: c.border.withValues(alpha: 0.5)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: existingUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    Icon(LucideIcons.globe, color: primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onRemove,
            icon: const Icon(LucideIcons.x, size: 13),
            label: const Text("O'chirish"),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.foreground,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              side: BorderSide(color: c.border),
            ),
          ),
        ],
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPick,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: c.border.withValues(alpha: 0.6),
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.plus, size: 18, color: c.mutedForeground),
            const SizedBox(width: 8),
            Text(
              'PNG, JPG, SVG, ICO',
              style: TextStyle(
                  fontSize: 13, color: c.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({
    required this.value,
    required this.onChanged,
    required this.c,
  });
  final String value;
  final ValueChanged<String?> onChanged;
  final AlsamosColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.background.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border.withValues(alpha: 0.5)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: Icon(LucideIcons.chevronDown,
              size: 16, color: c.mutedForeground),
          dropdownColor: c.card,
          style: TextStyle(fontSize: 14, color: c.foreground),
          items: miniAppCategories
              .where((cat) => cat.id != 'all')
              .map((cat) => DropdownMenuItem<String>(
                    value: cat.id,
                    child: Text(cat.label),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
