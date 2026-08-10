import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../data/map_models.dart';
import '../../data/overpass_client.dart';
import '../providers/location_provider.dart';
import '../providers/map_layers_provider.dart';

/// Clustered markers for user locations (nearby + following), de-duplicated by userId.
Widget buildUserMarkersLayer({
  required LocationState locSt,
  required bool showNearby,
  required bool showFollowing,
  required Color primary,
  required Function(UserLocationData) onUserTap,
}) {
  // Merge nearby + following into a single map keyed by userId (dedup)
  final users = <String, UserLocationData>{};
  if (showNearby) {
    for (final u in locSt.nearbyUsers) {
      users[u.userId] = u;
    }
  }
  if (showFollowing) {
    for (final u in locSt.followingUsers) {
      // Prefer the following entry if a user is in both lists (better priority)
      users[u.userId] = u;
    }
  }

  final markers = <Marker>[];
  for (final u in users.values) {
    final prof = u.profile;
    if (prof == null) continue;

    Widget avatar;
    if (prof.avatarUrl != null) {
      avatar = ClipOval(
        child: Image.network(
          prof.avatarUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Center(
            child: Text(
              prof.displayName.isNotEmpty ? prof.displayName[0].toUpperCase() : '?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: primary),
            ),
          ),
        ),
      );
    } else {
      avatar = Center(
        child: Text(
          prof.displayName.isNotEmpty ? prof.displayName[0].toUpperCase() : '?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: primary),
        ),
      );
    }

    markers.add(Marker(
      point: LatLng(u.latitude, u.longitude),
      width: 48,
      height: 48,
      child: GestureDetector(
        onTap: () => onUserTap(u),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: primary, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: avatar,
            ),
            if (prof.isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    ));
  }

  return MarkerClusterLayerWidget(
    options: MarkerClusterLayerOptions(
      maxClusterRadius: 80,
      size: const Size(48, 48),
      markers: markers,
      builder: (context, markers) {
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primary,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Text(
              '${markers.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// POI markers layer (restaurants, gas, ATM, etc)
class POIMarkersLayer extends ConsumerWidget {
  final LatLng center;
  final double zoom;
  final Function(MapPOI) onPOITap;

  const POIMarkersLayer({
    super.key,
    required this.center,
    required this.zoom,
    required this.onPOITap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(mapLayersConfigProvider);
    final poiState = ref.watch(poiLayerProvider);

    // Trigger fetch when config or viewport changes
    ref.listen(mapLayersConfigProvider, (prev, next) {
      if (next.showPOIs && next.poiCategories.isNotEmpty) {
        ref.read(poiLayerProvider.notifier).fetchPOIs(
              center: center,
              radiusKm: _radiusFromZoom(zoom),
              categories: next.poiCategories,
            );
      } else {
        ref.read(poiLayerProvider.notifier).clear();
      }
    });

    if (!config.showPOIs || poiState.pois.isEmpty) {
      return const SizedBox.shrink();
    }

    final markers = poiState.pois.map((poi) {
      return Marker(
        point: LatLng(poi.latitude, poi.longitude),
        width: 40,
        height: 50,
        child: GestureDetector(
          onTap: () => onPOITap(poi),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _categoryColor(poi.category),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(poi.category.icon, size: 18),
              ),
              const SizedBox(height: 2),
              Container(
                width: 2,
                height: 10,
                color: _categoryColor(poi.category),
              ),
            ],
          ),
        ),
      );
    }).toList();

    return MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        maxClusterRadius: 60,
        size: const Size(40, 40),
        markers: markers,
        builder: (context, markers) {
          return Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF97316),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '${markers.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  double _radiusFromZoom(double zoom) {
    if (zoom >= 16) return 0.5;
    if (zoom >= 14) return 1.0;
    if (zoom >= 12) return 2.0;
    return 5.0;
  }

  Color _categoryColor(POICategory category) {
    switch (category) {
      case POICategory.restaurant:
      case POICategory.cafe:
      case POICategory.fastFood:
        return const Color(0xFFEF4444);
      case POICategory.gas:
        return const Color(0xFF10B981);
      case POICategory.atm:
      case POICategory.bank:
        return const Color(0xFF3B82F6);
      case POICategory.pharmacy:
      case POICategory.hospital:
        return const Color(0xFFEC4899);
      case POICategory.shop:
        return const Color(0xFFF59E0B);
    }
  }
}

/// Cross-feature markers (Marketplace, Events, Social Posts)
class CrossFeatureMarkersLayer extends ConsumerWidget {
  final LatLngBounds bounds;
  final Function(String type, String id) onMarkerTap;

  const CrossFeatureMarkersLayer({
    super.key,
    required this.bounds,
    required this.onMarkerTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(mapLayersConfigProvider);
    final state = ref.watch(crossFeatureMarkersProvider);

    // Trigger fetch when config or bounds change
    ref.listen(mapLayersConfigProvider, (prev, next) {
      if (next.showMarketplace || next.showEvents || next.showSocialPosts) {
        ref.read(crossFeatureMarkersProvider.notifier).fetchMarkers(
              south: bounds.south,
              west: bounds.west,
              north: bounds.north,
              east: bounds.east,
              config: next,
            );
      }
    });

    final markers = <Marker>[];

    // Marketplace markers
    if (config.showMarketplace) {
      for (final m in state.marketplace) {
        markers.add(Marker(
          point: LatLng(m.latitude, m.longitude),
          width: 44,
          height: 54,
          child: GestureDetector(
            onTap: () => onMarkerTap('marketplace', m.id),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    LucideIcons.shoppingBag,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 2,
                  height: 10,
                  color: const Color(0xFF8B5CF6),
                ),
              ],
            ),
          ),
        ));
      }
    }

    // Event markers
    if (config.showEvents) {
      for (final e in state.events) {
        markers.add(Marker(
          point: LatLng(e.latitude, e.longitude),
          width: 44,
          height: 54,
          child: GestureDetector(
            onTap: () => onMarkerTap('event', e.id),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    LucideIcons.calendar,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 2,
                  height: 10,
                  color: const Color(0xFFF59E0B),
                ),
              ],
            ),
          ),
        ));
      }
    }

    // Social post markers
    if (config.showSocialPosts) {
      for (final p in state.socialPosts) {
        markers.add(Marker(
          point: LatLng(p.latitude, p.longitude),
          width: 44,
          height: 54,
          child: GestureDetector(
            onTap: () => onMarkerTap('social', p.id),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF06B6D4),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: p.authorAvatar != null
                      ? ClipOval(
                          child: Image.network(p.authorAvatar!, fit: BoxFit.cover),
                        )
                      : const Icon(
                          LucideIcons.messageCircle,
                          color: Colors.white,
                          size: 20,
                        ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 2,
                  height: 10,
                  color: const Color(0xFF06B6D4),
                ),
              ],
            ),
          ),
        ));
      }
    }

    if (markers.isEmpty) return const SizedBox.shrink();

    return MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        maxClusterRadius: 50,
        size: const Size(44, 44),
        markers: markers,
        builder: (context, markers) {
          return Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF6366F1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Center(
              child: Text(
                '${markers.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Taxi live markers layer
class TaxiMarkersLayer extends ConsumerWidget {
  final Function(TaxiDriverMarker) onTaxiTap;

  const TaxiMarkersLayer({
    super.key,
    required this.onTaxiTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(mapLayersConfigProvider);
    final state = ref.watch(taxiLayerProvider);

    // Subscribe/unsubscribe based on toggle
    ref.listen(mapLayersConfigProvider, (prev, next) {
      if (next.showTaxis && !state.connected) {
        ref.read(taxiLayerProvider.notifier).subscribe();
      } else if (!next.showTaxis && state.connected) {
        ref.read(taxiLayerProvider.notifier).unsubscribe();
      }
    });

    if (!config.showTaxis || state.drivers.isEmpty) {
      return const SizedBox.shrink();
    }

    final markers = state.drivers.map((taxi) {
      return Marker(
        point: LatLng(taxi.latitude, taxi.longitude),
        width: 44,
        height: 54,
        rotate: true,
        child: GestureDetector(
          onTap: () => onTaxiTap(taxi),
          child: Transform.rotate(
            angle: (taxi.heading ?? 0) * 3.14159 / 180,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBBF24),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    LucideIcons.car,
                    color: Colors.black,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 2,
                  height: 10,
                  color: const Color(0xFFFBBF24),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();

    return MarkerLayer(markers: markers);
  }
}
