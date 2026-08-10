import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/map_models.dart';
import '../../data/map_repository.dart';
import '../../data/overpass_client.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Layer Toggle State
// ═══════════════════════════════════════════════════════════════════════════
class MapLayersConfig {
  final bool showPOIs;
  final Set<POICategory> poiCategories;
  final bool showMarketplace;
  final bool showEvents;
  final bool showSocialPosts;
  final bool showTaxis;
  final bool showIncidents;

  const MapLayersConfig({
    this.showPOIs = false,
    this.poiCategories = const {},
    this.showMarketplace = false,
    this.showEvents = false,
    this.showSocialPosts = false,
    this.showTaxis = false,
    this.showIncidents = false,
  });

  MapLayersConfig copyWith({
    bool? showPOIs,
    Set<POICategory>? poiCategories,
    bool? showMarketplace,
    bool? showEvents,
    bool? showSocialPosts,
    bool? showTaxis,
    bool? showIncidents,
  }) =>
      MapLayersConfig(
        showPOIs: showPOIs ?? this.showPOIs,
        poiCategories: poiCategories ?? this.poiCategories,
        showMarketplace: showMarketplace ?? this.showMarketplace,
        showEvents: showEvents ?? this.showEvents,
        showSocialPosts: showSocialPosts ?? this.showSocialPosts,
        showTaxis: showTaxis ?? this.showTaxis,
        showIncidents: showIncidents ?? this.showIncidents,
      );
}

class MapLayersConfigNotifier extends StateNotifier<MapLayersConfig> {
  MapLayersConfigNotifier() : super(const MapLayersConfig());

  void togglePOIs(bool show) => state = state.copyWith(showPOIs: show);
  void setPOICategories(Set<POICategory> cats) => state = state.copyWith(poiCategories: cats);
  void toggleMarketplace(bool show) => state = state.copyWith(showMarketplace: show);
  void toggleEvents(bool show) => state = state.copyWith(showEvents: show);
  void toggleSocialPosts(bool show) => state = state.copyWith(showSocialPosts: show);
  void toggleTaxis(bool show) => state = state.copyWith(showTaxis: show);
  void toggleIncidents(bool show) => state = state.copyWith(showIncidents: show);
}

final mapLayersConfigProvider = StateNotifierProvider<MapLayersConfigNotifier, MapLayersConfig>(
  (ref) => MapLayersConfigNotifier(),
);

// ═══════════════════════════════════════════════════════════════════════════
// POI Layer Provider
// ═══════════════════════════════════════════════════════════════════════════
class POILayerState {
  final List<MapPOI> pois;
  final bool loading;
  final String? error;

  const POILayerState({
    this.pois = const [],
    this.loading = false,
    this.error,
  });

  POILayerState copyWith({List<MapPOI>? pois, bool? loading, String? error}) =>
      POILayerState(pois: pois ?? this.pois, loading: loading ?? this.loading, error: error);
}

class POILayerNotifier extends StateNotifier<POILayerState> {
  final OverpassClient _client;
  Timer? _debounce;

  POILayerNotifier(this._client) : super(const POILayerState());

  void fetchPOIs({
    required LatLng center,
    required double radiusKm,
    required Set<POICategory> categories,
  }) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (categories.isEmpty) {
        state = const POILayerState(pois: []);
        return;
      }
      state = state.copyWith(loading: true);
      try {
        final pois = await _client.fetchPOIs(
          center: center,
          radiusKm: radiusKm,
          categories: categories,
        );
        state = POILayerState(pois: pois, loading: false);
      } catch (e) {
        state = POILayerState(loading: false, error: e.toString());
      }
    });
  }

  void clear() {
    _debounce?.cancel();
    state = const POILayerState();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final poiLayerProvider = StateNotifierProvider<POILayerNotifier, POILayerState>(
  (ref) => POILayerNotifier(OverpassClient()),
);

// ═══════════════════════════════════════════════════════════════════════════
// Cross-Feature Markers Provider
// ═══════════════════════════════════════════════════════════════════════════
class CrossFeatureMarkersState {
  final List<MarketplaceMapMarker> marketplace;
  final List<EventMapMarker> events;
  final List<SocialPostMapMarker> socialPosts;
  final bool loading;

  const CrossFeatureMarkersState({
    this.marketplace = const [],
    this.events = const [],
    this.socialPosts = const [],
    this.loading = false,
  });

  CrossFeatureMarkersState copyWith({
    List<MarketplaceMapMarker>? marketplace,
    List<EventMapMarker>? events,
    List<SocialPostMapMarker>? socialPosts,
    bool? loading,
  }) =>
      CrossFeatureMarkersState(
        marketplace: marketplace ?? this.marketplace,
        events: events ?? this.events,
        socialPosts: socialPosts ?? this.socialPosts,
        loading: loading ?? this.loading,
      );
}

class CrossFeatureMarkersNotifier extends StateNotifier<CrossFeatureMarkersState> {
  final MapRepository _repo;
  Timer? _debounce;

  CrossFeatureMarkersNotifier(this._repo) : super(const CrossFeatureMarkersState());

  void fetchMarkers({
    required double south,
    required double west,
    required double north,
    required double east,
    required MapLayersConfig config,
  }) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      state = state.copyWith(loading: true);
      final futures = <Future<Object?>>[];
      if (config.showMarketplace) {
        futures.add(_repo.fetchMarketplaceMarkers(south: south, west: west, north: north, east: east));
      }
      if (config.showEvents) {
        futures.add(_repo.fetchEventMarkers(south: south, west: west, north: north, east: east));
      }
      if (config.showSocialPosts) {
        futures.add(_repo.fetchSocialPostMarkers(south: south, west: west, north: north, east: east));
      }

      if (futures.isEmpty) {
        state = const CrossFeatureMarkersState();
        return;
      }

      final results = await Future.wait(futures);
      var idx = 0;
      state = CrossFeatureMarkersState(
        marketplace: config.showMarketplace && idx < results.length ? results[idx++] as List<MarketplaceMapMarker> : const [],
        events: config.showEvents && idx < results.length ? results[idx++] as List<EventMapMarker> : const [],
        socialPosts: config.showSocialPosts && idx < results.length ? results[idx++] as List<SocialPostMapMarker> : const [],
        loading: false,
      );
    });
  }

  void clear() {
    _debounce?.cancel();
    state = const CrossFeatureMarkersState();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final crossFeatureMarkersProvider = StateNotifierProvider<CrossFeatureMarkersNotifier, CrossFeatureMarkersState>(
  (ref) => CrossFeatureMarkersNotifier(MapRepository()),
);

// ═══════════════════════════════════════════════════════════════════════════
// Taxi Live Layer Provider (Realtime)
// ═══════════════════════════════════════════════════════════════════════════
class TaxiLayerState {
  final List<TaxiDriverMarker> drivers;
  final bool connected;
  final String? error;

  const TaxiLayerState({
    this.drivers = const [],
    this.connected = false,
    this.error,
  });

  TaxiLayerState copyWith({List<TaxiDriverMarker>? drivers, bool? connected, String? error}) =>
      TaxiLayerState(drivers: drivers ?? this.drivers, connected: connected ?? this.connected, error: error);
}

class TaxiLayerNotifier extends StateNotifier<TaxiLayerState> {
  final MapRepository _repo;
  RealtimeChannel? _channel;

  TaxiLayerNotifier(this._repo) : super(const TaxiLayerState());

  Future<void> subscribe() async {
    try {
      // Fetch initial data
      final initial = await _repo.fetchTaxiMarkers();
      state = TaxiLayerState(drivers: initial, connected: false);

      // Subscribe to realtime updates
      _channel = Supabase.instance.client.channel('taxi_live_locations').onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'taxi_live_locations',
        callback: (payload) async {
          // Refetch on any change
          final updated = await _repo.fetchTaxiMarkers();
          if (mounted) {
            state = TaxiLayerState(drivers: updated, connected: true);
          }
        },
      ).subscribe();
      state = state.copyWith(connected: true);
    } catch (e) {
      state = TaxiLayerState(error: e.toString());
    }
  }

  void unsubscribe() {
    _channel?.unsubscribe();
    _channel = null;
    state = const TaxiLayerState();
  }

  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }
}

final taxiLayerProvider = StateNotifierProvider<TaxiLayerNotifier, TaxiLayerState>(
  (ref) => TaxiLayerNotifier(MapRepository()),
);
