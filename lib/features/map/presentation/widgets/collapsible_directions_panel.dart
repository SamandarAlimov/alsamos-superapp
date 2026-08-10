// Collapsible Directions Panel (Desktop/Tablet only)
// Similar to existing DirectionsPanel but with collapse/expand toggle and optional resize
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/map_models.dart';
import '../providers/map_provider.dart';
import 'transport_mode_picker.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Collapsible Directions Panel (Desktop - with toggle + resize)
// ═══════════════════════════════════════════════════════════════════════════
class CollapsibleDirectionsPanel extends ConsumerStatefulWidget {
  final bool collapsed;
  final ValueChanged<bool> onCollapsedChange;
  final ({double lat, double lng})? currentLocation;
  final ({double lat, double lng, String name})? initialDestination;
  final TransportMode transportMode;
  final ValueChanged<TransportMode> onTransportModeChange;
  final ValueChanged<RouteAlternative?> onRouteCalculated;
  final ValueChanged<({double lat, double lng})>? onStepSelected;
  final VoidCallback onClose;
  final String? mapSelectionMode;
  final ValueChanged<String?>? onMapSelectionModeChange;
  final ({double lat, double lng, String name})? selectedMapLocation;
  final VoidCallback? onClearSelectedMapLocation;

  const CollapsibleDirectionsPanel({
    super.key,
    this.collapsed = false,
    required this.onCollapsedChange,
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
  ConsumerState<CollapsibleDirectionsPanel> createState() =>
      _CollapsibleDirectionsPanelState();
}

class _CollapsibleDirectionsPanelState
    extends ConsumerState<CollapsibleDirectionsPanel>
    with TickerProviderStateMixin {
  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  Timer? _debounce;

  // Panel width state (resizable)
  double _panelWidth = 400;
  static const _minWidth = 320.0;
  static const _maxWidth = 600.0;

  // Collapse animation
  late AnimationController _collapseAnim;
  late Animation<double> _widthAnim;

  @override
  void initState() {
    super.initState();
    _collapseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _widthAnim = Tween<double>(
      begin: widget.collapsed ? 0 : _panelWidth,
      end: widget.collapsed ? 0 : _panelWidth,
    ).animate(CurvedAnimation(parent: _collapseAnim, curve: Curves.easeOut));
    
    if (!widget.collapsed) {
      _collapseAnim.value = 1.0;
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) => _initState());
  }

  void _initState() {
    if (!mounted) return;
    final dir = ref.read(directionsProvider);
    if (widget.currentLocation != null && dir.origin == null) {
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
    }
  }

  @override
  void didUpdateWidget(CollapsibleDirectionsPanel old) {
    super.didUpdateWidget(old);
    
    // Animate collapse/expand
    if (widget.collapsed != old.collapsed) {
      _animateCollapse(widget.collapsed);
    }
    
    // Handle map selection
    final sel = widget.selectedMapLocation;
    if (sel != null && widget.mapSelectionMode != null) {
      if (widget.mapSelectionMode == 'origin') {
        _originCtrl.text = sel.name;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(directionsProvider.notifier).setOrigin(sel);
          }
        });
      } else {
        _destCtrl.text = sel.name;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(directionsProvider.notifier).setDestination(sel);
          }
        });
      }
      widget.onMapSelectionModeChange?.call(null);
      widget.onClearSelectedMapLocation?.call();
    }
    
    // Update origin when currentLocation arrives late
    final dir = ref.read(directionsProvider);
    if (widget.currentLocation != null && dir.origin == null) {
      _originCtrl.text = 'Joriy joylashuv';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(directionsProvider.notifier).setOrigin((
            lat: widget.currentLocation!.lat,
            lng: widget.currentLocation!.lng,
            name: 'Joriy joylashuv',
          ));
        }
      });
    }
    
    // Auto-calc if both set
    if (dir.origin != null &&
        dir.destination != null &&
        dir.routes.isEmpty &&
        !dir.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _calcRoute();
        }
      });
    }
  }

  @override
  void dispose() {
    _originCtrl.dispose();
    _destCtrl.dispose();
    _debounce?.cancel();
    _collapseAnim.dispose();
    super.dispose();
  }

  void _animateCollapse(bool collapse) {
    _widthAnim = Tween<double>(
      begin: collapse ? _panelWidth : 0,
      end: collapse ? 0 : _panelWidth,
    ).animate(CurvedAnimation(parent: _collapseAnim, curve: Curves.easeOut));
    
    if (collapse) {
      _collapseAnim.reverse();
    } else {
      _collapseAnim.forward();
    }
  }

  Future<void> _calcRoute() async {
    final dir = ref.read(directionsProvider);
    if (dir.origin == null || dir.destination == null) return;
    final routes = await ref
        .read(directionsProvider.notifier)
        .calculate(widget.transportMode);
    if (routes.isNotEmpty) {
      widget.onRouteCalculated(routes.first);
      final dest = dir.destination;
      if (dest != null && dest.name != 'Joriy joylashuv') {
        ref.read(savedPlacesProvider.notifier).addRecent(
              SavedPlace(
                id: 'r_${DateTime.now().millisecondsSinceEpoch}',
                name: dest.name,
                lat: dest.lat,
                lng: dest.lng,
              ),
            );
      }
    } else {
      widget.onRouteCalculated(null);
    }
  }

  void _handleClose() {
    ref.read(directionsProvider.notifier).clearRoute();
    widget.onRouteCalculated(null);
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final dir = ref.watch(directionsProvider);

    return AnimatedBuilder(
      animation: _widthAnim,
      builder: (context, child) {
        final width = _widthAnim.value;
        
        return Row(mainAxisSize: MainAxisSize.min, children: [
          // Main panel content
          if (width > 0)
            SizedBox(
              width: width,
              child: Container(
                decoration: BoxDecoration(
                  color: c.background,
                  border: Border(right: BorderSide(color: c.border)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(2, 0),
                    ),
                  ],
                ),
                child: Column(children: [
                  _buildHeader(c),
                  _buildTransportBar(c),
                  _buildInputs(c, dir),
                  if (!dir.navigating &&
                      dir.routes.isEmpty &&
                      !dir.loading)
                    _buildSuggestions(c),
                  if (dir.loading) _buildLoading(c),
                  if (dir.error != null && !dir.loading) _buildError(c, dir.error!),
                  if (dir.selectedRoute != null && !dir.navigating) ...[
                    _buildRouteSummary(c, dir),
                    Expanded(child: _buildStepsList(c, dir)),
                  ],
                  if (dir.navigating &&
                      dir.selectedRoute != null &&
                      dir.currentStep != null)
                    Expanded(child: _buildNavigation(c, dir)),
                ]),
              ),
            ),
          // Toggle button (always visible)
          _buildToggleButton(c),
          // Resize handle (only when expanded)
          if (!widget.collapsed && width > 0) _buildResizeHandle(c),
        ]);
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // UI BUILDERS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildToggleButton(AlsamosColors c) {
    return GestureDetector(
      onTap: () => widget.onCollapsedChange(!widget.collapsed),
      child: Container(
        width: 32,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 14),
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(color: c.border),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(6),
            bottomRight: Radius.circular(6),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
            ),
          ],
        ),
        child: Icon(
          widget.collapsed ? LucideIcons.chevronRight : LucideIcons.chevronLeft,
          size: 16,
          color: c.foreground,
        ),
      ),
    );
  }

  Widget _buildResizeHandle(AlsamosColors c) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          setState(() {
            _panelWidth = (_panelWidth + details.delta.dx)
                .clamp(_minWidth, _maxWidth);
          });
        },
        child: Container(
          width: 8,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: c.border)),
          ),
          child: Center(
            child: Container(
              width: 2,
              height: 40,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AlsamosColors c) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
        gradient: LinearGradient(
          colors: [
            primary.withValues(alpha: 0.08),
            primary.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(LucideIcons.navigation, size: 20, color: primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Yo'nalishlar",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.foreground,
                ),
              ),
              Text(
                'Marshrutni rejalashtiring',
                style: TextStyle(fontSize: 12, color: c.mutedForeground),
              ),
            ],
          ),
        ),
        // Minimize button
        IconButton(
          icon: Icon(LucideIcons.minus, size: 18, color: c.mutedForeground),
          onPressed: () => widget.onCollapsedChange(true),
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(32, 32),
          ),
          tooltip: 'Minimallashtirish',
        ),
        // Close button
        IconButton(
          icon: Icon(LucideIcons.x, size: 20, color: c.mutedForeground),
          onPressed: _handleClose,
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(36, 36),
          ),
          tooltip: 'Yopish',
        ),
      ]),
    );
  }

  Widget _buildTransportBar(AlsamosColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
      child: TransportQuickBar(
        selected: widget.transportMode,
        onSelect: (m) {
          widget.onTransportModeChange(m);
          _calcRoute();
        },
      ),
    );
  }

  // Remaining methods (_buildInputs, _buildSuggestions, _buildLoading, etc.)
  // are identical to DirectionsPanel, so reuse that logic or import from there
  
  Widget _buildInputs(AlsamosColors c, DirectionsState dir) {
    // Same as DirectionsPanel._buildInputs
    return const SizedBox.shrink(); // Placeholder - copy from DirectionsPanel
  }

  Widget _buildSuggestions(AlsamosColors c) {
    return const SizedBox.shrink(); // Placeholder
  }

  Widget _buildLoading(AlsamosColors c) {
    return const SizedBox.shrink(); // Placeholder
  }

  Widget _buildError(AlsamosColors c, String error) {
    return const SizedBox.shrink(); // Placeholder
  }

  Widget _buildRouteSummary(AlsamosColors c, DirectionsState dir) {
    return const SizedBox.shrink(); // Placeholder
  }

  Widget _buildStepsList(AlsamosColors c, DirectionsState dir) {
    return const SizedBox.shrink(); // Placeholder
  }

  Widget _buildNavigation(AlsamosColors c, DirectionsState dir) {
    return const SizedBox.shrink(); // Placeholder
  }
}
