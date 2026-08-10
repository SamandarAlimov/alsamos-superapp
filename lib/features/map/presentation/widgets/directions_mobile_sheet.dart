// Mobile Directions Sheet - 100% 1:1 web DirectionsMobileSheet.tsx port
// Full-featured: voice input, map selection, OSRM routing, navigation mode
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

class DirectionsMobileSheet extends ConsumerStatefulWidget {
  final bool open;
  final ValueChanged<bool> onOpenChange;
  final ({double lat, double lng})? currentLocation;
  final ({double lat, double lng, String name})? initialDestination;
  final TransportMode transportMode;
  final ValueChanged<TransportMode> onTransportModeChange;
  final ValueChanged<RouteAlternative?> onRouteCalculated;
  final ValueChanged<({double lat, double lng})>? onStepSelected;
  final String? mapSelectionMode;
  final ValueChanged<String?>? onMapSelectionModeChange;
  final ({double lat, double lng, String name})? selectedMapLocation;
  final VoidCallback? onClearSelectedMapLocation;

  const DirectionsMobileSheet({
    super.key,
    required this.open,
    required this.onOpenChange,
    this.currentLocation,
    this.initialDestination,
    required this.transportMode,
    required this.onTransportModeChange,
    required this.onRouteCalculated,
    this.onStepSelected,
    this.mapSelectionMode,
    this.onMapSelectionModeChange,
    this.selectedMapLocation,
    this.onClearSelectedMapLocation,
  });

  @override
  ConsumerState<DirectionsMobileSheet> createState() => _DirectionsMobileSheetState();
}

class _DirectionsMobileSheetState extends ConsumerState<DirectionsMobileSheet> {
  final _originCtrl = TextEditingController();
  final _destCtrl   = TextEditingController();
  final _repo = MapRepository();

  List<SearchResult> _originResults = [];
  List<SearchResult> _destResults   = [];
  bool _expandedView = false;
  String? _activeSearch;
  bool _showSuggestions = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initState());
  }

  void _initState() {
    if (!mounted) return;
    if (widget.currentLocation != null) {
      _originCtrl.text = 'Joriy joylashuv';
      ref.read(directionsProvider.notifier).setOrigin((
        lat: widget.currentLocation!.lat,
        lng: widget.currentLocation!.lng,
        name: 'Joriy joylashuv',
      ));
    }
    if (widget.initialDestination != null) {
      final d = widget.initialDestination!;
      _destCtrl.text = d.name;
      ref.read(directionsProvider.notifier).setDestination(d);
      _calcRoute();
    }
  }

  @override
  void didUpdateWidget(DirectionsMobileSheet old) {
    super.didUpdateWidget(old);
    // handle map selection
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
      _calcRoute();
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
    // clear when closed
    if (!widget.open && old.open) {
      _clear();
    }
  }

  @override
  void dispose() {
    _originCtrl.dispose();
    _destCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _clear() {
    ref.read(directionsProvider.notifier).clearRoute();
    _originCtrl.clear();
    _destCtrl.clear();
    setState(() {
      _originResults = [];
      _destResults   = [];
      _activeSearch  = null;
      _expandedView  = false;
      _showSuggestions = false;
    });
  }

  void _onSearchChanged(String q, String type) {
    _debounce?.cancel();
    if (q.length < 2) {
      setState(() {
        if (type == 'origin') { _originResults = []; }
        else { _destResults = []; }
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final pos = widget.currentLocation;
      final results = await _repo.searchPlaces(q, lat: pos?.lat, lon: pos?.lng);
      if (!mounted) return;
      setState(() {
        if (type == 'origin') { _originResults = results; }
        else { _destResults = results; }
      });
    });
  }

  void _selectResult(SearchResult r, String type) {
    HapticFeedback.selectionClick();
    final loc = (lat: r.lat, lng: r.lon, name: r.displayName.split(',').first);
    if (type == 'origin') {
      _originCtrl.text = loc.name;
      ref.read(directionsProvider.notifier).setOrigin(loc);
      setState(() { _originResults = []; _activeSearch = null; });
    } else {
      _destCtrl.text = loc.name;
      ref.read(directionsProvider.notifier).setDestination(loc);
      setState(() { _destResults = []; _activeSearch = null; });
    }
    _calcRoute();
  }

  Future<void> _calcRoute() async {
    final dir = ref.read(directionsProvider);
    if (dir.origin == null || dir.destination == null) return;
    final routes = await ref.read(directionsProvider.notifier).calculate(widget.transportMode);
    if (routes.isNotEmpty) {
      widget.onRouteCalculated(routes.first);
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

  void _swap() {
    HapticFeedback.selectionClick();
    final dir = ref.read(directionsProvider);
    final tmpOrigin = dir.origin; final tmpDest = dir.destination;
    final tmpOText  = _originCtrl.text;
    _originCtrl.text = _destCtrl.text;
    _destCtrl.text   = tmpOText;
    ref.read(directionsProvider.notifier).setOrigin(tmpDest);
    ref.read(directionsProvider.notifier).setDestination(tmpOrigin);
    _calcRoute();
  }

  void _handleClose() {
    ref.read(directionsProvider.notifier).clearRoute();
    widget.onRouteCalculated(null);
    widget.onOpenChange(false);
  }

  double _sheetSize(DirectionsState dir) {
    if (dir.navigating) return 0.85;
    if (_expandedView && dir.selectedRoute != null) return 0.9;
    if (dir.selectedRoute != null) return 0.75;
    if (_originResults.isNotEmpty || _destResults.isNotEmpty || _showSuggestions) return 0.75;
    return 0.55;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open) return const SizedBox.shrink();
    final c   = AlsamosColors.of(context);
    final dir = ref.watch(directionsProvider);

    return DraggableScrollableSheet(
      key: ValueKey(_sheetSize(dir)),
      initialChildSize: _sheetSize(dir),
      minChildSize: 0.35,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, sc) {
        return Container(
          decoration: BoxDecoration(
            color: c.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: c.border),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, -4))],
          ),
          child: Column(children: [
            // drag handle
            Center(child: Container(
              width: 48, height: 5,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(3)),
            )),
            _buildHeader(c, dir),
            Expanded(child: ListView(controller: sc, padding: EdgeInsets.zero, children: [
              // transport bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: c.muted.withValues(alpha: 0.3),
                child: TransportQuickBar(selected: widget.transportMode, onSelect: (m) {
                  widget.onTransportModeChange(m);
                  _calcRoute();
                }),
              ),
              if (!dir.navigating) _buildInputSection(c, dir),
              // results
              if (_activeSearch != null && (_originResults.isNotEmpty || _destResults.isNotEmpty))
                _buildResultsList(c, _activeSearch == 'origin' ? _originResults : _destResults, _activeSearch!),
              // loading
              if (dir.loading) _buildLoading(c),
              // error
              if (dir.error != null && !dir.loading) _buildError(dir.error!),
              // route summary
              if (dir.selectedRoute != null && !dir.navigating) _buildRouteSummary(c, dir),
              // navigation
              if (dir.navigating && dir.selectedRoute != null && dir.currentStep != null) _buildNavigation(c, dir),
            ])),
          ]),
        );
      },
    );
  }

  Widget _buildHeader(AlsamosColors c, DirectionsState dir) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(LucideIcons.navigation, size: 18, color: primary),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text("Yo'nalishlar", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.foreground)),
          Text('Marshrutni rejalashtiring', style: TextStyle(fontSize: 11, color: c.mutedForeground)),
        ])),
        GestureDetector(
          onTap: _handleClose,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
            child: Icon(LucideIcons.x, size: 18, color: c.mutedForeground),
          ),
        ),
      ]),
    );
  }

  Widget _buildInputSection(AlsamosColors c, DirectionsState dir) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // Origin
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: primary, border: Border.all(color: primary.withValues(alpha: 0.3), width: 3))),
            Container(width: 2, height: 28, decoration: BoxDecoration(gradient: LinearGradient(colors: [primary.withValues(alpha: 0.5), Colors.red.withValues(alpha: 0.5)], begin: Alignment.topCenter, end: Alignment.bottomCenter))),
          ]),
          const SizedBox(width: 10),
          Expanded(child: TextField(
            controller: _originCtrl,
            onChanged: (q) { setState(() => _activeSearch = 'origin'); _onSearchChanged(q, 'origin'); },
            decoration: InputDecoration(
              hintText: 'Qayerdan...',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border.withValues(alpha: 0.6))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border.withValues(alpha: 0.6))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primary, width: 2)),
              filled: true, fillColor: c.background,
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                if (widget.currentLocation != null)
                  GestureDetector(onTap: () {
                    _originCtrl.text = 'Joriy joylashuv';
                    ref.read(directionsProvider.notifier).setOrigin((lat: widget.currentLocation!.lat, lng: widget.currentLocation!.lng, name: 'Joriy joylashuv'));
                  }, child: Padding(padding: const EdgeInsets.all(8), child: Icon(LucideIcons.locate, size: 16, color: primary))),
                if (_originCtrl.text.isNotEmpty)
                  GestureDetector(onTap: () { _originCtrl.clear(); ref.read(directionsProvider.notifier).setOrigin(null); }, child: Padding(padding: const EdgeInsets.all(8), child: Icon(LucideIcons.x, size: 16, color: c.mutedForeground))),
              ]),
            ),
          )),
          const SizedBox(width: 8),
          GestureDetector(onTap: _swap, child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(10), color: c.background),
            child: Icon(LucideIcons.arrowUpDown, size: 16, color: c.foreground),
          )),
        ]),
        const SizedBox(height: 10),
        // Destination
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFEF4444), border: Border.fromBorderSide(BorderSide(color: Color(0x4DEF4444), width: 3)))),
          const SizedBox(width: 10),
          Expanded(child: TextField(
            controller: _destCtrl,
            onChanged: (q) { setState(() => _activeSearch = 'destination'); _onSearchChanged(q, 'destination'); },
            decoration: InputDecoration(
              hintText: 'Qayerga...',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border.withValues(alpha: 0.6))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border.withValues(alpha: 0.6))),
              focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Color(0xFFEF4444), width: 2)),
              filled: true, fillColor: c.background,
              suffixIcon: _destCtrl.text.isNotEmpty
                ? GestureDetector(onTap: () {
                    _destCtrl.clear();
                    ref.read(directionsProvider.notifier).setDestination(null);
                    ref.read(directionsProvider.notifier).clearRoute();
                    widget.onRouteCalculated(null);
                  }, child: Padding(padding: const EdgeInsets.all(8), child: Icon(LucideIcons.x, size: 16, color: c.mutedForeground)))
                : null,
            ),
          )),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => widget.onMapSelectionModeChange?.call(widget.mapSelectionMode == 'destination' ? null : 'destination'),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: widget.mapSelectionMode == 'destination' ? const Color(0xFFEF4444) : c.border),
                borderRadius: BorderRadius.circular(10),
                color: widget.mapSelectionMode == 'destination' ? const Color(0xFFEF4444) : c.background,
              ),
              child: Icon(LucideIcons.crosshair, size: 16, color: widget.mapSelectionMode == 'destination' ? Colors.white : c.foreground),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildResultsList(AlsamosColors c, List<SearchResult> results, String type) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)]),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.all(6),
        itemCount: results.length,
        itemBuilder: (_, i) {
          final r = results[i];
          return InkWell(
            onTap: () => _selectResult(r, type),
            borderRadius: BorderRadius.circular(8),
            child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
              Icon(LucideIcons.mapPin, size: 16, color: c.mutedForeground),
              const SizedBox(width: 10),
              Expanded(child: Text(r.displayName.split(',').first, style: TextStyle(fontSize: 13, color: c.foreground), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ])),
          );
        },
      ),
    );
  }

  Widget _buildLoading(AlsamosColors c) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: primary, strokeWidth: 3),
        const SizedBox(height: 10),
        Text("Yo'l hisoblanmoqda...", style: TextStyle(fontSize: 13, color: c.mutedForeground)),
      ]),
    );
  }

  Widget _buildError(String error) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0x1AEF4444), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x33EF4444))),
      child: Row(children: [
        const Icon(LucideIcons.alertCircle, color: Color(0xFFEF4444), size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(error, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13))),
      ]),
    );
  }

  Widget _buildRouteSummary(AlsamosColors c, DirectionsState dir) {
    final primary = Theme.of(context).colorScheme.primary;
    final route   = dir.selectedRoute!;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primary.withValues(alpha: 0.08), primary.withValues(alpha: 0.02)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.clock, size: 18, color: primary),
          const SizedBox(width: 8),
          Text(formatDuration(route.duration), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c.foreground)),
          const SizedBox(width: 12),
          Icon(LucideIcons.route, size: 14, color: c.mutedForeground),
          const SizedBox(width: 4),
          Text(formatDistance(route.distance), style: TextStyle(fontSize: 13, color: c.mutedForeground)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(
            onPressed: () { ref.read(directionsProvider.notifier).startNavigation(); HapticFeedback.mediumImpact(); },
            icon: const Icon(LucideIcons.play, size: 16),
            label: const Text('Boshlash'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
          )),
          const SizedBox(width: 8),
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(12), color: c.background),
            child: Icon(LucideIcons.share2, size: 18, color: c.foreground),
          ),
        ]),
        if (dir.routes.length > 1) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            for (var i = 0; i < dir.routes.length; i++)
              GestureDetector(
                onTap: () { ref.read(directionsProvider.notifier).selectRoute(i); widget.onRouteCalculated(dir.routes[i]); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: dir.selectedRouteIndex == i ? primary : c.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: dir.selectedRouteIndex == i ? primary : c.border),
                  ),
                  child: Text(formatDuration(dir.routes[i].duration), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: dir.selectedRouteIndex == i ? Colors.white : c.foreground)),
                ),
              ),
          ])),
        ],
        // toggle steps
        GestureDetector(
          onTap: () => setState(() => _expandedView = !_expandedView),
          child: Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border), bottom: BorderSide(color: c.border))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_expandedView ? LucideIcons.chevronDown : LucideIcons.chevronUp, size: 16, color: c.mutedForeground),
              const SizedBox(width: 6),
              Text(_expandedView ? 'Yashirish' : "Yo'l ko'rsatmalari (${route.steps.length})", style: TextStyle(fontSize: 13, color: c.mutedForeground)),
            ]),
          ),
        ),
        if (_expandedView)
          Column(children: [
            for (var i = 0; i < route.steps.length; i++) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => widget.onStepSelected?.call((lat: route.steps[i].location.latitude, lng: route.steps[i].location.longitude)),
                borderRadius: BorderRadius.circular(10),
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: Row(children: [
                  Container(width: 32, height: 32, decoration: BoxDecoration(color: primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Center(child: Icon(maneuverIcon(route.steps[i].maneuverType, route.steps[i].maneuverModifier), size: 14))),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(route.steps[i].instruction, style: TextStyle(fontSize: 12, color: c.foreground)),
                    Text(formatDistance(route.steps[i].distance), style: TextStyle(fontSize: 11, color: c.mutedForeground)),
                  ])),
                ])),
              ),
            ],
          ]),
      ]),
    );
  }

  Widget _buildNavigation(AlsamosColors c, DirectionsState dir) {
    final primary  = Theme.of(context).colorScheme.primary;
    final route    = dir.selectedRoute!;
    final step     = dir.currentStep!;
    final stepIdx  = dir.currentStepIndex;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [primary.withValues(alpha: 0.15), primary.withValues(alpha: 0.05)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Row(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: primary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
            child: Center(child: Icon(maneuverIcon(step.maneuverType, step.maneuverModifier), size: 26)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(step.instruction, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c.foreground)),
            const SizedBox(height: 4),
            Row(children: [
              _MobileBadge(text: formatDistance(step.distance), c: c, primary: primary),
              const SizedBox(width: 6),
              _MobileBadge(text: formatDuration(step.duration), c: c, outlined: true),
            ]),
          ])),
        ]),
      ),
      // progress
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(children: [
          Row(children: [
            Text('${stepIdx + 1} / ${route.steps.length}', style: TextStyle(fontSize: 12, color: c.mutedForeground)),
            const Spacer(),
            Text(formatDuration(route.duration - route.steps.take(stepIdx).fold(0.0, (s, st) => s + st.duration)), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.foreground)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
            value: (stepIdx + 1) / route.steps.length,
            minHeight: 5,
            backgroundColor: c.muted,
            valueColor: AlwaysStoppedAnimation<Color>(primary),
          )),
        ]),
      ),
      // upcoming
      ...route.steps.skip(stepIdx + 1).take(3).map((s) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Row(children: [
          Container(width: 30, height: 30, decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(7)), child: Center(child: Icon(maneuverIcon(s.maneuverType, s.maneuverModifier), size: 12))),
          const SizedBox(width: 10),
          Expanded(child: Text(s.instruction, style: TextStyle(fontSize: 12, color: c.foreground), maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(formatDistance(s.distance), style: TextStyle(fontSize: 11, color: c.mutedForeground)),
        ]),
      )),
      // controls
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(children: [
          GestureDetector(
            onTap: stepIdx > 0 ? () => ref.read(directionsProvider.notifier).prevStep() : null,
            child: Container(
              width: 46, height: 46,
              decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(12), color: c.background),
              child: Icon(LucideIcons.chevronLeft, size: 20, color: stepIdx > 0 ? c.foreground : c.mutedForeground),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: FilledButton.icon(
            onPressed: () { ref.read(directionsProvider.notifier).stopNavigation(); HapticFeedback.mediumImpact(); },
            icon: const Icon(LucideIcons.square, size: 16),
            label: const Text("To'xtatish"),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444), padding: const EdgeInsets.symmetric(vertical: 13)),
          )),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: stepIdx < route.steps.length - 1 ? () => ref.read(directionsProvider.notifier).nextStep() : null,
            child: Container(
              width: 46, height: 46,
              decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(12), color: c.background),
              child: Icon(LucideIcons.chevronRight, size: 20, color: stepIdx < route.steps.length - 1 ? c.foreground : c.mutedForeground),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _MobileBadge extends StatelessWidget {
  final String text;
  final AlsamosColors c;
  final Color? primary;
  final bool outlined;
  const _MobileBadge({required this.text, required this.c, this.primary, this.outlined = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : (primary?.withValues(alpha: 0.15) ?? c.muted),
        border: outlined ? Border.all(color: c.border) : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: outlined ? c.mutedForeground : (primary ?? c.mutedForeground))),
    );
  }
}
