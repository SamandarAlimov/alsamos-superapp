import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/map_models.dart';
import '../../data/map_repository.dart';

final mapRepoProvider = Provider<MapRepository>((ref) => MapRepository());

/// Saved places synced with Supabase (saved_places + saved_place_lists).
class SavedPlacesState {
  final List<SavedPlace> recent;
  final List<SavedPlace> favorites;
  final List<String> listNames;
  final bool loading;
  const SavedPlacesState({this.recent = const [], this.favorites = const [], this.listNames = const ['Sevimlilar', 'Uy', 'Ish'], this.loading = false});
  SavedPlacesState copyWith({List<SavedPlace>? recent, List<SavedPlace>? favorites, List<String>? listNames, bool? loading}) =>
      SavedPlacesState(recent: recent ?? this.recent, favorites: favorites ?? this.favorites, listNames: listNames ?? this.listNames, loading: loading ?? this.loading);
}

class SavedPlacesNotifier extends StateNotifier<SavedPlacesState> {
  final MapRepository _repo;
  SavedPlacesNotifier(this._repo) : super(const SavedPlacesState(loading: true)) {
    _load();
  }

  Future<void> _load() async {
    final places = await _repo.fetchSavedPlaces();
    state = SavedPlacesState(
      recent: places.where((p) => !p.isFavorite).take(10).toList(),
      favorites: places.where((p) => p.isFavorite).toList(),
    );
  }

  Future<void> addRecent(SavedPlace place) async {
    final filtered = state.recent.where((p) => p.lat != place.lat || p.lng != place.lng).toList();
    final updated = [place.copyWith(), ...filtered].take(10).toList();
    state = state.copyWith(recent: updated);
    await _repo.savePlaceToSupabase(place);
  }

  Future<void> toggleFavorite(SavedPlace place) async {
    final exists = state.favorites.any((p) => p.id == place.id);
    if (exists) {
      state = state.copyWith(favorites: state.favorites.where((p) => p.id != place.id).toList());
      await _repo.deleteSavedPlace(place.id);
    } else {
      final updated = place.copyWith(isFavorite: true);
      state = state.copyWith(favorites: [...state.favorites, updated]);
      await _repo.savePlaceToSupabase(SavedPlace(id: place.id, name: place.name, lat: place.lat, lng: place.lng, isFavorite: true));
    }
  }

  bool isFavorite(String id) => state.favorites.any((p) => p.id == id);

  Future<void> clearRecent() async {
    state = state.copyWith(recent: const []);
  }

  Future<void> deletePlace(String id) async {
    state = state.copyWith(
      recent: state.recent.where((p) => p.id != id).toList(),
      favorites: state.favorites.where((p) => p.id != id).toList(),
    );
    await _repo.deleteSavedPlace(id);
  }
}

final savedPlacesProvider = StateNotifierProvider<SavedPlacesNotifier, SavedPlacesState>((ref) => SavedPlacesNotifier(ref.read(mapRepoProvider)));

/// Frequent places + daily routes (Supabase-backed) for the LocationHistory panel.
class LocationHistoryState {
  final bool loading;
  final List<FrequentPlace> frequentPlaces;
  final List<DailyRoute> dailyRoutes;
  final DailyRoute? todayRoute;
  const LocationHistoryState({this.loading = true, this.frequentPlaces = const [], this.dailyRoutes = const [], this.todayRoute});
  LocationHistoryState copyWith({bool? loading, List<FrequentPlace>? frequentPlaces, List<DailyRoute>? dailyRoutes, DailyRoute? todayRoute, bool clearToday = false}) =>
      LocationHistoryState(
        loading: loading ?? this.loading,
        frequentPlaces: frequentPlaces ?? this.frequentPlaces,
        dailyRoutes: dailyRoutes ?? this.dailyRoutes,
        todayRoute: clearToday ? null : (todayRoute ?? this.todayRoute),
      );
}

class LocationHistoryNotifier extends StateNotifier<LocationHistoryState> {
  final MapRepository _repo;
  LocationHistoryNotifier(this._repo) : super(const LocationHistoryState()) {
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true);
    final results = await Future.wait<Object?>([
      _repo.fetchFrequentPlaces(),
      _repo.fetchDailyRoutes(limit: 30),
      _repo.fetchTodayRoute(),
    ]);
    state = LocationHistoryState(
      loading: false,
      frequentPlaces: (results[0] as List<FrequentPlace>?) ?? const [],
      dailyRoutes: (results[1] as List<DailyRoute>?) ?? const [],
      todayRoute: results[2] as DailyRoute?,
    );
  }

  Future<void> updateName(String id, String name) async {
    await _repo.updatePlaceName(id, name);
    state = state.copyWith(
      frequentPlaces: state.frequentPlaces
          .map((p) => p.id == id
              ? FrequentPlace(
                  id: p.id,
                  userId: p.userId,
                  name: name,
                  placeType: p.placeType,
                  latitude: p.latitude,
                  longitude: p.longitude,
                  address: p.address,
                  averageStayMinutes: p.averageStayMinutes,
                  visitCount: p.visitCount,
                  lastVisitedAt: p.lastVisitedAt,
                  isAutoDetected: p.isAutoDetected,
                  confidenceScore: p.confidenceScore,
                  createdAt: p.createdAt,
                  updatedAt: p.updatedAt,
                )
              : p)
          .toList(),
    );
  }

  Future<void> delete(String id) async {
    await _repo.deletePlace(id);
    state = state.copyWith(frequentPlaces: state.frequentPlaces.where((p) => p.id != id).toList());
  }

  double getTotalDistance(int days) {
    final since = DateTime.now().subtract(Duration(days: days));
    double total = 0;
    for (final r in state.dailyRoutes) {
      try {
        final dt = DateTime.parse(r.routeDate);
        if (dt.isAfter(since)) total += r.totalDistanceKm;
      } catch (_) {}
    }
    return total;
  }
}

final locationHistoryProvider =
    StateNotifierProvider<LocationHistoryNotifier, LocationHistoryState>((ref) => LocationHistoryNotifier(ref.read(mapRepoProvider)));

/// Step history (auto-fetched on creation).
final stepHistoryProvider = FutureProvider.autoDispose.family<List<StepDataPoint>, int>((ref, days) async {
  final repo = ref.read(mapRepoProvider);
  return repo.fetchStepHistory(days: days);
});

/// Directions panel state (origin/destination/routes).
class DirectionsState {
  final ({double lat, double lng, String name})? origin;
  final ({double lat, double lng, String name})? destination;
  final List<RouteAlternative> routes;
  final int selectedRouteIndex;
  final bool loading;
  final String? error;
  final bool navigating;
  final int currentStepIndex;
  const DirectionsState({
    this.origin,
    this.destination,
    this.routes = const [],
    this.selectedRouteIndex = 0,
    this.loading = false,
    this.error,
    this.navigating = false,
    this.currentStepIndex = 0,
  });
  DirectionsState copyWith({
    Object? origin = _u,
    Object? destination = _u,
    List<RouteAlternative>? routes,
    int? selectedRouteIndex,
    bool? loading,
    Object? error = _u,
    bool? navigating,
    int? currentStepIndex,
  }) =>
      DirectionsState(
        origin: identical(origin, _u) ? this.origin : origin as ({double lat, double lng, String name})?,
        destination: identical(destination, _u) ? this.destination : destination as ({double lat, double lng, String name})?,
        routes: routes ?? this.routes,
        selectedRouteIndex: selectedRouteIndex ?? this.selectedRouteIndex,
        loading: loading ?? this.loading,
        error: identical(error, _u) ? this.error : error as String?,
        navigating: navigating ?? this.navigating,
        currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      );
  RouteAlternative? get selectedRoute => routes.isEmpty ? null : routes[selectedRouteIndex.clamp(0, routes.length - 1)];
  RouteStep? get currentStep {
    final r = selectedRoute;
    if (r == null || r.steps.isEmpty) return null;
    return r.steps[currentStepIndex.clamp(0, r.steps.length - 1)];
  }
}

const Object _u = Object();

class DirectionsNotifier extends StateNotifier<DirectionsState> {
  final MapRepository _repo;
  DirectionsNotifier(this._repo) : super(const DirectionsState());

  void setOrigin(({double lat, double lng, String name})? v) => state = state.copyWith(origin: v);
  void setDestination(({double lat, double lng, String name})? v) => state = state.copyWith(destination: v);
  void selectRoute(int index) => state = state.copyWith(selectedRouteIndex: index, currentStepIndex: 0);

  Future<List<RouteAlternative>> calculate(TransportMode mode) async {
    final o = state.origin;
    final d = state.destination;
    if (o == null || d == null) return const [];
    state = state.copyWith(loading: true, error: null);
    final routes = await _repo.calculateRoute(
      origin: LatLng(o.lat, o.lng),
      destination: LatLng(d.lat, d.lng),
      mode: mode,
    );
    state = state.copyWith(routes: routes, selectedRouteIndex: 0, loading: false, currentStepIndex: 0, error: routes.isEmpty ? "Yo'l topilmadi" : null);
    return routes;
  }

  void startNavigation() => state = state.copyWith(navigating: true, currentStepIndex: 0);
  void stopNavigation() => state = state.copyWith(navigating: false, currentStepIndex: 0);
  void nextStep() {
    final r = state.selectedRoute;
    if (r == null) return;
    if (state.currentStepIndex < r.steps.length - 1) {
      state = state.copyWith(currentStepIndex: state.currentStepIndex + 1);
    }
  }
  void prevStep() {
    if (state.currentStepIndex > 0) state = state.copyWith(currentStepIndex: state.currentStepIndex - 1);
  }

  void clearRoute() => state = const DirectionsState();
}

final directionsProvider =
    StateNotifierProvider<DirectionsNotifier, DirectionsState>((ref) => DirectionsNotifier(ref.read(mapRepoProvider)));
