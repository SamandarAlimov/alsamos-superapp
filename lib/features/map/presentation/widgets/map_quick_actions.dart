// Professional Map Quick Actions - 100% 1:1 match with alsamos-web MapQuickActions
// Provides quick access to nearby places (restaurants, gas, parking, etc.)
// with modern gradient pill buttons and smooth scrolling
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_theme.dart';

class _QuickAction {
  final String id;
  final IconData icon;
  final String label;
  final String query;
  final Color color;
  final Color bgColor;
  
  const _QuickAction(
    this.id,
    this.icon,
    this.label,
    this.query,
    this.color,
    this.bgColor,
  );
}

// Web version color scheme with background colors for pills
const List<_QuickAction> _actions = [
  _QuickAction('restaurants', LucideIcons.utensils, 'Ovqat', 'restaurant', 
      Color(0xFFF97316), Color(0xFFFFEDD5)),
  _QuickAction('gas', LucideIcons.fuel, "Yoqilg'i", 'gas_station', 
      Color(0xFFEF4444), Color(0xFFFFE4E6)),
  _QuickAction('parking', LucideIcons.circleParking, 'Parkovka', 'parking', 
      Color(0xFF3B82F6), Color(0xFFDBEAFE)),
  _QuickAction('coffee', LucideIcons.coffee, 'Kofe', 'cafe', 
      Color(0xFFD97706), Color(0xFFFEF3C7)),
  _QuickAction('shopping', LucideIcons.shoppingCart, "Do'kon", 'shopping_mall', 
      Color(0xFFA855F7), Color(0xFFF3E8FF)),
  _QuickAction('hotel', LucideIcons.hotel, 'Mehmonxona', 'hotel', 
      Color(0xFF14B8A6), Color(0xFFD1FAE5)),
  _QuickAction('hospital', LucideIcons.hospital, 'Shifoxona', 'hospital', 
      Color(0xFFDC2626), Color(0xFFFEE2E2)),
  _QuickAction('atm', LucideIcons.building2, 'Bankomat', 'atm', 
      Color(0xFF22C55E), Color(0xFFDCFCE7)),
  _QuickAction('bus', LucideIcons.bus, 'Bekat', 'bus_station', 
      Color(0xFF6366F1), Color(0xFFE0E7FF)),
  _QuickAction('metro', LucideIcons.train, 'Metro', 'subway_station', 
      Color(0xFFEF4444), Color(0xFFFFE4E6)),
  _QuickAction('university', LucideIcons.graduationCap, "Ta'lim", 'university', 
      Color(0xFF2563EB), Color(0xFFDBEAFE)),
  _QuickAction('government', LucideIcons.landmark, 'Davlat', 'local_government_office', 
      Color(0xFF64748B), Color(0xFFF1F5F9)),
];

Future<void> _openSearch(_QuickAction a, LatLng? location) async {
  if (location == null) return;
  final uri = Uri.parse(
    'https://www.google.com/maps/search/${a.query}/@${location.latitude},${location.longitude},15z',
  );
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Desktop/Tablet horizontal scrollable quick actions (web 1:1)
class MapQuickActions extends StatelessWidget {
  final LatLng? currentLocation;
  
  const MapQuickActions({super.key, this.currentLocation});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.5))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (final a in _actions)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _QuickActionPill(
                  action: a,
                  onPressed: () => _openSearch(a, currentLocation),
                  colors: c,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Modern pill button with gradient and icon (web 1:1 design)
class _QuickActionPill extends StatefulWidget {
  final _QuickAction action;
  final VoidCallback onPressed;
  final AlsamosColors colors;

  const _QuickActionPill({
    required this.action,
    required this.onPressed,
    required this.colors,
  });

  @override
  State<_QuickActionPill> createState() => _QuickActionPillState();
}

class _QuickActionPillState extends State<_QuickActionPill> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    widget.action.bgColor.withValues(alpha: 0.8),
                    widget.action.bgColor.withValues(alpha: 0.4),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.action.color.withValues(alpha: _isHovered ? 0.3 : 0.15),
                  width: 1.5,
                ),
                boxShadow: _isHovered
                    ? [
                        BoxShadow(
                          color: widget.action.color.withValues(alpha: 0.15),
                          blurRadius: 8,
                          spreadRadius: 0,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.action.icon,
                    size: 18,
                    color: widget.action.color,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.action.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: widget.action.color,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mobile bottom-sheet 4x2 grid version (web 1:1)
class MapQuickActionsGrid extends StatelessWidget {
  final LatLng? currentLocation;
  
  const MapQuickActionsGrid({super.key, this.currentLocation});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.count(
        crossAxisCount: 4,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 0.85,
        children: [
          for (final a in _actions.take(8))
            _QuickActionGridItem(
              action: a,
              onPressed: () => _openSearch(a, currentLocation),
              colors: c,
            ),
        ],
      ),
    );
  }
}

/// Grid item with circular icon container (web 1:1)
class _QuickActionGridItem extends StatelessWidget {
  final _QuickAction action;
  final VoidCallback onPressed;
  final AlsamosColors colors;

  const _QuickActionGridItem({
    required this.action,
    required this.onPressed,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border.withValues(alpha: 0.5)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      action.bgColor.withValues(alpha: 0.7),
                      action.bgColor.withValues(alpha: 0.4),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: action.color.withValues(alpha: 0.1),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Icon(
                  action.icon,
                  size: 22,
                  color: action.color,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                action.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colors.mutedForeground,
                  letterSpacing: -0.1,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
