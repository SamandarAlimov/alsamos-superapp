# Premium Map UI/UX Design

World-class map interface design inspired by Yandex Maps, Apple Maps, and Google Maps Material You design.

## Design Principles

### 1. **Professional & Premium**
- Clean, minimal interface
- Glass morphism effects
- Soft shadows and elevation
- Smooth 60 FPS animations
- High-quality iconography (Lucide Icons)

### 2. **User-First**
- One-hand operation friendly
- Large touch targets (48x48 minimum)
- Clear visual hierarchy
- Instant feedback
- Accessibility compliant

### 3. **Context-Aware**
- Adaptive UI based on mode (navigation vs exploration)
- Smart panel positioning
- Progressive disclosure
- Contextual actions

### 4. **Responsive**
- Mobile-first design
- Tablet optimization
- Desktop large-screen support
- Dynamic layouts

## Core Components

### Map Styles

#### 1. Light Mode (Default)
```dart
// Bright, high-contrast for outdoor use
final lightStyle = '''
  {
    "version": 8,
    "sources": {...},
    "layers": [
      {
        "id": "background",
        "type": "background",
        "paint": {"background-color": "#F5F5F5"}
      },
      {
        "id": "water",
        "type": "fill",
        "paint": {"fill-color": "#B3D9FF"}
      },
      {
        "id": "parks",
        "type": "fill",
        "paint": {"fill-color": "#C8E6C9"}
      },
      // ... roads, buildings, labels
    ]
  }
''';
```

#### 2. Dark Mode
```dart
// High contrast, OLED-friendly, battery-saving
final darkStyle = '''
  {
    "version": 8,
    "layers": [
      {
        "id": "background",
        "type": "background",
        "paint": {"background-color": "#181818"}
      },
      {
        "id": "water",
        "type": "fill",
        "paint": {"fill-color": "#1A3A52"}
      },
      // Dark theme optimized colors
    ]
  }
''';
```

#### 3. Satellite View
```dart
// Real satellite imagery
TileLayer(
  urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  subdomains: ['a', 'b', 'c'],
);
```

#### 4. Hybrid Mode
```dart
// Satellite + labels overlay
MarkerLayer(...), // Labels on top
TileLayer(satellite), // Satellite base
```

### Floating Action Buttons

**Primary FAB**: Current Location
```dart
Positioned(
  bottom: 24,
  right: 24,
  child: FloatingActionButton(
    onPressed: () => _centerOnCurrentLocation(),
    backgroundColor: Colors.white,
    elevation: 4,
    child: Icon(LucideIcons.navigation, color: primary),
  ),
)
```

**Secondary FABs**: Quick Actions
```dart
// Vertical FAB stack
Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    _FabButton(
      icon: LucideIcons.layers,
      label: 'Layers',
      onTap: () => _showLayersSheet(),
    ),
    SizedBox(height: 12),
    _FabButton(
      icon: LucideIcons.compass,
      label: '3D',
      onTap: () => _toggle3D(),
    ),
    SizedBox(height: 12),
    _FabButton(
      icon: LucideIcons.users,
      label: 'Friends',
      onTap: () => _showFriendsLayer(),
    ),
  ],
)
```

### Bottom Sheet Panels

**Search Panel**: Floating above map
```dart
DraggableScrollableSheet(
  initialChildSize: 0.3,
  minChildSize: 0.1,
  maxChildSize: 0.9,
  builder: (context, controller) {
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: ListView(
        controller: controller,
        children: [...],
      ),
    );
  },
)
```

**Place Details Sheet**: Slide from bottom
```dart
void showPlaceDetails(Place place) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => PlaceDetailsSheet(place: place),
  );
}
```

### Marker Design

#### Current Location Marker
```dart
class CurrentLocationMarker extends StatelessWidget {
  final double accuracy;
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Accuracy circle
        Container(
          width: accuracy * 2,
          height: accuracy * 2,
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.blue.withOpacity(0.3),
              width: 2,
            ),
          ),
        ),
        // Pulsing animation
        AnimatedContainer(
          duration: Duration(seconds: 2),
          curve: Curves.easeInOut,
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        // Center dot
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}
```

#### Friend/Family Marker
```dart
class UserMarker extends StatelessWidget {
  final User user;
  final bool isMoving;
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Avatar
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white,
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipOval(
            child: user.avatarUrl != null
              ? Image.network(user.avatarUrl!)
              : Icon(LucideIcons.user, color: Colors.grey),
          ),
        ),
        // Moving indicator
        if (isMoving)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        // Battery indicator
        Positioned(
          bottom: -8,
          left: 0,
          right: 0,
          child: BatteryIndicator(level: user.batteryLevel),
        ),
      ],
    );
  }
}
```

#### Place Marker
```dart
class PlaceMarker extends StatelessWidget {
  final Place place;
  final bool isSelected;
  
  @override
  Widget build(BuildContext context) {
    final icon = _getIconForCategory(place.category);
    final color = _getColorForCategory(place.category);
    
    return AnimatedContainer(
      duration: Duration(milliseconds: 200),
      transform: Matrix4.identity()
        ..scale(isSelected ? 1.2 : 1.0),
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: isSelected ? 12 : 6,
              offset: Offset(0, isSelected ? 4 : 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: isSelected ? 28 : 24,
        ),
      ),
    );
  }
}
```

### Route Visualization

#### Route Line
```dart
PolylineLayer(
  polylines: [
    Polyline(
      points: routePoints,
      strokeWidth: 8,
      color: primary,
      borderStrokeWidth: 2,
      borderColor: Colors.white,
      gradientColors: [
        primary,
        primary.withOpacity(0.7),
      ],
    ),
  ],
)
```

#### Animated Route Drawing
```dart
class AnimatedRouteDrawing extends StatefulWidget {
  final List<LatLng> points;
  
  @override
  _AnimatedRouteDrawingState createState() => _AnimatedRouteDrawingState();
}

class _AnimatedRouteDrawingState extends State<AnimatedRouteDrawing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..forward();
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final visiblePoints = widget.points.take(
          (widget.points.length * _controller.value).ceil(),
        ).toList();
        
        return PolylineLayer(
          polylines: [
            Polyline(
              points: visiblePoints,
              strokeWidth: 8,
              color: primary,
            ),
          ],
        );
      },
    );
  }
}
```

### Live Indicators

#### Live Location Pulse
```dart
class LiveLocationPulse extends StatefulWidget {
  @override
  _LiveLocationPulseState createState() => _LiveLocationPulseState();
}

class _LiveLocationPulseState extends State<LiveLocationPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 100 * _controller.value,
          height: 100 * _controller.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blue.withOpacity(0.3 * (1 - _controller.value)),
          ),
        );
      },
    );
  }
}
```

#### ETA Countdown
```dart
class ETACountdown extends StatefulWidget {
  final DateTime arrivalTime;
  
  @override
  _ETACountdownState createState() => _ETACountdownState();
}

class _ETACountdownState extends State<ETACountdown> {
  late Timer _timer;
  Duration _remaining = Duration.zero;
  
  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(Duration(seconds: 1), (_) => _updateRemaining());
  }
  
  void _updateRemaining() {
    setState(() {
      _remaining = widget.arrivalTime.difference(DateTime.now());
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.clock, color: Colors.white, size: 16),
          SizedBox(width: 6),
          Text(
            '${_remaining.inMinutes} min',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
```

### Glass Morphism Effects

```dart
class GlassPanel extends StatelessWidget {
  final Widget child;
  
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
```

### Context Menus

**Long Press Menu**:
```dart
void _showContextMenu(LatLng position, Offset tapPosition) {
  showMenu(
    context: context,
    position: RelativeRect.fromLTRB(
      tapPosition.dx,
      tapPosition.dy,
      tapPosition.dx,
      tapPosition.dy,
    ),
    items: [
      PopupMenuItem(
        child: ListTile(
          leading: Icon(LucideIcons.navigation),
          title: Text('Navigate here'),
          onTap: () => _navigateTo(position),
        ),
      ),
      PopupMenuItem(
        child: ListTile(
          leading: Icon(LucideIcons.mapPin),
          title: Text('Drop pin'),
          onTap: () => _dropPin(position),
        ),
      ),
      PopupMenuItem(
        child: ListTile(
          leading: Icon(LucideIcons.share2),
          title: Text('Share location'),
          onTap: () => _shareLocation(position),
        ),
      ),
    ],
  );
}
```

## Responsive Layouts

### Mobile (< 600px)
- Single-column layout
- Bottom sheet panels
- FABs in bottom-right
- Full-screen map
- Swipe gestures

### Tablet (600-1200px)
- Two-column layout option
- Side panel for details
- Larger touch targets
- Floating panels

### Desktop (> 1200px)
- Three-column layout
- Persistent sidebar
- Mouse hover states
- Keyboard shortcuts
- Right-click context menus

```dart
class ResponsiveMapLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return MobileMapLayout();
        } else if (constraints.maxWidth < 1200) {
          return TabletMapLayout();
        } else {
          return DesktopMapLayout();
        }
      },
    );
  }
}
```

## Animations

### Smooth Map Transitions
```dart
// Animate to location
mapController.animatedMove(
  destination,
  zoom: 15.0,
  duration: Duration(milliseconds: 500),
  curve: Curves.easeInOut,
);
```

### Panel Slide-In
```dart
class SlideInPanel extends StatefulWidget {
  @override
  _SlideInPanelState createState() => _SlideInPanelState();
}

class _SlideInPanelState extends State<SlideInPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
    _controller.forward();
  }
  
  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _offsetAnimation,
      child: YourPanelWidget(),
    );
  }
}
```

### Marker Bounce
```dart
class BouncingMarker extends StatefulWidget {
  @override
  _BouncingMarkerState createState() => _BouncingMarkerState();
}

class _BouncingMarkerState extends State<BouncingMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    )..forward();
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final bounce = Curves.bounceOut.transform(_controller.value);
        return Transform.translate(
          offset: Offset(0, -20 * (1 - bounce)),
          child: child,
        );
      },
      child: YourMarkerWidget(),
    );
  }
}
```

## Accessibility

### Screen Reader Support
```dart
Semantics(
  label: 'Current location button',
  hint: 'Centers map on your location',
  button: true,
  child: FloatingActionButton(...),
)
```

### High Contrast Mode
```dart
if (MediaQuery.of(context).highContrast) {
  // Use high-contrast colors
  return Colors.black;
} else {
  return Colors.grey[800];
}
```

### Text Scaling
```dart
Text(
  'Navigate',
  style: TextStyle(
    fontSize: 16,
  ),
  textScaleFactor: MediaQuery.of(context).textScaleFactor.clamp(0.8, 1.3),
)
```

## Performance

### 60 FPS Target
- Use `RepaintBoundary` for static widgets
- Avoid `setState()` in high-frequency callbacks
- Use `const` constructors
- Optimize marker rendering with clustering

### Tile Caching
```dart
TileLayer(
  urlTemplate: '...',
  tileProvider: CachedTileProvider(),
  maxNativeZoom: 19,
  maxZoom: 22,
)
```

### Image Optimization
- Use appropriate image sizes
- Compress avatars and thumbnails
- Lazy load off-screen markers
- Use vector icons (Lucide)

## Summary

Phase 9 delivers world-class UI/UX:
- ✅ Professional map styles (Light/Dark/Satellite/Hybrid)
- ✅ Premium glass morphism design
- ✅ Smooth 60 FPS animations
- ✅ Floating action buttons
- ✅ Draggable bottom sheets
- ✅ Context menus
- ✅ Professional marker designs
- ✅ Animated route visualization
- ✅ Live location indicators
- ✅ Responsive layouts (Mobile/Tablet/Desktop)
- ✅ Full accessibility support
- ✅ High performance optimizations

Alsamos Maps now has a premium, Yandex Maps-level professional interface.
