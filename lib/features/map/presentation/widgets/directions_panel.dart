library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/map_models.dart';
import '../../data/map_repository.dart';
import '../providers/map_provider.dart';
import 'transport_mode_picker.dart';
import '../../../../shared/widgets/app_toast.dart';

// ─── arrival time helper ───────────────────────────────────────────────────
String _arrivalTime(double seconds) {
  final arrival = DateTime.now().add(Duration(seconds: seconds.round()));
  final h = arrival.hour.toString().padLeft(2, '0');
  final m = arrival.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

typedef MapSelectionMode = String?; // 'origin' | 'destination' | null

// ═══════════════════════════════════════════════════════════════════════════
// DirectionsPanel  (desktop — web w-[400px] panel)
// ═══════════════════════════════════════════════════════════════════════════
class DirectionsPanel extends ConsumerStatefulWidget {
  final ({double lat, double lng})? currentLocation;
  final ({double lat, double lng, String name})? initialDestination;
  final TransportMode transportMode;
  final ValueChanged<TransportMode> onTransportModeChange;
  /// Called with the selected route (null = cleared).
  final ValueChanged<RouteAlternative?> onRouteCalculated;
  final ValueChanged<({double lat, double lng})>? onStepSelected;
  final VoidCallback onClose;
  // map-tap selection
  final String? mapSelectionMode; // 'origin' | 'destination' | null
  final ValueChanged<String?>? onMapSelectionModeChange;
  final ({double lat, double lng, String name})? selectedMapLocation;
  final VoidCallback? onClearSelectedMapLocation;

  const DirectionsPanel({
    super.key,
    this.currentLocation,
    this.initialDestination,
    required this.transportMode,
    required this.onTransportModeChange,
    required this.onRouteCalculated,
    this.onStepSelected,
    required this.onClose,
    this.mapSelectionMode,
    this.onMapSelectionModeChange,
    this.selectedMapLocation,
    this.onClearSelectedMapLocation,
  });

  @override
  ConsumerState<DirectionsPanel> createState() => _DirectionsPanelState();
}

class _DirectionsPanelState extends ConsumerState<DirectionsPanel> {
  final _originCtrl = TextEditingController();
  final _destCtrl   = TextEditingController();
  final _repo = MapRepository();

  List<SearchResult> _originResults = [];
  List<SearchResult> _destResults   = [];
  bool _showOriginResults = false;
  bool _showDestResults   = false;
  bool _expandedSteps = false;
  bool _showSuggestions = true;
  String? _activeSearch; // 'origin' | 'destination'
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initState());
  }

  void _initState() {
    if (!mounted) return;
    final dir = ref.read(directionsProvider);
    // set origin from current location
    if (widget.currentLocation != null && dir.origin == null) {
      _originCtrl.text = 'Joriy joylashuv';
      ref.read(directionsProvider.notifier).setOrigin((
        lat: widget.currentLocation!.lat,
        lng: widget.currentLocation!.lng,
        name: 'Joriy joylashuv',
      ));
    }
    // set destination from prop
    if (widget.initialDestination != null) {
      final d = widget.initialDestination!;
      _destCtrl.text = d.name;
      ref.read(directionsProvider.notifier).setDestination(d);
    }
  }

  @override
  void didUpdateWidget(DirectionsPanel old) {
    super.didUpdateWidget(old);
    // handle map-tap selection
    final sel = widget.selectedMapLocation;
    if (sel != null && widget.mapSelectionMode != null) {
      if (widget.mapSelectionMode == 'origin') {
        _originCtrl.text = sel.name;
        ref.read(directionsProvider.notifier).setOrigin(sel);
      } else {
        _destCtrl.text = sel.name;
        ref.read(directionsProvider.notifier).setDestination(sel);
      }
      widget.onMapSelectionModeChange?.call(null);
      widget.onClearSelectedMapLocation?.call();
    }
    // Update origin when currentLocation arrives late
    final dir = ref.read(directionsProvider);
    if (widget.currentLocation != null && dir.origin == null) {
      _originCtrl.text = 'Joriy joylashuv';
      ref.read(directionsProvider.notifier).setOrigin((
        lat: widget.currentLocation!.lat,
        lng: widget.currentLocation!.lng,
        name: 'Joriy joylashuv',
      ));
    }
    // auto-calc if both set
    if (dir.origin != null && dir.destination != null && dir.routes.isEmpty && !dir.loading) {
      _calcRoute();
    }
  }

  @override
  void dispose() {
    _originCtrl.dispose();
    _destCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── search with 300 ms debounce ──────────────────────────────────────────
  void _onSearchChanged(String q, String type) {
    _debounce?.cancel();
    if (q.length < 2) {
      setState(() {
        if (type == 'origin') { _originResults = []; }
        else { _destResults = []; }
        _showOriginResults = false;
        _showDestResults   = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final pos = widget.currentLocation;
      final results = await _repo.searchPlaces(q, lat: pos?.lat, lon: pos?.lng);
      if (!mounted) return;
      setState(() {
        if (type == 'origin') { _originResults = results; _showOriginResults = results.isNotEmpty; }
        else { _destResults = results; _showDestResults = results.isNotEmpty; }
      });
    });
  }

  void _selectResult(SearchResult r, String type) {
    HapticFeedback.selectionClick();
    final loc = (lat: r.lat, lng: r.lon, name: r.displayName.split(',').first);
    if (type == 'origin') {
      _originCtrl.text = loc.name;
      ref.read(directionsProvider.notifier).setOrigin(loc);
      setState(() { _originResults = []; _showOriginResults = false; });
    } else {
      _destCtrl.text = loc.name;
      ref.read(directionsProvider.notifier).setDestination(loc);
      setState(() { _destResults = []; _showDestResults = false; });
    }
    _calcRoute();
  }

  void _selectSavedPlace(SavedPlace p, String type) {
    final loc = (lat: p.lat, lng: p.lng, name: p.name);
    if (type == 'origin') {
      _originCtrl.text = p.name;
      ref.read(directionsProvider.notifier).setOrigin(loc);
    } else {
      _destCtrl.text = p.name;
      ref.read(directionsProvider.notifier).setDestination(loc);
    }
    setState(() => _showSuggestions = false);
    _calcRoute();
  }

  void _useCurrentLocation() {
    if (widget.currentLocation == null) return;
    final loc = (lat: widget.currentLocation!.lat, lng: widget.currentLocation!.lng, name: 'Joriy joylashuv');
    _originCtrl.text = loc.name;
    ref.read(directionsProvider.notifier).setOrigin(loc);
    setState(() { _originResults = []; _showOriginResults = false; });
  }

  void _swap() {
    HapticFeedback.selectionClick();
    final dir = ref.read(directionsProvider);
    final tmpOrigin = dir.origin;
    final tmpDest   = dir.destination;
    final tmpOText  = _originCtrl.text;
    _originCtrl.text = _destCtrl.text;
    _destCtrl.text   = tmpOText;
    ref.read(directionsProvider.notifier).setOrigin(tmpDest);
    ref.read(directionsProvider.notifier).setDestination(tmpOrigin);
    _calcRoute();
  }

  Future<void> _calcRoute() async {
    final dir = ref.read(directionsProvider);
    if (dir.origin == null || dir.destination == null) return;
    final routes = await ref.read(directionsProvider.notifier).calculate(widget.transportMode);
    if (routes.isNotEmpty) {
      widget.onRouteCalculated(routes.first);
      // save to recent
      final dest = dir.destination;
      if (dest != null && dest.name != 'Joriy joylashuv') {
        ref.read(savedPlacesProvider.notifier).addRecent(
          SavedPlace(id: 'r_${DateTime.now().millisecondsSinceEpoch}', name: dest.name, lat: dest.lat, lng: dest.lng),
        );
      }
    } else {
      widget.onRouteCalculated(null);
    }
  }

  void _shareRoute() {
    final dir = ref.read(directionsProvider);
    if (dir.origin == null || dir.destination == null) return;
    final url = 'https://www.google.com/maps/dir/${dir.origin!.lat},${dir.origin!.lng}/${dir.destination!.lat},${dir.destination!.lng}';
    Clipboard.setData(ClipboardData(text: url));
    AppToast.success(context, "Havola nusxalandi!");
  }

  void _handleClose() {
    ref.read(directionsProvider.notifier).clearRoute();
    widget.onRouteCalculated(null);
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final c       = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final dir     = ref.watch(directionsProvider);
    final saved   = ref.watch(savedPlacesProvider);

    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: c.background,
        border: Border(right: BorderSide(color: c.border)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(2, 0))],
      ),
      child: Column(children: [
        _buildHeader(c, primary),
        _buildTransportBar(primary),
        _buildInputs(c, primary, dir, saved),
        if (!dir.navigating && _showSuggestions && dir.routes.isEmpty && !dir.loading &&
            (saved.favorites.isNotEmpty || saved.recent.isNotEmpty))
          _buildSuggestions(c, primary, saved),
        if (dir.loading)  _buildLoading(c, primary),
        if (dir.error != null && !dir.loading) _buildError(c, dir.error!),
        if (dir.selectedRoute != null && !dir.navigating)  ...[
          _buildRouteSummary(c, primary, dir),
          Expanded(child: _buildStepsList(c, primary, dir)),
        ],
        if (dir.navigating && dir.selectedRoute != null && dir.currentStep != null)
          Expanded(child: _buildNavigation(c, primary, dir)),
      ]),
    );
  }

  // ─── HEADER ────────────────────────────────────────────────────────────
  Widget _buildHeader(AlsamosColors c, Color primary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
        gradient: LinearGradient(colors: [primary.withValues(alpha: 0.08), primary.withValues(alpha: 0.02)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
          child: Icon(LucideIcons.navigation, size: 20, color: primary),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text("Yo'nalishlar", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.foreground)),
          Text('Marshrutni rejalashtiring', style: TextStyle(fontSize: 12, color: c.mutedForeground)),
        ])),
        IconButton(
          icon: Icon(LucideIcons.x, size: 20, color: c.mutedForeground),
          onPressed: _handleClose,
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(36, 36),
          ),
        ),
      ]),
    );
  }

  Widget _buildTransportBar(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
      child: TransportQuickBar(selected: widget.transportMode, onSelect: (m) {
        widget.onTransportModeChange(m);
        _calcRoute();
      }),
    );
  }

  // ─── INPUTS ────────────────────────────────────────────────────────────
  Widget _buildInputs(AlsamosColors c, Color primary, DirectionsState dir, SavedPlacesState saved) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.3),
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Column(children: [
        // Origin row
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Column(children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: primary, border: Border.all(color: primary.withValues(alpha: 0.3), width: 3))),
            Container(width: 2, height: 36, decoration: BoxDecoration(gradient: LinearGradient(colors: [primary.withValues(alpha: 0.6), Colors.red.withValues(alpha: 0.6)], begin: Alignment.topCenter, end: Alignment.bottomCenter))),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Stack(children: [
            TextField(
              controller: _originCtrl,
              onChanged: (q) { _onSearchChanged(q, 'origin'); setState(() => _activeSearch = 'origin'); },
              onTap: () { setState(() { _activeSearch = 'origin'; _showSuggestions = true; }); },
              decoration: InputDecoration(
                hintText: 'Qayerdan...',
                contentPadding: const EdgeInsets.only(left: 12, right: 80, top: 12, bottom: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border.withValues(alpha: 0.6))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border.withValues(alpha: 0.6))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primary.withValues(alpha: 0.6), width: 2)),
                filled: true, fillColor: c.background,
              ),
            ),
            Positioned(right: 4, top: 0, bottom: 0, child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (widget.onMapSelectionModeChange != null)
                _InputIconBtn(icon: LucideIcons.crosshair, active: widget.mapSelectionMode == 'origin', activeColor: primary,
                  onTap: () => widget.onMapSelectionModeChange?.call(widget.mapSelectionMode == 'origin' ? null : 'origin')),
              if (widget.currentLocation != null)
                _InputIconBtn(icon: LucideIcons.locate, activeColor: primary, onTap: _useCurrentLocation),
              if (_originCtrl.text.isNotEmpty)
                _InputIconBtn(icon: LucideIcons.x, activeColor: c.mutedForeground, onTap: () {
                  _originCtrl.clear();
                  ref.read(directionsProvider.notifier).setOrigin(null);
                  setState(() => _originResults = []);
                }),
            ])),
          ])),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _swap,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(12), color: c.background),
              child: Icon(LucideIcons.arrowUpDown, size: 16, color: c.foreground),
            ),
          ),
        ]),
        // Origin results dropdown
        if (_showOriginResults && _originResults.isNotEmpty)
          _buildResultsDropdown(_originResults, 'origin', primary, c),
        const SizedBox(height: 8),
        // Destination row
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFEF4444), border: Border.fromBorderSide(BorderSide(color: Color(0x4DEF4444), width: 3)))),
          const SizedBox(width: 12),
          Expanded(child: Stack(children: [
            TextField(
              controller: _destCtrl,
              onChanged: (q) { _onSearchChanged(q, 'destination'); setState(() => _activeSearch = 'destination'); },
              onTap: () { setState(() { _activeSearch = 'destination'; _showSuggestions = true; }); },
              decoration: InputDecoration(
                hintText: 'Qayerga...',
                contentPadding: const EdgeInsets.only(left: 12, right: 64, top: 12, bottom: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border.withValues(alpha: 0.6))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border.withValues(alpha: 0.6))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0x66EF4444), width: 2)),
                filled: true, fillColor: c.background,
              ),
            ),
            Positioned(right: 4, top: 0, bottom: 0, child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (widget.onMapSelectionModeChange != null)
                _InputIconBtn(icon: LucideIcons.crosshair, active: widget.mapSelectionMode == 'destination', activeColor: const Color(0xFFEF4444),
                  onTap: () => widget.onMapSelectionModeChange?.call(widget.mapSelectionMode == 'destination' ? null : 'destination')),
              if (_destCtrl.text.isNotEmpty)
                _InputIconBtn(icon: LucideIcons.x, activeColor: c.mutedForeground, onTap: () {
                  _destCtrl.clear();
                  ref.read(directionsProvider.notifier).setDestination(null);
                  ref.read(directionsProvider.notifier).clearRoute();
                  widget.onRouteCalculated(null);
                  setState(() => _destResults = []);
                }),
            ])),
          ])),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => widget.onMapSelectionModeChange?.call(widget.mapSelectionMode == 'destination' ? null : 'destination'),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: widget.mapSelectionMode == 'destination' ? const Color(0xFFEF4444) : c.border),
                borderRadius: BorderRadius.circular(12),
                color: widget.mapSelectionMode == 'destination' ? const Color(0xFFEF4444) : c.background,
              ),
              child: Icon(LucideIcons.mapPin, size: 16, color: widget.mapSelectionMode == 'destination' ? Colors.white : c.foreground),
            ),
          ),
        ]),
        if (_showDestResults && _destResults.isNotEmpty)
          _buildResultsDropdown(_destResults, 'destination', const Color(0xFFEF4444), c),
      ]),
    );
  }

  Widget _buildResultsDropdown(List<SearchResult> results, String type, Color accent, AlsamosColors c) {
    return Container(
      margin: const EdgeInsets.only(top: 4, left: 24, right: 48),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12)]),
      child: ListView.builder(
        padding: const EdgeInsets.all(6),
        shrinkWrap: true,
        itemCount: results.length,
        itemBuilder: (_, i) {
          final r = results[i];
          final title = r.displayName.split(',').first;
          final subtitle = r.displayName.split(',').skip(1).take(2).join(',');
          return InkWell(
            onTap: () => _selectResult(r, type),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Icon(LucideIcons.mapPin, size: 16, color: c.mutedForeground),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.foreground), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle.isNotEmpty) Text(subtitle, style: TextStyle(fontSize: 11, color: c.mutedForeground), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ─── SUGGESTIONS (Favorites + Recent) ──────────────────────────────────
  Widget _buildSuggestions(AlsamosColors c, Color primary, SavedPlacesState saved) {
    return DefaultTabController(
      length: 2,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TabBar(
          labelColor: primary, unselectedLabelColor: c.mutedForeground,
          indicatorColor: primary, dividerColor: c.border,
          tabs: const [
            Tab(icon: Icon(LucideIcons.star, size: 14), text: 'Sevimlilar', height: 40),
            Tab(icon: Icon(LucideIcons.history, size: 14), text: 'Oxirgi', height: 40),
          ],
        ),
        SizedBox(height: 140, child: TabBarView(children: [
          // Favorites
          saved.favorites.isEmpty
            ? Center(child: Text("Sevimli joylar yo'q", style: TextStyle(fontSize: 12, color: c.mutedForeground)))
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: saved.favorites.take(5).length,
                itemBuilder: (_, i) {
                  final p = saved.favorites[i];
                  return _SavedPlaceTile(place: p, colors: c, primary: primary, onTap: () => _selectSavedPlace(p, _activeSearch ?? 'destination'));
                },
              ),
          // Recent
          saved.recent.isEmpty
            ? Center(child: Text("Oxirgi qidiruvlar yo'q", style: TextStyle(fontSize: 12, color: c.mutedForeground)))
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: saved.recent.take(5).length,
                itemBuilder: (_, i) {
                  final p = saved.recent[i];
                  return _SavedPlaceTile(place: p, colors: c, primary: primary, isRecent: true,
                    onTap: () => _selectSavedPlace(p, _activeSearch ?? 'destination'),
                    onFavorite: () => ref.read(savedPlacesProvider.notifier).toggleFavorite(p),
                  );
                },
              ),
        ])),
      ]),
    );
  }

  // ─── LOADING ────────────────────────────────────────────────────────────
  Widget _buildLoading(AlsamosColors c, Color primary) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 36, height: 36, child: CircularProgressIndicator(color: primary, strokeWidth: 3)),
        const SizedBox(height: 12),
        Text("Yo'l hisoblanmoqda...", style: TextStyle(fontSize: 13, color: c.mutedForeground)),
      ]),
    );
  }

  // ─── ERROR ──────────────────────────────────────────────────────────────
  Widget _buildError(AlsamosColors c, String error) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0x1AEF4444), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x33EF4444))),
      child: Row(children: [
        const Icon(LucideIcons.alertCircle, color: Color(0xFFEF4444), size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(error, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13))),
      ]),
    );
  }

  // ─── ROUTE SUMMARY ──────────────────────────────────────────────────────
  Widget _buildRouteSummary(AlsamosColors c, Color primary, DirectionsState dir) {
    final route = dir.selectedRoute!;
    final isFav = dir.destination != null && ref.read(savedPlacesProvider).favorites.any(
      (p) => (p.lat - dir.destination!.lat).abs() < 0.0001 && (p.lng - dir.destination!.lng).abs() < 0.0001,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
        gradient: LinearGradient(colors: [primary.withValues(alpha: 0.07), primary.withValues(alpha: 0.02)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.clock, size: 20, color: primary),
          const SizedBox(width: 8),
          Flexible(child: Text(formatDuration(route.duration), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c.foreground))),
          const SizedBox(width: 16),
          Icon(LucideIcons.route, size: 16, color: c.mutedForeground),
          const SizedBox(width: 4),
          Flexible(child: Text(formatDistance(route.distance), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.mutedForeground))),
          const SizedBox(width: 8),
          Icon(LucideIcons.calendar, size: 14, color: c.mutedForeground),
          const SizedBox(width: 4),
          Flexible(child: Text('${_arrivalTime(route.duration)} da yetish', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.mutedForeground))),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: FilledButton.icon(
            onPressed: () { ref.read(directionsProvider.notifier).startNavigation(); HapticFeedback.mediumImpact(); },
            icon: const Icon(LucideIcons.play, size: 16),
            label: const Text('Boshlash'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
          const SizedBox(width: 8),
          _IconOutlinedBtn(icon: isFav ? LucideIcons.star : LucideIcons.starOff, color: isFav ? const Color(0xFFF59E0B) : c.mutedForeground, onTap: () {
            if (dir.destination != null) {
              ref.read(savedPlacesProvider.notifier).toggleFavorite(SavedPlace(id: 'fav_${DateTime.now().millisecondsSinceEpoch}', name: dir.destination!.name, lat: dir.destination!.lat, lng: dir.destination!.lng, isFavorite: true, icon: 'star'));
            }
          }),
          const SizedBox(width: 8),
          _IconOutlinedBtn(icon: LucideIcons.share2, color: c.mutedForeground, onTap: _shareRoute),
        ]),
        // alternatives
        if (dir.routes.length > 1) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            for (var i = 0; i < dir.routes.length; i++) ...[
              GestureDetector(
                onTap: () { ref.read(directionsProvider.notifier).selectRoute(i); widget.onRouteCalculated(dir.routes[i]); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: dir.selectedRouteIndex == i ? primary : c.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: dir.selectedRouteIndex == i ? primary : c.border),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(formatDuration(dir.routes[i].duration), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: dir.selectedRouteIndex == i ? Colors.white : c.foreground)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: dir.selectedRouteIndex == i ? Colors.white.withValues(alpha: 0.3) : c.muted, borderRadius: BorderRadius.circular(4)),
                      child: Text(formatDistance(dir.routes[i].distance), style: TextStyle(fontSize: 10, color: dir.selectedRouteIndex == i ? Colors.white : c.mutedForeground)),
                    ),
                  ]),
                ),
              ),
            ],
          ])),
        ],
      ]),
    );
  }

  // ─── STEPS LIST ─────────────────────────────────────────────────────────
  Widget _buildStepsList(AlsamosColors c, Color primary, DirectionsState dir) {
    final route = dir.selectedRoute!;
    return Column(children: [
      InkWell(
        onTap: () => setState(() => _expandedSteps = !_expandedSteps),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border), bottom: _expandedSteps ? BorderSide(color: c.border) : BorderSide.none)),
          child: Row(children: [
            Text("Yo'l ko'rsatmalari (${route.steps.length})", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.mutedForeground)),
            const Spacer(),
            Icon(_expandedSteps ? LucideIcons.chevronDown : LucideIcons.chevronUp, size: 16, color: c.mutedForeground),
          ]),
        ),
      ),
      if (_expandedSteps)
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: route.steps.length,
          itemBuilder: (_, i) {
            final step = route.steps[i];
            return InkWell(
              onTap: () => widget.onStepSelected?.call((lat: step.location.latitude, lng: step.location.longitude)),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Column(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Icon(maneuverIcon(step.maneuverType, step.maneuverModifier), size: 16)),
                    ),
                    if (i < route.steps.length - 1) Container(width: 2, height: 20, color: c.border, margin: const EdgeInsets.symmetric(vertical: 3)),
                  ]),
                  const SizedBox(width: 12),
                  Expanded(child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(step.instruction, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.foreground)),
                      const SizedBox(height: 3),
                      Row(children: [
                        Text(formatDistance(step.distance), style: TextStyle(fontSize: 11, color: c.mutedForeground)),
                        Text(' • ', style: TextStyle(fontSize: 11, color: c.mutedForeground)),
                        Text(formatDuration(step.duration), style: TextStyle(fontSize: 11, color: c.mutedForeground)),
                      ]),
                    ]),
                  )),
                  Icon(LucideIcons.chevronRight, size: 16, color: c.mutedForeground),
                ]),
              ),
            );
          },
        )),
    ]);
  }

  // ─── NAVIGATION MODE ────────────────────────────────────────────────────
  Widget _buildNavigation(AlsamosColors c, Color primary, DirectionsState dir) {
    final route   = dir.selectedRoute!;
    final step    = dir.currentStep!;
    final stepIdx = dir.currentStepIndex;
    return Column(children: [
      // Current step hero
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [primary.withValues(alpha: 0.15), primary.withValues(alpha: 0.05)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(color: primary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16)),
            child: Center(child: Icon(maneuverIcon(step.maneuverType, step.maneuverModifier), size: 28)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(step.instruction, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: c.foreground)),
            const SizedBox(height: 6),
            Row(children: [
              _StepBadge(text: formatDistance(step.distance), icon: LucideIcons.route, c: c, primary: primary),
              const SizedBox(width: 8),
              _StepBadge(text: formatDuration(step.duration), icon: LucideIcons.clock, c: c, outlined: true),
            ]),
          ])),
        ]),
      ),
      // Progress bar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(color: c.muted.withValues(alpha: 0.3), border: Border(bottom: BorderSide(color: c.border))),
        child: Column(children: [
          Row(children: [
            Text('Qadam ${stepIdx + 1} / ${route.steps.length}', style: TextStyle(fontSize: 12, color: c.mutedForeground)),
            const Spacer(),
            Icon(LucideIcons.checkCircle, size: 14, color: primary),
            const SizedBox(width: 4),
            Text('${_arrivalTime(route.duration)} da yetish', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.foreground)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
            value: (stepIdx + 1) / route.steps.length,
            minHeight: 6,
            backgroundColor: c.muted,
            valueColor: AlwaysStoppedAnimation<Color>(primary),
          )),
        ]),
      ),
      // Upcoming steps
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('KEYINGI QADAMLAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.mutedForeground, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        ...route.steps.skip(stepIdx + 1).take(3).map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Container(width: 32, height: 32, decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(8)), child: Center(child: Icon(maneuverIcon(s.maneuverType, s.maneuverModifier), size: 14))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.instruction, style: TextStyle(fontSize: 12, color: c.foreground), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(formatDistance(s.distance), style: TextStyle(fontSize: 11, color: c.mutedForeground)),
            ])),
          ]),
        )),
      ])),
      // Controls
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.background, border: Border(top: BorderSide(color: c.border))),
        child: Row(children: [
          _NavBtn(icon: LucideIcons.chevronLeft, onTap: () => ref.read(directionsProvider.notifier).prevStep(), enabled: stepIdx > 0, c: c),
          const SizedBox(width: 12),
          Expanded(child: FilledButton.icon(
            onPressed: () { ref.read(directionsProvider.notifier).stopNavigation(); HapticFeedback.mediumImpact(); },
            icon: const Icon(LucideIcons.square, size: 16),
            label: const Text("To'xtatish"),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444), padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
          const SizedBox(width: 12),
          _NavBtn(icon: LucideIcons.chevronRight, onTap: () => ref.read(directionsProvider.notifier).nextStep(), enabled: stepIdx < route.steps.length - 1, c: c),
        ]),
      ),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Small helper widgets
// ═══════════════════════════════════════════════════════════════════════════

class _InputIconBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  const _InputIconBtn({required this.icon, required this.activeColor, required this.onTap, this.active = false});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(color: active ? activeColor : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 14, color: active ? Colors.white : activeColor),
      ),
    );
  }
}

class _IconOutlinedBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _IconOutlinedBtn({required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(12), color: c.background),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  final String text;
  final IconData icon;
  final AlsamosColors c;
  final Color? primary;
  final bool outlined;
  const _StepBadge({required this.text, required this.icon, required this.c, this.primary, this.outlined = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : (primary?.withValues(alpha: 0.15) ?? c.muted),
        border: outlined ? Border.all(color: c.border) : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: outlined ? c.mutedForeground : (primary ?? c.mutedForeground)),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: outlined ? c.mutedForeground : (primary ?? c.mutedForeground))),
      ]),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final AlsamosColors c;
  const _NavBtn({required this.icon, required this.onTap, required this.enabled, required this.c});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(12), color: c.background),
        child: Icon(icon, size: 20, color: enabled ? c.foreground : c.mutedForeground),
      ),
    );
  }
}

class _SavedPlaceTile extends StatelessWidget {
  final SavedPlace place;
  final AlsamosColors colors;
  final Color primary;
  final bool isRecent;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  const _SavedPlaceTile({required this.place, required this.colors, required this.primary, required this.onTap, this.isRecent = false, this.onFavorite});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: isRecent ? colors.muted : primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(isRecent ? LucideIcons.history : LucideIcons.star, size: 16, color: isRecent ? colors.mutedForeground : primary),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(place.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.foreground), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (onFavorite != null)
            GestureDetector(onTap: onFavorite, child: Icon(LucideIcons.star, size: 16, color: colors.mutedForeground)),
        ]),
      ),
    );
  }
}
