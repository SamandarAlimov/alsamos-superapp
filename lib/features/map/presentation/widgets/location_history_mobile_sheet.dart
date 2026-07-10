// Location History Mobile Sheet - 100% 1:1 web LocationHistoryMobileSheet.tsx port
// Shows: FrequentPlaces (home/work/study/other) + DailyRoutes from Supabase
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/map_models.dart';
import '../providers/map_provider.dart';

class LocationHistoryMobileSheet extends ConsumerStatefulWidget {
  final bool open;
  final ValueChanged<bool> onOpenChange;
  final void Function(double lat, double lng, String name)? onNavigateToPlace;
  final void Function(DailyRoute route)? onViewRoute;

  const LocationHistoryMobileSheet({
    super.key,
    required this.open,
    required this.onOpenChange,
    this.onNavigateToPlace,
    this.onViewRoute,
  });

  @override
  ConsumerState<LocationHistoryMobileSheet> createState() => _LocationHistoryMobileSheetState();
}

class _LocationHistoryMobileSheetState extends ConsumerState<LocationHistoryMobileSheet> {
  int _tab = 0; // 0=places, 1=routes
  String? _editingPlaceId;
  final _editCtrl = TextEditingController();

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open) return const SizedBox.shrink();
    final c   = AlsamosColors.of(context);
    final hist = ref.watch(locationHistoryProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, sc) => Container(
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: c.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, -4))],
        ),
        child: Column(children: [
          // drag handle
          Center(child: Container(width: 48, height: 5, margin: const EdgeInsets.only(top: 10, bottom: 6), decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(3)))),
          // header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
            child: Row(children: [
              Icon(LucideIcons.footprints, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text('Joylashuv tarixi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.foreground)),
              const Spacer(),
              GestureDetector(onTap: () { HapticFeedback.selectionClick(); widget.onOpenChange(false); },
                child: Container(width: 32, height: 32, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)), child: Icon(LucideIcons.x, size: 18, color: c.mutedForeground))),
            ]),
          ),
          Expanded(child: CustomScrollView(controller: sc, slivers: [
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                // stats summary
                Row(children: [
                  Expanded(child: _StatCard(
                    label: 'Haftalik masofa',
                    value: '${ref.read(locationHistoryProvider.notifier).getTotalDistance(7).toStringAsFixed(1)} km',
                    gradient: [Theme.of(context).colorScheme.primary.withValues(alpha: 0.12), Theme.of(context).colorScheme.primary.withValues(alpha: 0.04)],
                    borderColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                    valueColor: Theme.of(context).colorScheme.primary,
                    c: c,
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(
                    label: 'Oylik masofa',
                    value: '${ref.read(locationHistoryProvider.notifier).getTotalDistance(30).toStringAsFixed(1)} km',
                    gradient: [c.muted.withValues(alpha: 0.8), c.muted.withValues(alpha: 0.4)],
                    borderColor: c.border,
                    valueColor: c.foreground,
                    c: c,
                  )),
                ]),
                // today route summary
                if (hist.todayRoute != null) ...[
                  const SizedBox(height: 12),
                  _TodayRouteCard(route: hist.todayRoute!, c: c),
                ],
                const SizedBox(height: 14),
                // tab switcher
                Container(
                  decoration: BoxDecoration(color: c.muted.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.all(3),
                  child: Row(children: [
                    Expanded(child: _TabBtn(label: 'Joylar', icon: LucideIcons.mapPin, selected: _tab == 0, onTap: () => setState(() => _tab = 0), c: c)),
                    Expanded(child: _TabBtn(label: "Yo'llar", icon: LucideIcons.route, selected: _tab == 1, onTap: () => setState(() => _tab = 1), c: c)),
                  ]),
                ),
              ]),
            )),
            // content
            if (hist.loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (_tab == 0)
              _buildPlacesSliver(hist, c)
            else
              _buildRoutesSliver(hist, c),
          ])),
        ]),
      ),
    );
  }

  SliverList _buildPlacesSliver(LocationHistoryState hist, AlsamosColors c) {
    if (hist.frequentPlaces.isEmpty) {
      return SliverList(delegate: SliverChildListDelegate([
        Padding(padding: const EdgeInsets.all(32), child: Column(children: [
          Icon(LucideIcons.mapPin, size: 48, color: c.mutedForeground),
          const SizedBox(height: 12),
          Text('Hali joylar aniqlanmadi', style: TextStyle(fontWeight: FontWeight.w600, color: c.foreground)),
          const SizedBox(height: 4),
          Text('Kuzatishni yoqing va harakatlaning', style: TextStyle(fontSize: 13, color: c.mutedForeground)),
        ])),
      ]));
    }
    return SliverList(delegate: SliverChildBuilderDelegate(
      (_, i) {
        final place = hist.frequentPlaces[i];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _FrequentPlaceCard(
            place: place, c: c,
            isEditing: _editingPlaceId == place.id,
            editCtrl: _editCtrl,
            onNavigate: () {
              widget.onNavigateToPlace?.call(place.latitude, place.longitude, place.name);
              widget.onOpenChange(false);
            },
            onEdit: () { setState(() { _editingPlaceId = place.id; _editCtrl.text = place.name; }); },
            onSave: () async {
              if (_editCtrl.text.trim().isNotEmpty) {
                await ref.read(locationHistoryProvider.notifier).updateName(place.id, _editCtrl.text.trim());
              }
              setState(() { _editingPlaceId = null; });
            },
            onDelete: () async {
              await ref.read(locationHistoryProvider.notifier).delete(place.id);
            },
          ),
        );
      },
      childCount: hist.frequentPlaces.length,
    ));
  }

  SliverList _buildRoutesSliver(LocationHistoryState hist, AlsamosColors c) {
    final primary = Theme.of(context).colorScheme.primary;
    if (hist.dailyRoutes.isEmpty) {
      return SliverList(delegate: SliverChildListDelegate([
        Padding(padding: const EdgeInsets.all(32), child: Column(children: [
          Icon(LucideIcons.route, size: 48, color: c.mutedForeground),
          const SizedBox(height: 12),
          Text("Hali yo'llar saqlanmadi", style: TextStyle(fontWeight: FontWeight.w600, color: c.foreground)),
          const SizedBox(height: 4),
          Text('Kuzatishni yoqing va harakatlaning', style: TextStyle(fontSize: 13, color: c.mutedForeground)),
        ])),
      ]));
    }
    return SliverList(delegate: SliverChildBuilderDelegate(
      (_, i) {
        final route = hist.dailyRoutes[i];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: GestureDetector(
            onTap: () { widget.onViewRoute?.call(route); widget.onOpenChange(false); },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
              child: Row(children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(color: primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(LucideIcons.calendar, size: 20, color: primary)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(route.routeDate, style: TextStyle(fontWeight: FontWeight.w600, color: c.foreground)),
                  const SizedBox(height: 3),
                  Row(children: [
                    Icon(LucideIcons.trendingUp, size: 13, color: c.mutedForeground),
                    const SizedBox(width: 3),
                    Text('${route.totalDistanceKm.toStringAsFixed(1)} km', style: TextStyle(fontSize: 12, color: c.mutedForeground)),
                    const SizedBox(width: 10),
                    Icon(LucideIcons.mapPin, size: 13, color: c.mutedForeground),
                    const SizedBox(width: 3),
                    Text('${route.routeGeometry.length} nuqta', style: TextStyle(fontSize: 12, color: c.mutedForeground)),
                  ]),
                ])),
                Icon(LucideIcons.eye, size: 18, color: c.mutedForeground),
              ]),
            ),
          ),
        );
      },
      childCount: hist.dailyRoutes.length,
    ));
  }
}

// ─── Stat card ─────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final List<Color> gradient;
  final Color borderColor;
  final Color valueColor;
  final AlsamosColors c;
  const _StatCard({required this.label, required this.value, required this.gradient, required this.borderColor, required this.valueColor, required this.c});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: c.mutedForeground)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: valueColor)),
      ]),
    );
  }
}

class _TodayRouteCard extends StatelessWidget {
  final DailyRoute route;
  final AlsamosColors c;
  const _TodayRouteCard({required this.route, required this.c});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.muted.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.route, size: 16, color: primary),
          const SizedBox(width: 6),
          Text("Bugungi yo'l", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.foreground)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(6)),
            child: Text('${route.totalDistanceKm.toStringAsFixed(1)} km', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: c.mutedForeground)),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Icon(LucideIcons.mapPin, size: 13, color: c.mutedForeground),
          const SizedBox(width: 4),
          Text('${route.routeGeometry.length} nuqta', style: TextStyle(fontSize: 12, color: c.mutedForeground)),
          const SizedBox(width: 12),
          Icon(LucideIcons.clock, size: 13, color: c.mutedForeground),
          const SizedBox(width: 4),
          Text('${route.placesVisited} joy', style: TextStyle(fontSize: 12, color: c.mutedForeground)),
        ]),
      ]),
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final AlsamosColors c;
  const _TabBtn({required this.label, required this.icon, required this.selected, required this.onTap, required this.c});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: selected ? c.background : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 14, color: selected ? Theme.of(context).colorScheme.primary : c.mutedForeground),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: selected ? c.foreground : c.mutedForeground)),
        ]),
      ),
    );
  }
}

class _FrequentPlaceCard extends StatelessWidget {
  final FrequentPlace place;
  final AlsamosColors c;
  final bool isEditing;
  final TextEditingController editCtrl;
  final VoidCallback onNavigate;
  final VoidCallback onEdit;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  const _FrequentPlaceCard({required this.place, required this.c, required this.isEditing, required this.editCtrl, required this.onNavigate, required this.onEdit, required this.onSave, required this.onDelete});

  (IconData, Color, String) _placeStyle() => switch (place.placeType) {
    'home'  => (LucideIcons.home, const Color(0xFF3B82F6), 'Uy'),
    'work'  => (LucideIcons.briefcase, const Color(0xFFF59E0B), 'Ish'),
    'study' => (LucideIcons.graduationCap, const Color(0xFF8B5CF6), "Ta'lim"),
    _       => (LucideIcons.mapPin, const Color(0xFF6B7280), 'Boshqa'),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _placeStyle();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.2))),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(child: isEditing
            ? Row(children: [
                Expanded(child: TextField(
                  controller: editCtrl,
                  autofocus: true,
                  style: TextStyle(fontSize: 14, color: c.foreground),
                  decoration: InputDecoration(hintText: 'Joy nomi', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                )),
                const SizedBox(width: 8),
                TextButton(onPressed: onSave, child: const Text('Saqlash')),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(place.name.isNotEmpty ? place.name : label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.foreground), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(4)),
                    child: Text('${(place.confidenceScore * 100).round()}%', style: TextStyle(fontSize: 10, color: c.mutedForeground)),
                  ),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(LucideIcons.clock, size: 12, color: c.mutedForeground),
                  const SizedBox(width: 3),
                  Text('~${place.averageStayMinutes} min', style: TextStyle(fontSize: 11, color: c.mutedForeground)),
                  const SizedBox(width: 10),
                  Text('${place.visitCount} tashrif', style: TextStyle(fontSize: 11, color: c.mutedForeground)),
                ]),
              ])),
        ]),
        const SizedBox(height: 10),
        // action row (web 1:1)
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(LucideIcons.edit2, size: 14),
            label: const Text('Tahrirlash', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: onNavigate,
            icon: const Icon(LucideIcons.navigation, size: 14),
            label: const Text("Yo'nalish", style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
          )),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDelete,
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(8)),
              child: const Icon(LucideIcons.trash2, size: 16, color: Color(0xFFEF4444)),
            ),
          ),
        ]),
      ]),
    );
  }
}
