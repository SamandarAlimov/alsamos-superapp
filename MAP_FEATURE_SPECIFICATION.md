Auth
Login, register, reset password, session restore, redirect, loading/error states.

App Layout / Navigation
Sidebar, mobile header, bottom nav, route redirect, responsive layout.

Messages / Calls / Live
Chat, call, realtime, media, live stream, loading/failure states.

Home / Feed / Create
Post card, media carousel, create post, comments, likes, share.

Profile / Settings
Profile view/edit, avatars, privacy, account settings.

Marketplace / Payment
Product cards, cart/order flow, wallet/payment UI, error states.

Map / Mini Apps / AI / Discovery
MVPda kerakli darajada ishlashini tekshiramiz, ortiqcha polish keyin.

Global Cleanup
Shared widgets, providers/hooks, duplicated logic, loading/empty/error states, responsiveness.

# Map Feature - Complete Specification for Flutter Port

## Document Overview
This document provides a **100% accurate specification** for porting the React web map feature to Flutter. All component structures, state management, API calls, UI elements, and Uzbek text labels are documented.

---

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Main MapPage Component](#main-mappage-component)
3. [DirectionsPanel Component](#directionspanel-component)
4. [DirectionsMobileSheet Component](#directionsmobilesheet-component)
5. [LocationHistory Components](#locationhistory-components)
6. [MapQuickActions Component](#mapquickactions-component)
7. [StepTrackingCharts Component](#steptrackingcharts-component)
8. [TransportModePicker Component](#transportmodepicker-component)
9. [Hooks (Business Logic)](#hooks-business-logic)
10. [API Integration](#api-integration)
11. [Responsive Design](#responsive-design)
12. [Localization (Uzbek)](#localization-uzbek)

---

## Architecture Overview

### Tech Stack (React Web)
- **Map Library**: Leaflet (react-leaflet)
- **UI Framework**: shadcn/ui (Radix UI primitives)
- **State Management**: React hooks (useState, useCallback, useRef)
- **Real-time**: Supabase Realtime (presence channels)
- **Routing API**: OSRM (OpenStreetMap Router)
- **Geocoding**: Nominatim API
- **Charts**: Recharts (for step tracking)

### Flutter Equivalent Recommendations
- **Map Library**: flutter_map (or google_maps_flutter)
- **State Management**: Riverpod or Bloc
- **Real-time**: Supabase Flutter SDK
- **HTTP Client**: Dio or http
- **Charts**: fl_chart

### File Structure
```
lib/features/map/
├── data/
│   ├── models/
│   │   ├── location_point.dart
│   │   ├── frequent_place.dart
│   │   ├── daily_route.dart
│   │   ├── route_alternative.dart
│   │   ├── route_step.dart
│   │   └── search_result.dart
│   ├── repositories/
│   │   ├── location_repository.dart
│   │   ├── directions_repository.dart
│   │   └── map_presence_repository.dart
│   └── datasources/
│       ├── location_local_datasource.dart
│       ├── location_remote_datasource.dart
│       └── directions_remote_datasource.dart
├── domain/
│   ├── entities/
│   ├── repositories/
│   └── usecases/
├── presentation/
│   ├── pages/
│   │   └── map_page.dart
│   ├── widgets/
│   │   ├── directions_panel.dart
│   │   ├── directions_mobile_sheet.dart
│   │   ├── location_history_panel.dart
│   │   ├── location_history_sheet.dart
│   │   ├── map_quick_actions.dart
│   │   ├── step_tracking_charts.dart
│   │   ├── transport_mode_picker.dart
│   │   └── map_markers.dart
│   └── providers/
│       ├── map_state_provider.dart
│       ├── directions_provider.dart
│       ├── location_tracking_provider.dart
│       └── map_presence_provider.dart
```

---

## Main MapPage Component

### Component Overview
**File**: `src/pages/MapPage.tsx` (1380 lines)
**Purpose**: Main container for the entire map feature with real-time location sharing

### State Variables

```typescript
// Map State
const [mapCenter, setMapCenter] = useState<[number, number]>([41.2995, 69.2401]); // Tashkent default
const [zoom, setZoom] = useState(13);
const [mapLayer, setMapLayer] = useState<'standard' | 'satellite' | 'terrain'>('standard');

// UI State
const [sidebarOpen, setSidebarOpen] = useState(true);
const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
const [mobileSettingsOpen, setMobileSettingsOpen] = useState(false);
const [activeTab, setActiveTab] = useState<'nearby' | 'following' | 'activity'>('nearby');

// Location State
const [currentLocation, setCurrentLocation] = useState<{ latitude: number; longitude: number } | null>(null);
const [hasLocationPermission, setHasLocationPermission] = useState<boolean | null>(null);
const [isCheckingPermission, setIsCheckingPermission] = useState(false);
const [batteryLevel, setBatteryLevel] = useState(100);
const [isOnline, setIsOnline] = useState(navigator.onLine);

// Sharing & Privacy
const [isSharing, setIsSharing] = useState(false);
const [isLocationPrivate, setIsLocationPrivate] = useState(false);
const [showNearby, setShowNearby] = useState(true);
const [showFollowing, setShowFollowing] = useState(true);
const [nearbyRadius, setNearbyRadius] = useState(10); // km

// Transport & Tracking
const [transportMode, setTransportMode] = useState<TransportMode>('driving');
const [stepsToday, setStepsToday] = useState(0);
const [stepHistory, setStepHistory] = useState<StepData[]>([]);
const DAILY_STEP_GOAL = 10000;

// Directions
const [destination, setDestination] = useState<{ lat: number; lng: number; name: string } | null>(null);
const [showDirections, setShowDirections] = useState(false);
const [showDirectionsPanel, setShowDirectionsPanel] = useState(false);
const [activeRoute, setActiveRoute] = useState<RouteAlternative | null>(null);
const [mapSelectionMode, setMapSelectionMode] = useState<'origin' | 'destination' | null>(null);
const [selectedMapLocation, setSelectedMapLocation] = useState<{ lat: number; lng: number; name: string } | null>(null);

// History & Places
const [showLocationHistory, setShowLocationHistory] = useState(false);
const [viewingRoute, setViewingRoute] = useState<DailyRoute | null>(null);
const [todayRoute, setTodayRoute] = useState<DailyRoute | null>(null);
const [frequentPlaces, setFrequentPlaces] = useState<FrequentPlace[]>([]);

// Users & Search
const [nearbyLocations, setNearbyLocations] = useState<UserLocation[]>([]);
const [followingLocations, setFollowingLocations] = useState<UserLocation[]>([]);
const [selectedUser, setSelectedUser] = useState<string | null>(null);
const [searchQuery, setSearchQuery] = useState('');
```

### Key Functions

#### Location Management
```typescript
// Request location permission
const requestLocationPermission = async () => {
  setIsCheckingPermission(true);
  try {
    const permission = await navigator.permissions.query({ name: 'geolocation' });
    if (permission.state === 'granted') {
      setHasLocationPermission(true);
      getCurrentLocation();
    } else if (permission.state === 'prompt') {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          setHasLocationPermission(true);
          setCurrentLocation({
            latitude: position.coords.latitude,
            longitude: position.coords.longitude,
          });
        },
        () => setHasLocationPermission(false)
      );
    } else {
      setHasLocationPermission(false);
    }
  } finally {
    setIsCheckingPermission(false);
  }
};

// Get current location
const getCurrentLocation = () => {
  if (!navigator.geolocation) return;
  
  navigator.geolocation.getCurrentPosition(
    (position) => {
      setCurrentLocation({
        latitude: position.coords.latitude,
        longitude: position.coords.longitude,
      });
      setMapCenter([position.coords.latitude, position.coords.longitude]);
      setZoom(15);
    },
    (error) => console.error('Geolocation error:', error),
    { enableHighAccuracy: true, timeout: 10000 }
  );
};

// Center map on current location
const centerOnLocation = () => {
  if (currentLocation) {
    setMapCenter([currentLocation.latitude, currentLocation.longitude]);
    setZoom(15);
  }
};

// Calculate distance between two points (Haversine formula)
const calculateDistance = (lat1: number, lon1: number, lat2: number, lon2: number): number => {
  const R = 6371; // Earth's radius in km
  const dLat = (lat2 - lat1) * (Math.PI / 180);
  const dLon = (lon2 - lon1) * (Math.PI / 180);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * (Math.PI / 180)) * Math.cos(lat2 * (Math.PI / 180)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
};
```

#### Location Sharing
```typescript
// Toggle location sharing
const toggleSharing = async () => {
  if (!user || !currentLocation) return;
  
  const newSharingState = !isSharing;
  setIsSharing(newSharingState);
  
  if (newSharingState) {
    // Start sharing - update Supabase
    await supabase.from('user_locations').upsert({
      user_id: user.id,
      latitude: currentLocation.latitude,
      longitude: currentLocation.longitude,
      is_sharing: true,
      is_private: isLocationPrivate,
    });
  } else {
    // Stop sharing
    await supabase.from('user_locations')
      .update({ is_sharing: false })
      .eq('user_id', user.id);
  }
};
```

#### Directions & Navigation
```typescript
// Open built-in device directions
const openBuiltInDirections = (lat: number, lng: number, name: string) => {
  const isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);
  const url = isMobile 
    ? `geo:${lat},${lng}?q=${lat},${lng}(${encodeURIComponent(name)})`
    : `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`;
  window.open(url, '_blank');
};

// Handle route calculation
const handleRouteCalculated = (route: RouteAlternative | null) => {
  setActiveRoute(route);
  if (route && route.geometry.length > 0) {
    // Fit map to route bounds
    const bounds = route.geometry;
    // Calculate center
    const latSum = bounds.reduce((sum, point) => sum + point[0], 0);
    const lngSum = bounds.reduce((sum, point) => sum + point[1], 0);
    setMapCenter([latSum / bounds.length, lngSum / bounds.length]);
  }
};

// Handle step selection in navigation
const handleStepSelected = (stepLocation: [number, number]) => {
  setMapCenter(stepLocation);
  setZoom(17);
};
```

### Map Layers & Tiles
```typescript
const getTileUrl = () => {
  switch (mapLayer) {
    case 'satellite':
      return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    case 'terrain':
      return 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';
    default:
      return 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
  }
};
```

### Custom Marker Icons
```typescript
// Create user avatar marker
const createUserIcon = (avatarUrl?: string, isCurrentUser: boolean = false, isOnline: boolean = false) => {
  const size = isCurrentUser ? 40 : 32;
  const borderColor = isCurrentUser ? '#3b82f6' : (isOnline ? '#22c55e' : '#94a3b8');
  
  return L.divIcon({
    className: 'custom-marker',
    html: `
      <div style="position: relative; width: ${size}px; height: ${size}px;">
        <img 
          src="${avatarUrl || '/default-avatar.png'}" 
          style="width: 100%; height: 100%; border-radius: 50%; border: 3px solid ${borderColor}; background: white;"
        />
        ${isCurrentUser ? '<div style="position: absolute; bottom: -2px; right: -2px; width: 12px; height: 12px; background: #22c55e; border: 2px solid white; border-radius: 50%;"></div>' : ''}
      </div>
    `,
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2],
  });
};

// Destination marker
const destinationIcon = L.divIcon({
  className: 'destination-marker',
  html: '<div style="width: 32px; height: 32px; background: #ef4444; border-radius: 50% 50% 50% 0; transform: rotate(-45deg); border: 3px solid white; box-shadow: 0 2px 8px rgba(0,0,0,0.3);"></div>',
  iconSize: [32, 32],
