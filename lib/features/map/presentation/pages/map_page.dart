// Map Page - Yandex-like professional map
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'dart:ui' as ui;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:flutter_map_compass/flutter_map_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/content/utils/content_metadata.dart';
import '../../data/map_models.dart';
import '../../data/overpass_client.dart';
import '../../utils/map_deep_links.dart';
import '../providers/location_provider.dart';
import '../providers/map_layers_provider.dart';
import '../providers/map_provider.dart';
import '../widgets/draggable_directions_sheet.dart';
import '../widgets/collapsible_directions_panel.dart';
import '../widgets/location_history_mobile_sheet.dart';
import '../widgets/location_history_panel.dart';
import '../widgets/map_marker_layers.dart';
import '../widgets/map_quick_actions.dart';
import '../widgets/step_tracking_charts.dart';
import '../widgets/transport_mode_picker.dart';
import '../../../../shared/services/connectivity_service.dart';
import '../../../../shared/widgets/app_toast.dart';

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});
  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage>
    with TickerProviderStateMixin {
  static const _initialCenter = LatLng(41.2995, 69.2401);

  final _mapCtrl   = MapController();
  final _searchCtrl = TextEditingController();
  late final TabController _tab;
  final _battery   = Battery();
  StreamSubscription<bool>? _connSub;

  // Map state
  LatLng  _center    = _initialCenter;
  bool _hasCenteredOnUser = false;
  double  _zoom      = 15;
  MapLayer _layer    = MapLayer.standard;
  TransportMode _transport = TransportMode.driving;

  // Animated zoom
  AnimationController? _zoomAnim;
  double _zoomAnimFrom = 0;
  double _zoomAnimTo = 0;

  // Debounce for position changes
  Timer? _posDebounce;

  // Keyboard focus node
  final _mapFocusNode = FocusNode();

  // UI state
  bool _sidebarOpen         = true;
  bool _showDirectionsPanel = false; // desktop only
  bool _directionsPanelCollapsed = false; // desktop collapse state
  bool _showDirMobile       = false; // mobile sheet
  SheetSnapState _mobileSheetState = SheetSnapState.half; // mobile sheet state
  bool _showHistoryMobile   = false; // mobile history sheet
  bool _showNearby          = true;
  bool _showFollowing       = true;
  bool _showFreqPlaces      = true;
  bool _showRadiusCircle    = true;
  bool _isLocationPrivate   = false;
  double _nearbyRadius      = 1; // km — default 1km like Yandex

  // Active route polyline on map
  List<LatLng>? _activeRoute;
  DailyRoute?   _viewingRoute;

  // Destination for directions
  ({double lat, double lng, String name})? _destination;

  // Map selection mode for DirectionsPanel
  String? _mapSelectionMode;
  ({double lat, double lng, String name})? _selectedMapLoc;

  // Battery + online
  int  _batteryLevel = 100;
  bool _isOnline      = true;

  // Supabase Presence (who's on map now)
  List<Map<String, dynamic>> _usersOnMap = [];
  RealtimeChannel? _presenceChannel;

  // Sidebar search
  List<SearchResult> _searchResults = [];
  bool _isSearchingMap = false;
  Timer? _searchDebounce;

  // ── Yandex-like features ────────────────────────────────────────────────
  // Long-press selected point
  LatLng? _longPressPoint;

  // Voice navigation (TTS)
  final FlutterTts _tts = FlutterTts();
  bool _voiceEnabled = true;

  // Route animation
  Timer? _routeAnimTimer;

  // Traffic layer toggle
  bool _showTraffic = false;

  // Location tracking path (bread-crumb trail)
  final List<LatLng> _trackingPath = [];

  // Cached tile provider with connection limits
  late final CachedTileProvider _cachedTileProvider;
  late final Dio _tileDio;

  // Compass heading
  double _compassHeading = 0;

  static const _stepGoal = 10000;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _initTileProvider();
    _initBattery();
    _initConnectivity();
    _initTts();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initMap());
  }

  void _initTileProvider() {
    _tileDio = Dio()
      ..httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.maxConnectionsPerHost = 4;
          return client;
        },
      );
    _cachedTileProvider = CachedTileProvider(
      store: MemCacheStore(maxSize: 209715200),
      dio: _tileDio,
      maxStale: const Duration(days: 30),
    );
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('uz-UZ');
      await _tts.setSpeechRate(0.9);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (_) {
      try {
        await _tts.setLanguage('ru-RU');
      } catch (_) {}
    }
  }

  Future<void> _speakInstruction(String text) async {
    if (!_voiceEnabled) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> _initBattery() async {
    try {
      final lvl = await _battery.batteryLevel;
      if (mounted) setState(() => _batteryLevel = lvl);
      _battery.onBatteryStateChanged.listen((_) async {
        final lvl = await _battery.batteryLevel;
        if (mounted) setState(() => _batteryLevel = lvl);
      });
    } catch (_) {}
  }

  void _initConnectivity() {
    final svc = ref.read(connectivityServiceProvider);
    _isOnline = svc.isOnlineNow;
    _connSub = svc.onlineStream.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  Future<void> _initMap() async {
    await ref.read(locationProvider.notifier).startTracking();

    // Check for deep link query params (alsamos://map?lat=...&lng=...&z=...)
    final qp = GoRouterState.of(context).uri.queryParameters;
    final deepLat = double.tryParse(qp['lat'] ?? '');
    final deepLng = double.tryParse(qp['lng'] ?? '');
    final deepZoom = double.tryParse(qp['z'] ?? '');

    if (deepLat != null && deepLng != null && mounted) {
      final loc = LatLng(deepLat, deepLng);
      final z = deepZoom?.clamp(3.0, 19.0) ?? 15;
      setState(() { _center = loc; _zoom = z; });
      try { _mapCtrl.move(loc, z); } catch (_) {}
      return;
    }

      final pos = ref.read(locationProvider).currentPosition;
    if (pos != null && mounted && !_hasCenteredOnUser) {
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() { _center = loc; _zoom = 15; _hasCenteredOnUser = true; });
      try { _mapCtrl.move(loc, 15); } catch (_) {}
    }
    // setup Supabase presence (who's viewing map)
    _setupPresence();
    // periodic nearby refresh
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isOnline) {
        ref.read(locationProvider.notifier).fetchNearbyUsers(radiusKm: _nearbyRadius);
        ref.read(locationProvider.notifier).fetchFollowingUsers();
      }
    });
  }

  void _setupPresence() {
    final supa = Supabase.instance.client;
    final uid  = supa.auth.currentUser?.id;
    if (uid == null) return;

    _presenceChannel = supa.channel('map-presence', opts: const RealtimeChannelConfig(key: ''))
      .onPresenceSync((_) {
        try {
          final states = _presenceChannel?.presenceState() ?? [];
          final users = <Map<String, dynamic>>[];
          for (final state in states) {
            if (state.key == uid || state.presences.isEmpty) continue;
            final payload = state.presences.first.payload;
            users.add({'user_id': state.key, ...payload});
          }
          if (mounted) setState(() => _usersOnMap = users);
        } catch (_) {}
      })
      .subscribe((status, [_]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          final prof = supa.auth.currentUser;
          await _presenceChannel?.track({
            'user_id': uid,
            'online_at': DateTime.now().toIso8601String(),
            'display_name': prof?.userMetadata?['display_name'],
            'avatar_url':   prof?.userMetadata?['avatar_url'],
          });
        }
      });
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    _mapCtrl.dispose();
    _connSub?.cancel();
    _refreshTimer?.cancel();
    _searchDebounce?.cancel();
    _routeAnimTimer?.cancel();
    _zoomAnim?.dispose();
    _posDebounce?.cancel();
    _mapFocusNode.dispose();
    _tts.stop();
    _presenceChannel?.unsubscribe();
    super.dispose();
  }

  // ─── Tile URL ────────────────────────────────────────────────────────────
  String _tileUrl() {
    switch (_layer) {
      case MapLayer.satellite:
      case MapLayer.hybrid: // base = satellite, labels added separately
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case MapLayer.terrain:
        return 'https://a.tile.opentopomap.org/{z}/{x}/{y}.png';
      case MapLayer.standard:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
  }


  

  // ─── Animated zoom ───────────────────────────────────────────────────────
  void _animateZoom(double target) {
    final clamped = target.clamp(3.0, 19.0);
    if ((clamped - _zoom).abs() < 0.01) return;
    _zoomAnim?.stop();
    _zoomAnim?.dispose();
    _zoomAnimFrom = _zoom;
    _zoomAnimTo = clamped;
    _zoomAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))
      ..addListener(_onZoomFrame)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) { _zoomAnim?.dispose(); _zoomAnim = null; }
      })
      ..forward();
  }

  void _onZoomFrame() {
    if (_zoomAnim == null) return;
    final t = Curves.easeOut.transform(_zoomAnim!.value);
    _mapCtrl.move(_center, _zoomAnimFrom + (_zoomAnimTo - _zoomAnimFrom) * t);
  }

  // ─── Position-change debounce ────────────────────────────────────────────
  void _onMapMoved() {
    _posDebounce?.cancel();
    _posDebounce = Timer(const Duration(milliseconds: 400), () {
      // After the map settles, POI/marker layers re-cluster automatically
      // via their own Consumer rebuilds when positionChanged triggers setState.
    });
  }

  void _cycleLayer() => setState(() => _layer = MapLayer.values[(_layer.index + 1) % MapLayer.values.length]);

  // ─── Calculate bottom offset for floating buttons based on sheet state ──
  double _getBottomOffsetForSheet() {
    switch (_mobileSheetState) {
      case SheetSnapState.collapsed:
        return MediaQuery.of(context).size.height * 0.18 + 16;
      case SheetSnapState.half:
        return MediaQuery.of(context).size.height * 0.48 + 16;
      case SheetSnapState.expanded:
        return MediaQuery.of(context).size.height * 0.88 + 16;
    }
  }

  // ─── Center on current location ─────────────────────────────────────────
  void _centerOnMe() {
    final notifier = ref.read(locationProvider.notifier);
    final pos = ref.read(locationProvider).currentPosition;
    if (pos != null) {
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() { _center = loc; _zoom = 16; _hasCenteredOnUser = true; });
      _mapCtrl.move(loc, 16);
    } else {
      notifier.acquireForButton().then((newPos) {
        if (newPos != null && mounted) {
          final loc = LatLng(newPos.latitude, newPos.longitude);
          setState(() { _center = loc; _zoom = 16; _hasCenteredOnUser = true; });
          _mapCtrl.move(loc, 16);
        }
      });
    }
  }

  // ─── Handle map tap for location selection ──────────────────────────────
  Future<void> _onMapTap(TapPosition _, LatLng latLng) async {
    if (_mapSelectionMode == null) return;
    final name = await ref.read(mapRepoProvider).reverseGeocode(latLng.latitude, latLng.longitude);
    setState(() => _selectedMapLoc = (lat: latLng.latitude, lng: latLng.longitude, name: name));
    if (mounted) {
      AppToast.success(context, '${_mapSelectionMode == "origin" ? "Boshlangich nuqta" : "Manzil"} tanlandi: $name');
    }
  }

  // ─── Long press → Yandex-style point menu ───────────────────────────────
  Future<void> _onMapLongPress(TapPosition _, LatLng latLng) async {
    HapticFeedback.mediumImpact();
    setState(() => _longPressPoint = latLng);
    final address = await ref.read(mapRepoProvider).reverseGeocode(latLng.latitude, latLng.longitude);
    if (mounted) { _showLongPressMenu(latLng, address); }
  }

  void _showLongPressMenu(LatLng latLng, String address) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.border)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 8), width: 36, height: 4, decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [
            Icon(LucideIcons.mapPin, color: primary, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(address.split(',').first, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: c.foreground)),
              Text('${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}', style: TextStyle(fontSize: 11, color: c.mutedForeground)),
            ])),
          ])),
          const Divider(height: 1),
          Row(children: [
            _LongPressAction(icon: LucideIcons.navigation, label: "Yo'nalish", color: primary, onTap: () {
              Navigator.pop(ctx);
              setState(() {
                _destination = (lat: latLng.latitude, lng: latLng.longitude, name: address.split(',').first);
                _longPressPoint = null; _showDirMobile = true;
              });
            }),
            _LongPressAction(icon: LucideIcons.star, label: 'Saqlash', color: const Color(0xFFF59E0B), onTap: () {
              Navigator.pop(ctx);
              final repo = ref.read(mapRepoProvider);
              final uid = Supabase.instance.client.auth.currentUser?.id;
              if (uid == null) return;
              final place = SavedPlace(id: 'lp_${DateTime.now().millisecondsSinceEpoch}', name: address.split(',').first, lat: latLng.latitude, lng: latLng.longitude, isFavorite: true);
              repo.savePlaceToSupabase(place);
              ref.read(savedPlacesProvider.notifier).addRecent(place);
              AppToast.success(context, "Sevimlilarga qo'shildi");
            }),
            _LongPressAction(icon: LucideIcons.share2, label: 'Ulashish', color: const Color(0xFF3B82F6), onTap: () {
              Navigator.pop(ctx);
              shareLocation(lat: latLng.latitude, lng: latLng.longitude, name: address.split(',').first);
            }),
            _LongPressAction(icon: LucideIcons.mapPinOff, label: 'Belgi', color: const Color(0xFFEF4444), onTap: () {
              Navigator.pop(ctx);
              setState(() { _longPressPoint = null; });
            }),
          ]),
          Row(children: [
            _LongPressAction(icon: LucideIcons.car, label: 'Taksi chaqirish', color: const Color(0xFFFBBF24), onTap: () {
              Navigator.pop(ctx);
              setState(() {
                _destination = (lat: latLng.latitude, lng: latLng.longitude, name: address.split(',').first);
                _longPressPoint = null;
              });
              AppToast.info(context, 'Taksi buyurtmasi yuborildi');
            }),
            _LongPressAction(icon: LucideIcons.copy, label: 'Nusxalash', color: const Color(0xFF6366F1), onTap: () {
              Navigator.pop(ctx);
              final link = MapDeepLink(latitude: latLng.latitude, longitude: latLng.longitude, zoom: 16).toUri();
              Clipboard.setData(ClipboardData(text: '$address\n$link'));
              AppToast.success(context, 'Havola nusxalandi');
            }),
            _LongPressAction(icon: LucideIcons.mapPin, label: 'Joylashuvni o\'rnatish', color: const Color(0xFF22C55E), onTap: () {
              Navigator.pop(ctx);
              ref.read(locationProvider.notifier).setManualLocation(latLng.latitude, latLng.longitude);
              AppToast.success(context, 'Joylashuv o\'rnatildi');
              _longPressPoint = null;
            }),
          ]),
          const SizedBox(height: 8),
        ]),
      ),
    ).then((_) {
      if (mounted) setState(() => _longPressPoint = null);
    });
  }

  // ─── Animated route drawing (smooth draw-on effect) ─────────────────────
  void _showSocialPostSheet(String postId) {
    final marker = ref.read(crossFeatureMarkersProvider).socialPosts.where((post) => post.id == postId).cast<SocialPostMapMarker?>().firstWhere((post) => post != null, orElse: () => null);
    if (marker == null) {
      context.push('/post/$postId');
      return;
    }

    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final place = marker.locationName?.trim().isNotEmpty == true
        ? marker.locationName!
        : marker.locationAddress?.trim().isNotEmpty == true
            ? marker.locationAddress!
            : '${marker.latitude.toStringAsFixed(5)}, ${marker.longitude.toStringAsFixed(5)}';
    final previewText = stripPostMetadata(marker.content);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.border), boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 26, offset: const Offset(0, 12)),
          ]),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(999)))),
            Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: primary.withValues(alpha: 0.12),
                backgroundImage: marker.authorAvatar == null ? null : NetworkImage(marker.authorAvatar!),
                child: marker.authorAvatar == null ? Icon(LucideIcons.user, color: primary, size: 20) : null,
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(marker.authorName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.foreground, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(LucideIcons.mapPin, size: 13, color: c.mutedForeground),
                  const SizedBox(width: 4),
                  Expanded(child: Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.mutedForeground, fontSize: 12, fontWeight: FontWeight.w600))),
                ]),
              ])),
              IconButton(
                tooltip: 'Xaritada ko\'rsatish',
                onPressed: () {
                  Navigator.pop(ctx);
                  _mapCtrl.move(LatLng(marker.latitude, marker.longitude), 17);
                },
                icon: const Icon(LucideIcons.locateFixed, size: 18),
              ),
            ]),
            if (marker.mediaUrl != null && marker.mediaUrl!.isNotEmpty) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(marker.mediaUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: c.muted, alignment: Alignment.center, child: Icon(LucideIcons.imageOff, color: c.mutedForeground))),
                ),
              ),
            ],
            if (previewText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(previewText, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.foreground, fontSize: 14, height: 1.35)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push('/post/${marker.id}');
                },
                icon: const Icon(LucideIcons.messageCircle, size: 17),
                label: const Text('Postni ochish'),
              )),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: 'Manzil havolasini nusxalash',
                onPressed: () {
                  final link = MapDeepLink(latitude: marker.latitude, longitude: marker.longitude, zoom: 16).toUri();
                  Clipboard.setData(ClipboardData(text: '$place\n$link'));
                  Navigator.pop(ctx);
                  AppToast.success(context, 'Havola nusxalandi');
                },
                icon: const Icon(LucideIcons.copy, size: 18),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  void _showPOIDetails(MapPOI poi, Color primary) {
    final c = AlsamosColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _poiColor(poi.category),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(poi.category.icon, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      poi.name ?? poi.category.displayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: c.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      poi.category.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          if (poi.address != null ||
              poi.phone != null ||
              poi.website != null ||
              poi.openingHours != null)
            const Divider(height: 1),
          if (poi.address != null)
            ListTile(
              leading: Icon(
                LucideIcons.mapPin,
                size: 18,
                color: c.mutedForeground,
              ),
              title: Text(
                poi.address!,
                style: TextStyle(fontSize: 13, color: c.foreground),
              ),
              dense: true,
            ),
          if (poi.phone != null)
            ListTile(
              leading: Icon(
                LucideIcons.phone,
                size: 18,
                color: c.mutedForeground,
              ),
              title: Text(
                poi.phone!,
                style: TextStyle(fontSize: 13, color: c.foreground),
              ),
              dense: true,
            ),
          if (poi.website != null)
            ListTile(
              leading: Icon(
                LucideIcons.globe,
                size: 18,
                color: c.mutedForeground,
              ),
              title: Text(
                poi.website!,
                style: TextStyle(fontSize: 13, color: c.foreground),
              ),
              dense: true,
            ),
          if (poi.openingHours != null)
            ListTile(
              leading: Icon(LucideIcons.clock, size: 18, color: c.mutedForeground),
              title: Text(poi.openingHours!, style: TextStyle(fontSize: 13, color: c.foreground)),
              dense: true,
            ),
          // Distance badge
          ListTile(
            leading: Icon(LucideIcons.move, size: 18, color: c.mutedForeground),
            title: Text(_distanceText(poi.latitude, poi.longitude), style: TextStyle(fontSize: 13, color: c.foreground)),
            dense: true,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(LucideIcons.navigation, size: 16),
                  label: const Text("Yo'nalish"),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _destination = (lat: poi.latitude, lng: poi.longitude, name: poi.name ?? poi.category.displayName);
                      _showDirMobile = true;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(LucideIcons.share2, size: 16),
                  label: const Text('Ulashish'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    shareLocation(lat: poi.latitude, lng: poi.longitude, name: poi.name ?? poi.category.displayName);
                  },
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  String _distanceText(double lat, double lng) {
    final pos = ref.read(locationProvider).currentPosition;
    if (pos == null) return '';
    const R = 6371.0;
    final dLat = (lat - pos.latitude) * math.pi / 180;
    final dLon = (lng - pos.longitude) * math.pi / 180;
    final a = math.sin(dLat) * math.sin(dLat) + math.cos(pos.latitude * math.pi / 180) * math.cos(lat * math.pi / 180) * math.sin(dLon) * math.sin(dLon);
    final km = R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    if (km < 1) return '${(km * 1000).round()} m uzoqlikda';
    return '${km.toStringAsFixed(1)} km uzoqlikda';
  }

  Color _poiColor(POICategory category) {
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

  void _animateRoute(List<LatLng> fullRoute) {
    _routeAnimTimer?.cancel();
    if (fullRoute.isEmpty) { setState(() => _activeRoute = fullRoute); return; }
    final step = math.max(1, fullRoute.length ~/ 60);
    int idx = 0;
    _routeAnimTimer = Timer.periodic(const Duration(milliseconds: 16), (t) {
      idx = math.min(idx + step, fullRoute.length);
      if (mounted) {
        setState(() => _activeRoute = fullRoute.sublist(0, idx));
      }
      if (idx >= fullRoute.length) { t.cancel(); }
    });
  }

  // ════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final c      = AlsamosColors.of(context);
    final locSt  = ref.watch(locationProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    // Move map to user location when it first arrives
    final pos = locSt.currentPosition;
    if (pos != null && !_hasCenteredOnUser) {
      Future.microtask(() {
        if (mounted && !_hasCenteredOnUser) {
          final loc = LatLng(pos.latitude, pos.longitude);
          setState(() { _center = loc; _hasCenteredOnUser = true; });
          try { _mapCtrl.move(loc, 15); } catch (_) {}
        }
      });
    }
    // Update tracking path breadcrumb
    if (pos != null) {
      final loc = LatLng(pos.latitude, pos.longitude);
      final shouldAdd = _trackingPath.isEmpty ||
          (_trackingPath.last.latitude - loc.latitude).abs() > 0.00005 ||
          (_trackingPath.last.longitude - loc.longitude).abs() > 0.00005;
      if (shouldAdd) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _trackingPath.add(loc);
              if (_trackingPath.length > 500) { _trackingPath.removeAt(0); }
            });
          }
        });
      }
      // Update compass heading
      final heading = pos.heading;
      if (heading >= 0 && (heading - _compassHeading).abs() > 2) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) { setState(() => _compassHeading = heading); }
        });
      }
    }

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: isWide
          ? Stack(children: [
              Row(children: [
                if (_sidebarOpen) SizedBox(width: 320, child: _buildSidebar(c, locSt)),
                Expanded(child: _buildMapArea(c, locSt, isWide)),
              ]),
              // Desktop CollapsibleDirectionsPanel
              if (_showDirectionsPanel)
                Positioned(
                  left: _sidebarOpen ? 320 : 0,
                  top: 0, bottom: 0,
                  child: CollapsibleDirectionsPanel(
                    collapsed: _directionsPanelCollapsed,
                    onCollapsedChange: (collapsed) => setState(() => _directionsPanelCollapsed = collapsed),
                    currentLocation: locSt.currentPosition != null
                      ? (lat: locSt.currentPosition!.latitude, lng: locSt.currentPosition!.longitude)
                      : null,
                    initialDestination: _destination,
                    transportMode: _transport,
                    onTransportModeChange: (m) => setState(() => _transport = m),
                    onRouteCalculated: (route) {
                      if (route != null && route.geometry.isNotEmpty) {
                        _animateRoute(route.geometry);
                        final mid = route.geometry[route.geometry.length ~/ 2];
                        setState(() { _center = mid; });
                        _mapCtrl.move(mid, _zoom);
                        // speak first instruction
                        if (route.steps.isNotEmpty) {
                          _speakInstruction(route.steps.first.instruction);
                        }
                      } else {
                        setState(() => _activeRoute = null);
                      }
                    },
                    onStepSelected: (loc) {
                      setState(() => _center = LatLng(loc.lat, loc.lng));
                      _mapCtrl.move(LatLng(loc.lat, loc.lng), 17);
                    },
                    onClose: () => setState(() { _showDirectionsPanel = false; _activeRoute = null; _mapSelectionMode = null; _directionsPanelCollapsed = false; }),
                    mapSelectionMode: _mapSelectionMode,
                    onMapSelectionModeChange: (m) => setState(() => _mapSelectionMode = m),
                    selectedMapLocation: _selectedMapLoc,
                    onClearSelectedMapLocation: () => setState(() => _selectedMapLoc = null),
                  ),
                ),
              // Sidebar toggle
              _buildSidebarToggle(c),
            ])
          : Column(children: [
              _buildMobileHeader(c, locSt),
              Expanded(child: _buildMapArea(c, locSt, isWide)),
            ]),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  MOBILE HEADER  (web 1:1 pixel-perfect)
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildMobileHeader(AlsamosColors c, LocationState locSt) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: c.background.withValues(alpha: 0.95),
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Row(children: [
            Icon(LucideIcons.mapPin, color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Text('Xarita', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              Text('Real vaqt joylashuv', style: TextStyle(fontSize: 11, color: c.mutedForeground)),
            ])),
            // locate
            _MobileHeaderBtn(icon: LucideIcons.locate, onTap: _centerOnMe, tooltip: 'Mening joylashuvim'),
            // settings
            _MobileHeaderBtn(icon: LucideIcons.settings, onTap: () => _showSettingsSheet(), tooltip: 'Sozlamalar'),
            // menu
            _MobileHeaderBtn(icon: LucideIcons.menu, onTap: () => _showListSheet(), tooltip: 'Menyu'),
          ]),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  DESKTOP SIDEBAR  (web 1:1 — w-80 = 320px)
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildSidebar(AlsamosColors c, LocationState locSt) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: 320,
      decoration: BoxDecoration(color: c.background, border: Border(right: BorderSide(color: c.border))),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
          child: Row(children: [
            Icon(LucideIcons.mapPin, color: primary, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Text('Xarita', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              Text('Real vaqt joylashuv', style: TextStyle(fontSize: 12, color: c.mutedForeground)),
            ])),
            IconButton(
              icon: Icon(LucideIcons.settings, size: 20, color: c.foreground),
              onPressed: () => _showSettingsSheet(),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),
          ]),
        ),
        // Search — real Nominatim search with current location context
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _searchCtrl,
              onChanged: (q) {
                setState(() { _searchResults = []; });
                _searchDebounce?.cancel();
                if (q.trim().length < 2) return;
                setState(() => _isSearchingMap = true);
                _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
                  final pos = ref.read(locationProvider).currentPosition;
                  final results = await ref.read(mapRepoProvider).searchPlaces(q, lat: pos?.latitude, lon: pos?.longitude);
                  if (!mounted) return;
                  setState(() { _searchResults = results; _isSearchingMap = false; });
                });
              },
              decoration: InputDecoration(
                hintText: 'Qidirish...',
                prefixIcon: _isSearchingMap
                  ? Padding(padding: const EdgeInsets.all(11), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: primary)))
                  : Icon(LucideIcons.search, size: 16, color: c.mutedForeground),
                suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(icon: Icon(LucideIcons.x, size: 16, color: c.mutedForeground), onPressed: () { _searchCtrl.clear(); setState(() { _searchResults = []; }); })
                  : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              ),
            ),
            // Search results dropdown
            if (_searchResults.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)]),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(4),
                  itemCount: _searchResults.length,
                  itemBuilder: (_, i) {
                    final r = _searchResults[i];
                    final title = r.displayName.split(',').first;
                    final sub = r.displayName.split(',').skip(1).take(2).join(',').trim();
                    return InkWell(
                      onTap: () {
                        final loc = LatLng(r.lat, r.lon);
                        setState(() { _center = loc; _zoom = 16; _searchResults = []; _searchCtrl.clear(); });
                        _mapCtrl.move(loc, 16);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Row(children: [
                          Icon(LucideIcons.mapPin, size: 15, color: c.mutedForeground),
                          const SizedBox(width: 8),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.foreground), maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 11, color: c.mutedForeground), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ])),
                        ]),
                      ),
                    );
                  },
                ),
              ),
          ]),
        ),
        // Quick actions
        MapQuickActions(currentLocation: locSt.currentPosition != null
          ? LatLng(locSt.currentPosition!.latitude, locSt.currentPosition!.longitude)
          : null),
        // Presence row (who's viewing the map now)
        if (_usersOnMap.isNotEmpty) _buildPresenceRow(c, primary),
        // Tabs — web 1:1: text only, compact (Yaqinda | Kuzatuvlar | Statistika)
        Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
          child: TabBar(
            controller: _tab,
            labelColor: primary,
            unselectedLabelColor: c.mutedForeground,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            indicator: BoxDecoration(border: Border(bottom: BorderSide(color: primary, width: 2))),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            isScrollable: false,
            labelPadding: EdgeInsets.zero,
            tabs: const [
              Tab(text: 'Yaqinda',    height: 40),
              Tab(text: 'Obunalar',   height: 40),
              Tab(text: 'Statistika', height: 40),
            ],
          ),
        ),
        Expanded(child: TabBarView(controller: _tab, children: [
          _buildNearbyList(c, locSt),
          _buildFollowingList(c, locSt),
          _buildActivityTab(c, locSt),
        ])),
      ]),
    );
  }

  Widget _buildPresenceRow(AlsamosColors c, Color primary) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.eye, size: 14, color: primary),
          const SizedBox(width: 6),
          Text("Hozir ko'rayotganlar", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.foreground)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(6)),
            child: Text('${_usersOnMap.length}', style: TextStyle(fontSize: 11, color: c.foreground)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          ..._usersOnMap.take(8).map((u) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Stack(children: [
              CircleAvatar(
                radius: 16,
                backgroundImage: (u['avatar_url'] as String?)?.isNotEmpty == true ? NetworkImage(u['avatar_url'] as String) : null,
                backgroundColor: c.muted,
                child: (u['avatar_url'] as String?)?.isEmpty != false
                  ? Text((u['display_name'] as String? ?? '?').isNotEmpty ? (u['display_name'] as String)[0] : '?', style: const TextStyle(fontSize: 12))
                  : null,
              ),
              Positioned(right: 0, bottom: 0, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: c.background, width: 2)))),
            ]),
          )),
          if (_usersOnMap.length > 8) ...[
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
              child: Center(child: Text('+${_usersOnMap.length - 8}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.foreground))),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _buildSidebarToggle(AlsamosColors c) {
    return Positioned(
      left: _sidebarOpen ? 320 : 0,
      top: MediaQuery.of(context).size.height / 2 - 22,
      child: GestureDetector(
        onTap: () => setState(() => _sidebarOpen = !_sidebarOpen),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 14),
          decoration: BoxDecoration(
            color: c.card,
            border: Border.all(color: c.border),
            borderRadius: const BorderRadius.only(topRight: Radius.circular(6), bottomRight: Radius.circular(6)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6)],
          ),
          child: Icon(_sidebarOpen ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 16, color: c.foreground),
        ),
      ),
    );
  }

  // ─── Nearby list ─────────────────────────────────────────────────────────
  Widget _buildNearbyList(AlsamosColors c, LocationState locSt) {
    final q = _searchCtrl.text.toLowerCase();
    final list = locSt.nearbyUsers.where((u) =>
      (u.profile?.displayName.toLowerCase().contains(q) ?? false) ||
      (u.profile?.username.toLowerCase().contains(q) ?? false)).toList();

    if (list.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(LucideIcons.users, size: 48, color: c.mutedForeground),
        const SizedBox(height: 12),
        Text("Yaqin atrofda hech kim yo'q", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.foreground)),
        const SizedBox(height: 4),
        Text("Joylashuvni ulashayotgan foydalanuvchilar\n${_nearbyRadius.toStringAsFixed(0)} km radiusda ko'rinadi",
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.mutedForeground)),
      ])));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      itemBuilder: (_, i) => _UserCard(user: list[i], c: c, onTap: () => _mapCtrl.move(LatLng(list[i].latitude, list[i].longitude), 17),
        onNavigate: () { setState(() { _destination = (lat: list[i].latitude, lng: list[i].longitude, name: list[i].profile?.displayName ?? 'Foydalanuvchi'); _showDirectionsPanel = true; }); }),
    );
  }

  // ─── Following list ───────────────────────────────────────────────────────
  Widget _buildFollowingList(AlsamosColors c, LocationState locSt) {
    final q = _searchCtrl.text.toLowerCase();
    final list = locSt.followingUsers.where((u) =>
      (u.profile?.displayName.toLowerCase().contains(q) ?? false) ||
      (u.profile?.username.toLowerCase().contains(q) ?? false)).toList();

    if (list.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(LucideIcons.userPlus, size: 48, color: c.mutedForeground),
        const SizedBox(height: 12),
        Text("Obunalar joylashuvni ulashmayapti", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.foreground)),
      ])));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      itemBuilder: (_, i) => _UserCard(user: list[i], c: c, onTap: () => _mapCtrl.move(LatLng(list[i].latitude, list[i].longitude), 17),
        onNavigate: () { setState(() { _destination = (lat: list[i].latitude, lng: list[i].longitude, name: list[i].profile?.displayName ?? 'Foydalanuvchi'); _showDirectionsPanel = true; }); }),
    );
  }

  // ─── Activity tab ─────────────────────────────────────────────────────────
  Widget _buildActivityTab(AlsamosColors c, LocationState locSt) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    if (isWide) {
      return LocationHistoryPanel(
        onNavigateToPlace: (lat, lng, name) => _mapCtrl.move(LatLng(lat, lng), 16),
        onViewRoute: (route) {
          setState(() => _activeRoute = route.routeGeometry);
          if (route.routeGeometry.isNotEmpty) {
            final mid = route.routeGeometry[route.routeGeometry.length ~/ 2];
            _mapCtrl.move(mid, 14);
          }
        },
      );
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      StepTrackingCharts(stepsToday: locSt.stepsToday, dailyGoal: _stepGoal),
      const SizedBox(height: 12),
      _BatteryCard(level: _batteryLevel, c: c),
      const SizedBox(height: 8),
      _ConnectionCard(isOnline: _isOnline, c: c),
    ]);
  }

  // ════════════════════════════════════════════════════════════════════════
  //  MAP AREA  (flutter_map + all overlays)
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildMapArea(AlsamosColors c, LocationState locSt, bool isWide) {
    final primary  = Theme.of(context).colorScheme.primary;
    final histSt   = ref.watch(locationHistoryProvider);
    final savedSt  = ref.watch(savedPlacesProvider);
    final markers  = <Marker>[];

    // Frequent places
    if (_showFreqPlaces) {
      for (final p in histSt.frequentPlaces) {
        markers.add(Marker(
          point: LatLng(p.latitude, p.longitude),
          width: 44, height: 54,
          child: _FrequentPlaceMarker(place: p, primary: primary),
        ));
      }
    }
    // Saved places
    for (final p in [...savedSt.favorites, ...savedSt.recent]) {
      markers.add(Marker(
        point: LatLng(p.lat, p.lng),
        width: 36, height: 44,
        child: _SavedPlaceMarker(place: p, primary: primary),
      ));
    }
    // Current user
    if (locSt.currentPosition != null) {
      markers.add(Marker(
        point: LatLng(locSt.currentPosition!.latitude, locSt.currentPosition!.longitude),
        width: 60, height: 60,
        child: RepaintBoundary(
          child: _SelfMarker(primary: primary, heading: locSt.currentPosition!.heading),
        ),
      ));
    }
    // Destination pin
    if (_destination != null) {
      markers.add(Marker(
        point: LatLng(_destination!.lat, _destination!.lng),
        width: 36, height: 44,
        alignment: Alignment.topCenter,
        child: RepaintBoundary(
          child: _DestinationPin(primary: primary),
        ),
      ));
    }
    // Selected map location pin
    if (_selectedMapLoc != null) {
      markers.add(Marker(
        point: LatLng(_selectedMapLoc!.lat, _selectedMapLoc!.lng),
        width: 32, height: 32,
        child: Icon(LucideIcons.crosshair, color: _mapSelectionMode == 'origin' ? primary : const Color(0xFFEF4444), size: 28),
      ));
    }

    return Stack(children: [
      // ── FlutterMap (wrapped for keyboard shortcuts) ──────────────────────
      Focus(
        focusNode: _mapFocusNode,
        autofocus: true,
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.equal): () => _animateZoom(_zoom + 1),
            const SingleActivator(LogicalKeyboardKey.numpadAdd): () => _animateZoom(_zoom + 1),
            const SingleActivator(LogicalKeyboardKey.minus): () => _animateZoom(_zoom - 1),
            const SingleActivator(LogicalKeyboardKey.numpadSubtract): () => _animateZoom(_zoom - 1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () => _mapCtrl.move(LatLng(_center.latitude + 0.001, _center.longitude), _zoom),
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => _mapCtrl.move(LatLng(_center.latitude - 0.001, _center.longitude), _zoom),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _mapCtrl.move(LatLng(_center.latitude, _center.longitude - 0.001), _zoom),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () => _mapCtrl.move(LatLng(_center.latitude, _center.longitude + 0.001), _zoom),
          },
          child: FlutterMap(
        mapController: _mapCtrl,
        options: MapOptions(
          initialCenter: _center,
          initialZoom: _zoom,
          minZoom: 3, maxZoom: 19,
          onTap: _onMapTap,
          onLongPress: _onMapLongPress,
          onPositionChanged: (cam, _) {
            _center = cam.center;
            _zoom = cam.zoom;
            _onMapMoved();
          },
          interactionOptions: InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            scrollWheelVelocity: 0.005,
            pinchZoomThreshold: 0.1,
            pinchMoveThreshold: 10.0,
            enableMultiFingerGestureRace: true,
            pinchZoomWinGestures:
                MultiFingerGesture.pinchZoom | MultiFingerGesture.pinchMove,
            pinchMoveWinGestures:
                MultiFingerGesture.pinchZoom | MultiFingerGesture.pinchMove,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: _tileUrl(),
            userAgentPackageName: 'com.alsamos.app',
            tileProvider: _cachedTileProvider,
            errorTileCallback: (_, __, ___) {},
            keepBuffer: 6,
          ),
          // Radius circle
          if (_showRadiusCircle && locSt.currentPosition != null)
            CircleLayer(circles: [
              CircleMarker(
                point: LatLng(locSt.currentPosition!.latitude, locSt.currentPosition!.longitude),
                radius: _nearbyRadius * 1000, useRadiusInMeter: true,
                color: primary.withValues(alpha: 0.08),
                borderColor: primary.withValues(alpha: 0.4),
                borderStrokeWidth: 1.5,
              ),
            ]),
          // Accuracy circle for user position
          if (locSt.currentPosition != null && locSt.currentPosition!.accuracy > 0)
            CircleLayer(circles: [
              CircleMarker(
                point: LatLng(locSt.currentPosition!.latitude, locSt.currentPosition!.longitude),
                radius: locSt.currentPosition!.accuracy,
                useRadiusInMeter: true,
                color: locSt.isCoarse ? Colors.amber.withValues(alpha: 0.08) : primary.withValues(alpha: 0.06),
                borderColor: locSt.isCoarse ? Colors.amber.withValues(alpha: 0.3) : primary.withValues(alpha: 0.25),
                borderStrokeWidth: 1.5,
              ),
            ]),
          // Active route polyline
          if (_activeRoute != null && _activeRoute!.length > 1)
            PolylineLayer(polylines: [
              Polyline(points: _activeRoute!, strokeWidth: 10, color: primary.withValues(alpha: 0.20)),
              Polyline(points: _activeRoute!, strokeWidth: 5, color: primary, borderColor: Colors.white, borderStrokeWidth: 1.5),
            ]),
          // Today's route (dashed)
          if (_viewingRoute == null)
            Consumer(builder: (_, ref, __) {
              final todayRoute = ref.watch(locationHistoryProvider).todayRoute;
              if (todayRoute == null || todayRoute.routeGeometry.length < 2) return const SizedBox.shrink();
              return PolylineLayer(polylines: [
                Polyline(points: todayRoute.routeGeometry, strokeWidth: 3, color: primary.withValues(alpha: 0.55), pattern: StrokePattern.dashed(segments: const [8, 4])),
              ]);
            }),
          // Viewing historical route
          if (_viewingRoute != null && _viewingRoute!.routeGeometry.length > 1)
            PolylineLayer(polylines: [
              Polyline(points: _viewingRoute!.routeGeometry, strokeWidth: 4, color: const Color(0xFF16A34A)),
            ]),
          MarkerLayer(markers: markers),
          // Clustered user markers (nearby + following)
          buildUserMarkersLayer(
            locSt: locSt,
            showNearby: _showNearby,
            showFollowing: _showFollowing,
            primary: primary,
            onUserTap: (user) => _showUserSheet(user, c),
          ),
          // POI layer
          Consumer(builder: (_, ref, __) {
            final config = ref.watch(mapLayersConfigProvider);
            if (!config.showPOIs || config.poiCategories.isEmpty) return const SizedBox.shrink();
            return POIMarkersLayer(
              center: _center,
              zoom: _zoom,
              onPOITap: (poi) => _showPOIDetails(poi, primary),
            );
          }),
          // Cross-feature markers
          Consumer(
            builder: (context, ref, child) {
              final config = ref.watch(mapLayersConfigProvider);
              if (!config.showMarketplace && !config.showEvents && !config.showSocialPosts) {
                return const SizedBox.shrink();
              }
              final bounds = _mapCtrl.camera.visibleBounds;
              return CrossFeatureMarkersLayer(
                bounds: bounds,
                onMarkerTap: (type, id) {
                  if (type == 'marketplace') {
                    AppToast.info(context, 'Mahsulot: $id');
                  } else if (type == 'event') {
                    AppToast.info(context, 'Tadbir: $id');
                  } else if (type == 'social') {
                    _showSocialPostSheet(id);
                  }
                },
              );
            },
          ),
          // Taxi live layer
          Consumer(builder: (_, ref, __) {
            final config = ref.watch(mapLayersConfigProvider);
            if (!config.showTaxis) return const SizedBox.shrink();
            return TaxiMarkersLayer(
              onTaxiTap: (taxi) {
                AppToast.info(context, 'Taksi: ${taxi.vehicleType ?? "Sedan"}');
              },
            );
          }),
          // Route end pin
          if (_activeRoute != null && _activeRoute!.isNotEmpty)
            MarkerLayer(markers: [
              Marker(point: _activeRoute!.last, width: 36, height: 44, alignment: Alignment.topCenter, child: _DestinationPin(primary: primary)),
            ]),
          // Tracking path (breadcrumb trail) — subtle dashed line
          if (_trackingPath.length > 1)
            PolylineLayer(polylines: [
              Polyline(points: _trackingPath, strokeWidth: 2, color: primary.withValues(alpha: 0.4), pattern: StrokePattern.dashed(segments: const [4, 6])),
            ]),
          // Long-press marker
          if (_longPressPoint != null)
            MarkerLayer(markers: [
              Marker(point: _longPressPoint!, width: 32, height: 40, alignment: Alignment.bottomCenter, child: _LongPressMarker(color: primary)),
            ]),
          // Compass widget
          const MapCompass.cupertino(
            alignment: Alignment.bottomLeft,
            padding: EdgeInsets.only(left: 12, bottom: 80),
            hideIfRotatedNorth: true,
          ),
        ],
      ),   // FlutterMap
        ), // CallbackShortcuts
      ), // Focus

      // ── Top-right: layer cycle button only (Yandex style) ──────────────
      Positioned(top: 8, right: 12, child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        _GlassPanel(child: _LayerCycleBtn(layer: _layer, onTap: _cycleLayer)),
      ])),

      // ── Map selection mode banner ────────────────────────────────────────
      if (_mapSelectionMode != null)
        Positioned(top: 12, left: 0, right: 0, child: Center(child: _MapSelectionBanner(
          mode: _mapSelectionMode!,
          onCancel: () => setState(() => _mapSelectionMode = null),
        ))),

      // ── Destination bar at top ────────────────────────────────────────
      if (_destination != null && _activeRoute == null)
        Positioned(
          top: _mapSelectionMode != null ? 60 : 8,
          left: 60, right: 60,
          child: _DestinationBar(
            dest: _destination!, transport: _transport, locSt: locSt, c: c,
            onShowDirections: () => setState(() => isWide ? _showDirectionsPanel = true : _showDirMobile = true),
            onClose: () => setState(() => _destination = null),
          ),
        ),

      // ── Viewing route banner ─────────────────────────────────────────
      if (_viewingRoute != null)
        Positioned(top: 8, left: 60, right: 60, child: _GlassPanel(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Icon(LucideIcons.footprints, size: 16, color: const Color(0xFF16A34A)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text("${_viewingRoute!.routeDate} yo'li", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.foreground)),
              Text('${_viewingRoute!.totalDistanceKm.toStringAsFixed(1)} km', style: TextStyle(fontSize: 11, color: c.mutedForeground)),
            ])),
            GestureDetector(onTap: () => setState(() => _viewingRoute = null), child: Icon(LucideIcons.x, size: 16, color: c.mutedForeground)),
          ]),
        ))),

      // ── Bottom-right: Directions + Traffic + Voice + Locate + Zoom ────────
      Positioned(
        right: 12,
        bottom: isWide 
          ? 16 
          : _showDirMobile 
            ? _getBottomOffsetForSheet() 
            : 84,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Traffic toggle
          _GlassPanel(child: _MapToggleBtn(
            icon: LucideIcons.carFront,
            tooltip: 'Trafik',
            active: _showTraffic,
            primary: primary,
            onTap: () => setState(() => _showTraffic = !_showTraffic),
          )),
          const SizedBox(height: 6),
          // Voice toggle
          _GlassPanel(child: _MapToggleBtn(
            icon: _voiceEnabled ? LucideIcons.volume2 : LucideIcons.volumeX,
            tooltip: _voiceEnabled ? "Ovoz yoqiq" : "Ovoz o'chiq",
            active: _voiceEnabled,
            primary: primary,
            onTap: () { setState(() => _voiceEnabled = !_voiceEnabled); HapticFeedback.selectionClick(); },
          )),
          const SizedBox(height: 6),
          // Directions — Yandex-style prominent button
          _GlassPanel(child: _MapToggleBtn(
            icon: LucideIcons.route,
            tooltip: "Yo'nalish",
            active: _showDirectionsPanel || _showDirMobile,
            primary: primary,
            onTap: () => isWide
              ? setState(() => _showDirectionsPanel = !_showDirectionsPanel)
              : setState(() => _showDirMobile = !_showDirMobile),
          )),
          const SizedBox(height: 6),
          // Locate (always tappable — spinner is clickable too)
          _GlassPanel(child: GestureDetector(
            onTap: _centerOnMe,
            child: Container(width: 40, height: 40, alignment: Alignment.center,
              child: locSt.isAcquiring
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: primary))
                : Icon(LucideIcons.locate, size: 20, color: primary)),
          )),
          const SizedBox(height: 6),
          // Zoom in
          _GlassPanel(child: _MapBtn(
            icon: LucideIcons.plus,
            tooltip: 'Yaqinlashtirish',
            onTap: () => _animateZoom(_zoom + 1),
          )),
          const SizedBox(height: 6),
          // Zoom out
          _GlassPanel(child: _MapBtn(
            icon: LucideIcons.minus,
            tooltip: 'Uzoqlashtirish',
            onTap: () => _animateZoom(_zoom - 1),
          )),
        ]),
      ),

      // ── Mobile bottom: quick actions ────────────────────────────────────
      if (!isWide)
        Positioned(left: 0, right: 0, bottom: 0, child: ClipRect(child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: c.background.withValues(alpha: 0.88),
            child: MapQuickActions(currentLocation: locSt.currentPosition != null
              ? LatLng(locSt.currentPosition!.latitude, locSt.currentPosition!.longitude)
              : null),
          ),
        ))),

      // ── Mobile Draggable Directions sheet ───────────────────────────────
      if (!isWide)
        Positioned.fill(child: Align(alignment: Alignment.bottomCenter, child: DraggableDirectionsSheet(
          open: _showDirMobile,
          onOpenChange: (v) => setState(() { _showDirMobile = v; if (!v) { _activeRoute = null; _mapSelectionMode = null; } }),
          currentLocation: locSt.currentPosition != null ? (lat: locSt.currentPosition!.latitude, lng: locSt.currentPosition!.longitude) : null,
          initialDestination: _destination,
          transportMode: _transport,
          onTransportModeChange: (m) => setState(() => _transport = m),
          onRouteCalculated: (route) {
            setState(() {
              _activeRoute = route?.geometry;
              if (route != null && route.geometry.isNotEmpty) {
                final mid = route.geometry[route.geometry.length ~/ 2];
                _center = mid;
                _mapCtrl.move(mid, _zoom);
              }
            });
          },
          onStepSelected: (loc) { _mapCtrl.move(LatLng(loc.lat, loc.lng), 17); },
          mapSelectionMode: _mapSelectionMode,
          onMapSelectionModeChange: (m) => setState(() => _mapSelectionMode = m),
          selectedMapLocation: _selectedMapLoc,
          onClearSelectedMapLocation: () => setState(() => _selectedMapLoc = null),
          onSheetStateChange: (state) => setState(() => _mobileSheetState = state),
        ))),

      // ── Mobile History sheet ────────────────────────────────────────────
      if (!isWide)
        Positioned.fill(child: Align(alignment: Alignment.bottomCenter, child: LocationHistoryMobileSheet(
          open: _showHistoryMobile,
          onOpenChange: (v) => setState(() => _showHistoryMobile = v),
          onNavigateToPlace: (lat, lng, name) {
            setState(() { _destination = (lat: lat, lng: lng, name: name); _showHistoryMobile = false; });
          },
          onViewRoute: (route) {
            setState(() { _viewingRoute = route; _showHistoryMobile = false; });
            if (route.routeGeometry.isNotEmpty) {
              final mid = route.routeGeometry[route.routeGeometry.length ~/ 2];
              _mapCtrl.move(mid, 14);
            }
          },
        ))),
    ]);
  }

  // ─── Bottom sheets ────────────────────────────────────────────────────────
  void _showSettingsSheet() {
    final c = AlsamosColors.of(context);
    final locSt = ref.read(locationProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(initialChildSize: 0.7, maxChildSize: 0.95, minChildSize: 0.4, expand: false, builder: (_, sc) => Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(controller: sc, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)))),
          const Center(child: Text('Sozlamalar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          const SizedBox(height: 16),
          Text('Xarita turi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.mutedForeground)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final l in MapLayer.values)
              OutlinedButton.icon(
                icon: Icon(_layerIconFor(l), size: 14),
                label: Text(_layerLabelFor(l), style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  backgroundColor: _layer == l ? Theme.of(ctx).colorScheme.primary : null,
                  foregroundColor: _layer == l ? Colors.white : null,
                  side: BorderSide(color: _layer == l ? Theme.of(ctx).colorScheme.primary : c.border),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                ),
                onPressed: () { setState(() => _layer = l); Navigator.pop(ctx); },
              ),
          ]),
          const SizedBox(height: 8),
          Text('Qatlamlar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.mutedForeground)),
          const SizedBox(height: 6),
          _LayerToggle(
            icon: LucideIcons.utensilsCrossed,
            label: 'POI (restoran, kafe, bank...)',
            active: ref.watch(mapLayersConfigProvider).showPOIs,
            onChanged: (v) {
              ref.read(mapLayersConfigProvider.notifier).togglePOIs(v);
              if (v) ref.read(mapLayersConfigProvider.notifier).setPOICategories({...POICategory.values});
            },
            c: c,
          ),
          _LayerToggle(
            icon: LucideIcons.shoppingBag,
            label: 'Marketplace',
            active: ref.watch(mapLayersConfigProvider).showMarketplace,
            onChanged: (v) => ref.read(mapLayersConfigProvider.notifier).toggleMarketplace(v),
            c: c,
          ),
          _LayerToggle(
            icon: LucideIcons.calendar,
            label: 'Tadbirlar',
            active: ref.watch(mapLayersConfigProvider).showEvents,
            onChanged: (v) => ref.read(mapLayersConfigProvider.notifier).toggleEvents(v),
            c: c,
          ),
          _LayerToggle(
            icon: LucideIcons.messageCircle,
            label: 'Ijtimoiy postlar',
            active: ref.watch(mapLayersConfigProvider).showSocialPosts,
            onChanged: (v) => ref.read(mapLayersConfigProvider.notifier).toggleSocialPosts(v),
            c: c,
          ),
          _LayerToggle(
            icon: LucideIcons.car,
            label: 'Taksi (real vaqt)',
            active: ref.watch(mapLayersConfigProvider).showTaxis,
            onChanged: (v) => ref.read(mapLayersConfigProvider.notifier).toggleTaxis(v),
            c: c,
          ),
          _LayerToggle(
            icon: LucideIcons.triangleAlert,
            label: "Hodisalar (yo'l harakati)",
            active: ref.watch(mapLayersConfigProvider).showIncidents,
            onChanged: (v) => ref.read(mapLayersConfigProvider.notifier).toggleIncidents(v),
            c: c,
          ),
          const SizedBox(height: 16),
          _SettingsRow(icon: LucideIcons.eye, label: 'Joylashuvni ulashish', value: locSt.isSharing, onChanged: (_) => ref.read(locationProvider.notifier).toggleSharing(), c: c),
          _SettingsRow(icon: LucideIcons.lock, label: 'Maxfiy joylashuv', value: _isLocationPrivate, onChanged: (v) => setState(() => _isLocationPrivate = v), c: c),
          _SettingsRow(icon: LucideIcons.users, label: "Yaqindagilarni ko'rsatish", value: _showNearby, onChanged: (v) => setState(() => _showNearby = v), c: c),
          _SettingsRow(icon: LucideIcons.userPlus, label: "Obunalarni ko'rsatish", value: _showFollowing, onChanged: (v) => setState(() => _showFollowing = v), c: c),
          _SettingsRow(icon: LucideIcons.home, label: 'Tez-tez tashrif joylar', value: _showFreqPlaces, onChanged: (v) => setState(() => _showFreqPlaces = v), c: c),
          _SettingsRow(icon: LucideIcons.target, label: "Radius doirasini ko'rsatish", value: _showRadiusCircle, onChanged: (v) => setState(() => _showRadiusCircle = v), c: c),
          const SizedBox(height: 8),
          Text('Qidiruv radiusi (${_nearbyRadius.toStringAsFixed(0)} km)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.foreground)),
          Slider(
            value: _nearbyRadius, min: 1, max: 50, divisions: 49,
            label: '${_nearbyRadius.toStringAsFixed(0)} km',
            onChanged: (v) => setState(() => _nearbyRadius = v),
            onChangeEnd: (_) => ref.read(locationProvider.notifier).fetchNearbyUsers(radiusKm: _nearbyRadius),
          ),
          const SizedBox(height: 8),
          Text('Radius seçenekleri', style: TextStyle(fontSize: 12, color: c.mutedForeground)),
          Wrap(spacing: 8, children: [
            for (final r in [1.0, 5.0, 10.0, 25.0, 50.0])
              ActionChip(
                label: Text('${r.toStringAsFixed(0)} km'),
                onPressed: () { setState(() => _nearbyRadius = r); ref.read(locationProvider.notifier).fetchNearbyUsers(radiusKm: r); },
                backgroundColor: _nearbyRadius == r ? Theme.of(ctx).colorScheme.primary : c.muted,
                labelStyle: TextStyle(color: _nearbyRadius == r ? Colors.white : c.foreground, fontSize: 12),
              ),
          ]),
          const SizedBox(height: 8),
          TransportModePicker(selected: _transport, onSelect: (m) => setState(() => _transport = m)),
        ]),
      )),
    );
  }

  void _showListSheet() {
    final c = AlsamosColors.of(context);
    final locSt = ref.read(locationProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.4, expand: false, builder: (_, sc) => Column(children: [
        Container(margin: const EdgeInsets.symmetric(vertical: 8), width: 40, height: 4, decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Row(children: [
          Icon(LucideIcons.users, size: 18, color: c.foreground),
          const SizedBox(width: 8),
          const Text('Odamlar & Statistika', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ])),
        MapQuickActionsGrid(currentLocation: locSt.currentPosition != null ? LatLng(locSt.currentPosition!.latitude, locSt.currentPosition!.longitude) : null),
        TabBar(
          controller: _tab,
          labelColor: Theme.of(ctx).colorScheme.primary,
          unselectedLabelColor: c.mutedForeground,
          indicatorColor: Theme.of(ctx).colorScheme.primary,
          dividerColor: c.border,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          tabs: const [Tab(text: 'Yaqinda', height: 40), Tab(text: 'Obunalar', height: 40), Tab(text: 'Statistika', height: 40)],
        ),
        Expanded(child: TabBarView(controller: _tab, children: [
          _buildNearbyList(c, locSt),
          _buildFollowingList(c, locSt),
          _buildActivityTab(c, locSt),
        ])),
      ])),
    );
  }

  void _showUserSheet(UserLocationData u, AlsamosColors c) {
    final prof = u.profile; if (prof == null) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)))),
        Stack(alignment: Alignment.bottomRight, children: [
          CircleAvatar(radius: 36, backgroundImage: prof.avatarUrl != null ? NetworkImage(prof.avatarUrl!) : null, backgroundColor: c.muted,
            child: prof.avatarUrl == null ? Text(prof.displayName.isNotEmpty ? prof.displayName[0].toUpperCase() : '?', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)) : null),
          if (prof.isOnline) Container(width: 16, height: 16, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: c.card, width: 2.5))),
        ]),
        const SizedBox(height: 10),
        Text(prof.displayName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        Text('@${prof.username}', style: TextStyle(color: c.mutedForeground, fontSize: 13)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(LucideIcons.mapPin, size: 13, color: c.mutedForeground),
          const SizedBox(width: 4),
          Text(u.distanceKm <= 0 ? '—' : '${u.distanceKm.toStringAsFixed(1)} km uzoqlikda', style: TextStyle(color: c.mutedForeground, fontSize: 13)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            icon: const Icon(LucideIcons.navigation, size: 16),
            label: const Text("Yo'nalish"),
            onPressed: () { Navigator.pop(ctx); setState(() { _destination = (lat: u.latitude, lng: u.longitude, name: prof.displayName); _showDirMobile = true; }); },
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            icon: const Icon(LucideIcons.messageCircle, size: 16),
            label: const Text('Yozish'),
            onPressed: () { Navigator.pop(ctx); },
          )),
        ]),
      ]))),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SMALL HELPER WIDGETS
// ════════════════════════════════════════════════════════════════════════════

// ─── Glass panel ─────────────────────────────────────────────────────────────
class _GlassPanel extends StatelessWidget {
  final Widget child;
  const _GlassPanel({required this.child});
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: c.card.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 10)],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─── Map icon button ─────────────────────────────────────────────────────────
class _MapBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _MapBtn({required this.icon, required this.tooltip, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Tooltip(message: tooltip, child: GestureDetector(onTap: onTap, child: Container(
      width: 40, height: 40, alignment: Alignment.center,
      child: Icon(icon, size: 20, color: c.foreground),
    )));
  }
}

// ─── Mobile header button ────────────────────────────────────────────────────
class _MobileHeaderBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  const _MobileHeaderBtn({required this.icon, required this.onTap, required this.tooltip});
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Tooltip(message: tooltip, child: GestureDetector(onTap: onTap, child: Container(
      width: 36, height: 36, margin: const EdgeInsets.only(left: 2),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, size: 20, color: c.foreground),
    )));
  }
}

// ─── User card (nearby/following list) ───────────────────────────────────────
class _UserCard extends StatelessWidget {
  final UserLocationData user;
  final AlsamosColors c;
  final VoidCallback onTap;
  final VoidCallback onNavigate;
  const _UserCard({required this.user, required this.c, required this.onTap, required this.onNavigate});
  @override
  Widget build(BuildContext context) {
    final prof = user.profile!;
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
        child: Row(children: [
          Stack(children: [
            Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: prof.isOnline ? Colors.green : c.border, width: 2.5)),
              child: CircleAvatar(radius: 22, backgroundImage: prof.avatarUrl != null ? NetworkImage(prof.avatarUrl!) : null, backgroundColor: c.muted,
                child: prof.avatarUrl == null ? Text(prof.displayName.isNotEmpty ? prof.displayName[0].toUpperCase() : '?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.foreground)) : null)),
            if (prof.isOnline) Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: c.card, width: 2)))),
          ]),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(prof.displayName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.foreground), maxLines: 1, overflow: TextOverflow.ellipsis),
            Row(children: [
              Flexible(child: Text('@${prof.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.mutedForeground))),
              Text(' • ', style: TextStyle(fontSize: 11, color: c.mutedForeground)),
              Icon(LucideIcons.mapPin, size: 11, color: c.mutedForeground),
              const SizedBox(width: 2),
              Text(user.distanceKm <= 0 ? '—' : '${user.distanceKm.toStringAsFixed(1)} km', style: TextStyle(fontSize: 11, color: c.mutedForeground)),
            ]),
          ])),
          GestureDetector(onTap: onNavigate, child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(LucideIcons.navigation, size: 16, color: primary),
          )),
        ]),
      ),
    );
  }
}

// ─── User map marker ─────────────────────────────────────────────────────────
// ─── User card in sidebar lists ────────────────────────────────────────────────

// ─── Destination pin ─────────────────────────────────────────────────────────
class _DestinationPin extends StatefulWidget {
  final Color primary;
  const _DestinationPin({required this.primary});
  @override
  State<_DestinationPin> createState() => _DestinationPinState();
}
class _DestinationPinState extends State<_DestinationPin> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _ctrl, builder: (_, __) => Transform.translate(
      offset: Offset(0, -3 * _ctrl.value),
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFEF4444), border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 3))]),
        child: const Icon(LucideIcons.mapPin, color: Colors.white, size: 14),
      ),
    ));
  }
}

// ─── Destination bar ─────────────────────────────────────────────────────────
class _DestinationBar extends StatelessWidget {
  final ({double lat, double lng, String name}) dest;
  final TransportMode transport;
  final LocationState locSt;
  final AlsamosColors c;
  final VoidCallback onShowDirections;
  final VoidCallback onClose;
  const _DestinationBar({required this.dest, required this.transport, required this.locSt, required this.c, required this.onShowDirections, required this.onClose});
  @override
  Widget build(BuildContext context) {
    return _GlassPanel(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: Row(children: [
      const Icon(LucideIcons.mapPin, color: Color(0xFFEF4444), size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(dest.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.foreground), maxLines: 1, overflow: TextOverflow.ellipsis)),
      const SizedBox(width: 8),
      GestureDetector(onTap: onShowDirections, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(8)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(LucideIcons.route, size: 13, color: Colors.white), SizedBox(width: 4), Text("Yo'nalish", style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600))]),
      )),
      const SizedBox(width: 4),
      GestureDetector(onTap: onClose, child: Icon(LucideIcons.x, size: 16, color: c.mutedForeground)),
    ])));
  }
}

// ─── Map selection banner ─────────────────────────────────────────────────────
class _MapSelectionBanner extends StatelessWidget {
  final String mode;
  final VoidCallback onCancel;
  const _MapSelectionBanner({required this.mode, required this.onCancel});
  @override
  Widget build(BuildContext context) {
    final isOrigin = mode == 'origin';
    final color = isOrigin ? Theme.of(context).colorScheme.primary : const Color(0xFFEF4444);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12)]),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(LucideIcons.crosshair, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Text(isOrigin ? "Boshlang'ich nuqtani xaritadan tanlang" : 'Manzilni xaritadan tanlang', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(width: 8),
        GestureDetector(onTap: onCancel, child: Container(
          width: 22, height: 22,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
          child: const Icon(LucideIcons.x, size: 14, color: Colors.white),
        )),
      ]),
    );
  }
}

// ─── Self marker (pulsing) ────────────────────────────────────────────────────
class _SelfMarker extends StatefulWidget {
  final Color primary;
  final double? heading;
  const _SelfMarker({required this.primary, this.heading});
  @override State<_SelfMarker> createState() => _SelfMarkerState();
}
class _SelfMarkerState extends State<_SelfMarker> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _ctrl, builder: (_, __) {
      final t = _ctrl.value; final t2 = (t + 0.5) % 1.0;
      return Stack(alignment: Alignment.center, children: [
        Container(width: 60 * (0.5 + 0.5 * t), height: 60 * (0.5 + 0.5 * t), decoration: BoxDecoration(shape: BoxShape.circle, color: widget.primary.withValues(alpha: (1 - t) * 0.40))),
        Container(width: 60 * (0.4 + 0.4 * t2), height: 60 * (0.4 + 0.4 * t2), decoration: BoxDecoration(shape: BoxShape.circle, color: widget.primary.withValues(alpha: (1 - t2) * 0.28))),
        if (widget.heading != null && widget.heading! >= 0)
          Transform.rotate(angle: widget.heading! * math.pi / 180, child: CustomPaint(size: const Size(40, 40), painter: _HeadingPainter(color: widget.primary.withValues(alpha: 0.5)))),
        Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.primary, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 6)])),
      ]);
    });
  }
}

class _HeadingPainter extends CustomPainter {
  final Color color;
  _HeadingPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    const reach = 22.0;
    final path = ui.Path()
      ..moveTo(c.dx, c.dy)
      ..lineTo(c.dx - reach * 0.34, c.dy - reach * 0.94)
      ..quadraticBezierTo(c.dx, c.dy - reach * 1.16, c.dx + reach * 0.34, c.dy - reach * 0.94)
      ..close();
    canvas.drawPath(path, Paint()..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: reach)));
  }
  @override bool shouldRepaint(covariant _HeadingPainter old) => old.color != color;
}

// ─── Frequent place marker ────────────────────────────────────────────────────
class _FrequentPlaceMarker extends StatelessWidget {
  final FrequentPlace place;
  final Color primary;
  const _FrequentPlaceMarker({required this.place, required this.primary});
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final (icon, tint, label) = switch (place.placeType) {
      'home'  => (LucideIcons.home, const Color(0xFF22C55E), 'Uy'),
      'work'  => (LucideIcons.briefcase, const Color(0xFF3B82F6), 'Ish'),
      'study' => (LucideIcons.graduationCap, const Color(0xFF8B5CF6), "Ta'lim"),
      _       => (LucideIcons.mapPin, primary, 'Joy'),
    };
    return Tooltip(message: place.name.isNotEmpty ? place.name : label, child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: tint, border: Border.all(color: Colors.white, width: 2.5), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.26), blurRadius: 6, offset: const Offset(0, 2))]),
        child: Icon(icon, size: 17, color: Colors.white)),
      Container(width: 2, height: 8, color: tint.withValues(alpha: 0.8)),
      Container(width: 6, height: 6, decoration: BoxDecoration(color: c.background, shape: BoxShape.circle, border: Border.all(color: tint, width: 1.5))),
    ]));
  }
}

// ─── Saved place marker ───────────────────────────────────────────────────────
class _SavedPlaceMarker extends StatelessWidget {
  final SavedPlace place;
  final Color primary;
  const _SavedPlaceMarker({required this.place, required this.primary});
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final tint = place.isFavorite ? const Color(0xFFF59E0B) : c.mutedForeground;
    return Tooltip(message: place.name, child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, color: c.card, border: Border.all(color: tint, width: 2.5), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 5, offset: const Offset(0, 2))]),
        child: Icon(place.isFavorite ? LucideIcons.star : LucideIcons.bookmark, size: 13, color: tint)),
      Container(width: 1.5, height: 6, color: tint),
    ]));
  }
}

// ─── Battery card ─────────────────────────────────────────────────────────────
class _BatteryCard extends StatelessWidget {
  final int level;
  final AlsamosColors c;
  const _BatteryCard({required this.level, required this.c});
  @override
  Widget build(BuildContext context) {
    final batteryColor = level < 20 ? Colors.red : level < 50 ? Colors.orange : Colors.green;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.battery, size: 16, color: batteryColor),
          const SizedBox(width: 8),
          Text('Batareya', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.foreground)),
          const Spacer(),
          Text('$level%', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: batteryColor)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(
          value: level / 100, minHeight: 8,
          backgroundColor: c.muted,
          valueColor: AlwaysStoppedAnimation<Color>(batteryColor),
        )),
      ]),
    );
  }
}

// ─── Connection card ──────────────────────────────────────────────────────────
class _ConnectionCard extends StatelessWidget {
  final bool isOnline;
  final AlsamosColors c;
  const _ConnectionCard({required this.isOnline, required this.c});
  @override
  Widget build(BuildContext context) {
    final color = isOnline ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(isOnline ? LucideIcons.wifi : LucideIcons.wifiOff, size: 16, color: color)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isOnline ? 'Ulangan' : 'Oflayn', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.foreground)),
          Text(isOnline ? 'Internet barqaror' : "Internet yo'q", style: TextStyle(fontSize: 12, color: c.mutedForeground)),
        ])),
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle,
          boxShadow: isOnline ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 2)] : null)),
      ]),
    );
  }
}

// ─── Settings row ─────────────────────────────────────────────────────────────
class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final AlsamosColors c;
  const _SettingsRow({required this.icon, required this.label, required this.value, required this.onChanged, required this.c});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
      child: Row(children: [
        Icon(icon, size: 16, color: c.mutedForeground),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: c.foreground))),
        Switch(value: value, onChanged: onChanged, activeTrackColor: Theme.of(context).colorScheme.primary),
      ]),
    );
  }
}

// ─── Layer toggle row ─────────────────────────────────────────────────────────
class _LayerToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final ValueChanged<bool> onChanged;
  final AlsamosColors c;
  const _LayerToggle({required this.icon, required this.label, required this.active, required this.onChanged, required this.c});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: active ? primary.withValues(alpha: 0.3) : c.border)),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: (active ? primary : c.muted).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, size: 14, color: active ? primary : c.mutedForeground)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: c.foreground))),
        Switch(value: active, onChanged: onChanged, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, activeTrackColor: primary),
      ]),
    );
  }
}

// ─── Layer helpers (static — used in _MapPageState & settings sheet) ────────
IconData _layerIconFor(MapLayer l) {
  switch (l) {
    case MapLayer.standard:   return LucideIcons.map;
    case MapLayer.satellite:  return LucideIcons.globe;
    case MapLayer.hybrid:     return LucideIcons.layers;
    case MapLayer.terrain:    return LucideIcons.mountain;
  }
}

String _layerLabelFor(MapLayer l) {
  switch (l) {
    case MapLayer.standard:   return 'Standart';
    case MapLayer.satellite:  return "Sun'iy";
    case MapLayer.hybrid:     return 'Gibrid';
    case MapLayer.terrain:    return 'Relyef';
  }
}

// ─── Single cycling layer button (top-right corner of map) ──────────────────
class _LayerCycleBtn extends StatelessWidget {
  final MapLayer layer;
  final VoidCallback onTap;
  const _LayerCycleBtn({required this.layer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: _layerLabelFor(layer),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40, height: 40,
          alignment: Alignment.center,
          child: Icon(_layerIconFor(layer), size: 20, color: primary),
        ),
      ),
    );
  }
}

// ─── Long-press bottom menu action button ────────────────────────────────────
class _LongPressAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _LongPressAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AlsamosColors.of(context).foreground,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Long-press pin marker on map ────────────────────────────────────────────
class _LongPressMarker extends StatefulWidget {
  final Color color;
  const _LongPressMarker({required this.color});
  @override State<_LongPressMarker> createState() => _LongPressMarkerState();
}

class _LongPressMarkerState extends State<_LongPressMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = Curves.elasticOut.transform(_ctrl.value);
        return Transform.scale(
          scale: t,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: const Icon(LucideIcons.mapPin, color: Colors.white, size: 14),
            ),
            // pin stem
            Container(width: 2, height: 8, color: widget.color),
            // pin dot
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ─── Map toggle button (active/inactive state) ───────────────────────────────
class _MapToggleBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final Color primary;
  final VoidCallback onTap;

  const _MapToggleBtn({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: active ? primary.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 20,
            color: active ? primary : c.foreground,
          ),
        ),
      ),
    );
  }
}
