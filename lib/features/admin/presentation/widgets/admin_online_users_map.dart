import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';

/// Ported from src/components/admin/AdminOnlineUsersMap.tsx.
/// CARTO dark tiles + circle markers + country sidebar + realtime updates +
/// 10s polling tick.
class AdminOnlineUsersMap extends StatefulWidget {
  const AdminOnlineUsersMap({super.key});

  @override
  State<AdminOnlineUsersMap> createState() => _AdminOnlineUsersMapState();
}

class _AdminOnlineUsersMapState extends State<AdminOnlineUsersMap> {
  final AdminRepository _repo = AdminRepository();
  List<OnlineUser> _users = const [];
  List<OnlineCountry> _countries = const [];
  bool _loading = true;
  Timer? _tick;
  RealtimeChannel? _channel;
  String? _expanded;

  @override
  void initState() {
    super.initState();
    _refresh();
    _tick = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    _channel = supabase
        .channel('admin-online-users')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          callback: (_) => _refresh(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _tick?.cancel();
    final ch = _channel;
    if (ch != null) supabase.removeChannel(ch);
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final list = await _repo.fetchOnlineUsers();
      if (!mounted) return;
      setState(() {
        _users = list;
        _countries = _repo.groupByCountry(list);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _radius(int count) {
    if (count >= 100) return 30;
    if (count >= 50) return 25;
    if (count >= 20) return 20;
    if (count >= 10) return 15;
    if (count >= 5) return 12;
    return 8;
  }

  Color _markerColor(int count, Color primary) {
    if (count >= 50) return const Color(0xFFEF4444);
    if (count >= 20) return const Color(0xFF22C55E);
    if (count >= 10) return const Color(0xFF3B82F6);
    return primary;
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(children: [
              Icon(LucideIcons.mapPin, size: 18, color: c.foreground),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Real-time foydalanuvchilar xaritasi',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF22C55E),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_users.length} online',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF22C55E),
                    ),
                  ),
                ]),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Yangilash',
                onPressed: _refresh,
                icon: Icon(LucideIcons.refreshCw,
                    size: 16, color: c.mutedForeground),
              ),
            ]),
          ),
          SizedBox(
            height: 380,
            child: LayoutBuilder(builder: (ctx, box) {
              final compact = box.maxWidth < 720;
              final map = Stack(
                children: [
                  FlutterMap(
                    options: const MapOptions(
                      initialCenter: LatLng(20, 0),
                      initialZoom: 2,
                      minZoom: 1.5,
                      maxZoom: 8,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                        subdomains: const ['a', 'b', 'c', 'd'],
                        userAgentPackageName: 'com.alsamos.superapp',
                      ),
                      CircleLayer(
                        circles: _countries.map((c0) {
                          final color = _markerColor(c0.count, primary);
                          return CircleMarker(
                            point: LatLng(c0.lat, c0.lng),
                            radius: _radius(c0.count),
                            color: color.withValues(alpha: 0.45),
                            borderColor: color,
                            borderStrokeWidth: 2,
                            useRadiusInMeter: false,
                          );
                        }).toList(),
                      ),
                      MarkerLayer(
                        markers: _countries.map((c0) {
                          return Marker(
                            point: LatLng(c0.lat, c0.lng),
                            width: 40,
                            height: 22,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${c0.count}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Foydalanuvchilar soni',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _legendRow(const Color(0xFFEF4444), '50+'),
                          _legendRow(const Color(0xFF22C55E), '20-49'),
                          _legendRow(const Color(0xFF3B82F6), '10-19'),
                          _legendRow(primary, '1-9'),
                        ],
                      ),
                    ),
                  ),
                  if (_loading)
                    const Positioned(
                      top: 12,
                      right: 12,
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              );

              final sidebar = _CountriesPanel(
                c: c,
                countries: _countries,
                expanded: _expanded,
                onTap: (k) => setState(
                    () => _expanded = _expanded == k ? null : k),
              );

              if (compact) {
                return Column(children: [
                  Expanded(child: map),
                  SizedBox(
                    height: 140,
                    child: sidebar,
                  ),
                ]);
              }
              return Row(children: [
                Expanded(child: map),
                SizedBox(
                  width: 260,
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.background,
                      border: Border(left: BorderSide(color: c.border)),
                    ),
                    child: sidebar,
                  ),
                ),
              ]);
            }),
          ),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 10)),
      ]),
    );
  }
}

class _CountriesPanel extends StatelessWidget {
  final AlsamosColors c;
  final List<OnlineCountry> countries;
  final String? expanded;
  final ValueChanged<String> onTap;

  const _CountriesPanel({
    required this.c,
    required this.countries,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (countries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            "Hozircha onlayn foydalanuvchilar yo'q",
            textAlign: TextAlign.center,
            style: TextStyle(color: c.mutedForeground, fontSize: 12),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      itemCount: countries.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Row(children: [
              Icon(LucideIcons.globe, size: 14, color: c.mutedForeground),
              const SizedBox(width: 6),
              Text(
                "Davlatlar bo'yicha",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.mutedForeground,
                ),
              ),
            ]),
          );
        }
        final ctry = countries[i - 1];
        final isOpen = expanded == ctry.country;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: c.card,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onTap(ctry.country),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      ctry.country,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${ctry.count}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF22C55E),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            if (isOpen)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: Column(
                  children: [
                    for (final u in ctry.users.take(5))
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          UserAvatar(
                            avatarUrl: u.avatarUrl,
                            fallback: ((u.username ?? '?')
                                .characters
                                .firstOrNull ??
                                '?')
                                .toUpperCase(),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              u.displayName ??
                                  u.username ??
                                  'user',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ]),
                      ),
                    if (ctry.users.length > 5)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '+${ctry.users.length - 5} more',
                          style: TextStyle(
                              fontSize: 11,
                              color: c.mutedForeground),
                        ),
                      ),
                  ],
                ),
              ),
          ]),
        );
      },
    );
  }
}
