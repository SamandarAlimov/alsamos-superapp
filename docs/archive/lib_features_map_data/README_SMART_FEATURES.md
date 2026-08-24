# Smart Features & AI

AI-powered intelligent features inspired by Google Maps' smart suggestions, Waze's crowd-sourced intelligence, and Apple Maps' predictive features.

## Features Overview

### 1. Smart Route Suggestions
AI learns your patterns and suggests routes:

**Features:**
- ✅ Morning commute route (home → work)
- ✅ Evening commute route (work → home)
- ✅ Weekend patterns (gym, mall, etc.)
- ✅ Recurring trips detection
- ✅ One-tap navigation to frequent places

**Implementation:**
```dart
// Analyze location history to detect patterns
class SmartRouteAnalyzer {
  Future<List<RoutePattern>> analyzePatterns() async {
    final history = await locationHistoryService.getHistory(
      startDate: DateTime.now().subtract(Duration(days: 30)),
      endDate: DateTime.now(),
    );

    // Detect recurring trips
    final patterns = _detectRecurringTrips(history);
    
    // Identify work location (most frequent weekday 9-5 location)
    final workLocation = _detectWorkLocation(history);
    
    // Identify home location (most frequent night/early morning location)
    final homeLocation = _detectHomeLocation(history);
    
    return [
      if (workLocation != null && homeLocation != null)
        RoutePattern(
          type: 'commute_morning',
          from: homeLocation,
          to: workLocation,
          typicalTime: TimeOfDay(hour: 8, minute: 0),
          frequency: 5, // days per week
        ),
      ...patterns,
    ];
  }
  
  LatLng? _detectWorkLocation(List<LocationHistory> history) {
    // Find most common location during weekdays 9-5
    final weekdayDayLocations = history.where((h) {
      final hour = h.timestamp.hour;
      final isWeekday = h.timestamp.weekday <= 5;
      return isWeekday && hour >= 9 && hour <= 17;
    });
    
    // Cluster and find most frequent
    return _findMostFrequentCluster(weekdayDayLocations);
  }
}
```

**UI:**
```dart
// Home screen widget
if (smartRoute != null) {
  SmartRouteSuggestionCard(
    title: 'Work',
    subtitle: '25 min via Rudaki St',
    leaveTime: 'Leave by 8:30 AM',
    route: smartRoute,
    onTap: () => startNavigation(smartRoute),
  );
}
```

### 2. "Leave Now" Reminders
Smart notifications when to leave:

**Features:**
- ✅ Traffic-aware departure time
- ✅ Calendar event integration
- ✅ Historical travel time analysis
- ✅ Real-time traffic updates
- ✅ Buffer time calculation

**Algorithm:**
```dart
class LeaveNowCalculator {
  Future<DateTime?> calculateLeaveTime({
    required LatLng destination,
    required DateTime arrivalTime,
    int bufferMinutes = 10,
  }) async {
    // 1. Get historical travel time for this route
    final historicalTime = await _getHistoricalTravelTime(
      destination: destination,
      dayOfWeek: arrivalTime.weekday,
      timeOfDay: arrivalTime.hour,
    );
    
    // 2. Get current traffic prediction
    final currentTraffic = await _getTrafficPrediction(
      destination: destination,
      time: arrivalTime,
    );
    
    // 3. Calculate with buffer
    final estimatedDuration = max(historicalTime, currentTraffic);
    final withBuffer = estimatedDuration + Duration(minutes: bufferMinutes);
    
    // 4. Leave time
    return arrivalTime.subtract(withBuffer);
  }
}
```

**Notification:**
```dart
// Schedule notification
void scheduleLeaveNowNotification() async {
  final leaveTime = await leaveNowCalculator.calculateLeaveTime(
    destination: workLocation,
    arrivalTime: DateTime.now().add(Duration(hours: 1)),
  );
  
  if (leaveTime != null) {
    await notificationService.schedule(
      id: 'leave_now_work',
      title: 'Time to leave for Work',
      body: 'Leave now to arrive by 9:00 AM',
      scheduledTime: leaveTime,
      payload: {'action': 'start_navigation', 'destination': 'work'},
    );
  }
}
```

### 3. Smart Parking Finder
Find parking near destination:

**Features:**
- ✅ Historical parking availability
- ✅ Distance from destination
- ✅ Parking price estimate
- ✅ User-contributed data
- ✅ Street parking vs lots
- ✅ Walking time to destination

**Data Sources:**
- User check-ins at parking lots
- Community-reported parking spots
- Historical patterns (where users usually park)
- OSM parking data

**Implementation:**
```dart
class SmartParkingFinder {
  Future<List<ParkingSpot>> findParking({
    required LatLng destination,
    double radiusKm = 0.5,
  }) async {
    // 1. Find parking spots from OSM
    final osmParking = await _getOSMParking(destination, radiusKm);
    
    // 2. Get community data (where users parked before)
    final communityData = await supabase
      .rpc('get_parking_patterns', params: {
        'lat': destination.latitude,
        'lon': destination.longitude,
        'radius_km': radiusKm,
      });
    
    // 3. Score by distance, availability, cost
    return _rankParkingSpots(osmParking + communityData);
  }
}
```

**Database Function:**
```sql
-- Detect parking locations from user history
CREATE OR REPLACE FUNCTION get_parking_patterns(
  lat DOUBLE PRECISION,
  lon DOUBLE PRECISION,
  radius_km DOUBLE PRECISION
)
RETURNS TABLE (
  parking_lat DOUBLE PRECISION,
  parking_lon DOUBLE PRECISION,
  usage_count INTEGER,
  avg_duration_minutes INTEGER
) AS $$
BEGIN
  -- Find locations where users stop for >1 hour near destination
  -- Then walk short distance (detected by location jumps)
  RETURN QUERY
  WITH parking_stops AS (
    SELECT
      h1.latitude,
      h1.longitude,
      COUNT(*) as stop_count,
      AVG(EXTRACT(EPOCH FROM (h2.timestamp - h1.timestamp)) / 60) as avg_duration
    FROM location_history h1
    JOIN location_history h2 ON h2.user_id = h1.user_id
    WHERE
      earth_distance(ll_to_earth(lat, lon), ll_to_earth(h1.latitude, h1.longitude)) < radius_km * 1000
      AND h2.timestamp > h1.timestamp
      AND h2.timestamp < h1.timestamp + interval '1 hour'
      AND earth_distance(ll_to_earth(h1.latitude, h1.longitude), ll_to_earth(h2.latitude, h2.longitude)) > 100
      AND earth_distance(ll_to_earth(h1.latitude, h1.longitude), ll_to_earth(h2.latitude, h2.longitude)) < 500
    GROUP BY h1.latitude, h1.longitude
    HAVING COUNT(*) > 3
  )
  SELECT
    latitude,
    longitude,
    stop_count::INTEGER,
    avg_duration::INTEGER
  FROM parking_stops
  ORDER BY stop_count DESC;
END;
$$ LANGUAGE plpgsql;
```

### 4. Fuel Station Suggestions
Smart fuel recommendations:

**Features:**
- ✅ Low fuel detection (battery level integration)
- ✅ Nearby fuel stations on route
- ✅ Price comparison (user-contributed)
- ✅ Minimal detour calculation
- ✅ Preferred brand detection

**Algorithm:**
```dart
class SmartFuelFinder {
  Future<List<FuelStation>> suggestFuelStations({
    required LatLng currentLocation,
    LatLng? destination,
    int? batteryLevel,
  }) async {
    // 1. Find stations nearby or on route
    final stations = destination != null
      ? await _getStationsOnRoute(currentLocation, destination)
      : await _getStationsNearby(currentLocation, radiusKm: 5);
    
    // 2. Get user preferences (brand, price sensitivity)
    final preferences = await _getUserFuelPreferences();
    
    // 3. Get community price data
    for (final station in stations) {
      station.estimatedPrice = await _getCommunityPrice(station.id);
    }
    
    // 4. Score by: distance, price, detour time, brand preference
    return _rankFuelStations(stations, preferences);
  }
}
```

**Notification:**
```dart
// Trigger when battery/fuel low
void checkFuelAlert() async {
  final batteryLevel = await getBatteryLevel();
  
  if (batteryLevel < 20 && isNavigating) {
    final stations = await smartFuelFinder.suggestFuelStations(
      currentLocation: currentPosition,
      destination: navigationDestination,
      batteryLevel: batteryLevel,
    );
    
    if (stations.isNotEmpty) {
      showInAppNotification(
        title: 'Low fuel',
        message: 'Nearest station: ${stations.first.name} (+2 min)',
        action: () => showStationsSheet(stations),
      );
    }
  }
}
```

### 5. Popular Times & Crowding
Show when places are busy:

**Features:**
- ✅ Popular times chart (hourly)
- ✅ Current crowd level
- ✅ "Usually crowded" indicator
- ✅ Best time to visit
- ✅ Community-sourced data

**Data Collection:**
```dart
// Passive data collection from check-ins
void logPlaceVisit(String placeId) async {
  await supabase.from('place_visit_patterns').insert({
    'place_id': placeId,
    'visit_hour': DateTime.now().hour,
    'visit_day_of_week': DateTime.now().weekday,
    'user_id': currentUser.id,
  });
}
```

**Database Aggregation:**
```sql
-- Aggregate popular times
CREATE MATERIALIZED VIEW place_popular_times AS
SELECT
  place_id,
  visit_hour,
  visit_day_of_week,
  COUNT(*) as visit_count,
  AVG(duration_minutes) as avg_duration
FROM (
  SELECT
    place_id,
    EXTRACT(HOUR FROM created_at) as visit_hour,
    EXTRACT(DOW FROM created_at) as visit_day_of_week,
    EXTRACT(EPOCH FROM (check_out_time - created_at)) / 60 as duration_minutes
  FROM check_ins
  WHERE created_at > now() - interval '90 days'
) visits
GROUP BY place_id, visit_hour, visit_day_of_week;

-- Refresh daily
```

**UI Display:**
```dart
class PopularTimesChart extends StatelessWidget {
  final String placeId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>>(
      future: _getPopularTimes(placeId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator();
        
        final data = snapshot.data!;
        final maxVisits = data.reduce(max);
        
        return Column(
          children: [
            Text('Popular times', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(24, (hour) {
                final visits = data[hour];
                final height = (visits / maxVisits) * 50;
                
                return Container(
                  width: 8,
                  height: height,
                  decoration: BoxDecoration(
                    color: _getColorForCrowd(visits / maxVisits),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('6 AM', style: TextStyle(fontSize: 10)),
                Text('12 PM', style: TextStyle(fontSize: 10)),
                Text('6 PM', style: TextStyle(fontSize: 10)),
                Text('12 AM', style: TextStyle(fontSize: 10)),
              ],
            ),
          ],
        );
      },
    );
  }
  
  Color _getColorForCrowd(double ratio) {
    if (ratio < 0.3) return Colors.green;
    if (ratio < 0.7) return Colors.orange;
    return Colors.red;
  }
}
```

### 6. Commute Patterns & Insights
Learn and predict user commutes:

**Features:**
- ✅ Daily commute detection
- ✅ Average commute time
- ✅ Best/worst commute days
- ✅ Alternative route suggestions
- ✅ Commute time trends

**Analytics:**
```dart
class CommuteAnalyzer {
  Future<CommuteInsights> analyzeCommute() async {
    final history = await locationHistoryService.getHistory(
      startDate: DateTime.now().subtract(Duration(days: 90)),
    );
    
    // Detect home and work
    final home = _detectHome(history);
    final work = _detectWork(history);
    
    if (home == null || work == null) return CommuteInsights.empty();
    
    // Find all home→work trips
    final morningCommutes = _findCommutes(
      history,
      from: home,
      to: work,
      timeWindow: (6, 10), // 6 AM - 10 AM
    );
    
    // Find all work→home trips
    final eveningCommutes = _findCommutes(
      history,
      from: work,
      to: home,
      timeWindow: (16, 20), // 4 PM - 8 PM
    );
    
    return CommuteInsights(
      homeLocation: home,
      workLocation: work,
      avgMorningDuration: _averageDuration(morningCommutes),
      avgEveningDuration: _averageDuration(eveningCommutes),
      commuteFrequency: morningCommutes.length,
      bestDay: _findBestDay(morningCommutes),
      worstDay: _findWorstDay(morningCommutes),
      totalCommuteTime: _totalTime(morningCommutes + eveningCommutes),
    );
  }
}
```

**UI Widget:**
```dart
class CommuteInsightsCard extends StatelessWidget {
  final CommuteInsights insights;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your Commute', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            _InsightRow(
              icon: LucideIcons.clock,
              label: 'Avg morning',
              value: '${insights.avgMorningDuration.inMinutes} min',
            ),
            _InsightRow(
              icon: LucideIcons.clock,
              label: 'Avg evening',
              value: '${insights.avgEveningDuration.inMinutes} min',
            ),
            _InsightRow(
              icon: LucideIcons.calendar,
              label: 'Total this month',
              value: '${insights.totalCommuteTime.inHours}h ${insights.totalCommuteTime.inMinutes % 60}m',
            ),
            _InsightRow(
              icon: LucideIcons.trendingUp,
              label: 'Best day',
              value: _dayName(insights.bestDay),
              valueColor: Colors.green,
            ),
            _InsightRow(
              icon: LucideIcons.trendingDown,
              label: 'Worst day',
              value: _dayName(insights.worstDay),
              valueColor: Colors.red,
            ),
          ],
        ),
      ),
    );
  }
}
```

### 7. Smart Place Recommendations
AI-powered place suggestions:

**Features:**
- ✅ "Places you might like"
- ✅ Based on check-in history
- ✅ Friend recommendations
- ✅ Similar places discovery
- ✅ Time-aware suggestions (lunch spots at noon)

**Algorithm:**
```dart
class SmartRecommendations {
  Future<List<PlaceRecommendation>> getRecommendations() async {
    // 1. User's check-in history
    final userCheckIns = await socialMapService.getUserCheckIns(currentUser.id);
    
    // 2. Extract preferences (categories, areas)
    final preferredCategories = _extractCategories(userCheckIns);
    final preferredAreas = _extractAreas(userCheckIns);
    
    // 3. Friends' check-ins in those categories
    final friendCheckIns = await _getFriendsCheckIns(
      categories: preferredCategories,
      limit: 50,
    );
    
    // 4. Nearby places in preferred categories
    final nearbyPlaces = await _getNearbyPlaces(
      location: currentLocation,
      categories: preferredCategories,
      excludeVisited: true,
    );
    
    // 5. Score by: friend visits, reviews, distance, freshness
    return _rankRecommendations(friendCheckIns + nearbyPlaces);
  }
}
```

### 8. Context-Aware Smart Navigation
Navigation that adapts to context:

**Features:**
- ✅ Time-based route selection (fastest morning ≠ fastest evening)
- ✅ Mode detection (walking/driving/cycling)
- ✅ Weather-aware routing
- ✅ Avoid recently-traffic areas
- ✅ Learn user route preferences

**Implementation:**
```dart
class ContextAwareRouter {
  Future<Route> getSmartRoute({
    required LatLng destination,
  }) async {
    final context = await _getContext();
    
    // Apply context-specific optimizations
    final route = await routingService.getRoute(
      destination: destination,
      avoidTolls: context.userPrefersNoTolls,
      avoidHighways: context.isRaining && context.mode == TransportMode.motorcycle,
      departureTime: context.timeOfDay == 'rush_hour' ? DateTime.now().add(Duration(minutes: 30)) : null,
    );
    
    return route;
  }
  
  Future<NavigationContext> _getContext() async {
    final weather = await weatherService.getCurrentWeather();
    final timeOfDay = _getTimeCategory(DateTime.now().hour);
    final mode = await _detectTransportMode();
    
    return NavigationContext(
      weather: weather,
      timeOfDay: timeOfDay,
      mode: mode,
      isRushHour: _isRushHour(),
      userPrefersNoTolls: await _getUserPreference('avoid_tolls'),
    );
  }
}
```

## Performance Considerations

### Data Collection
- Passive, privacy-respecting collection
- Aggregated anonymized data only
- User can opt-out anytime
- No individual tracking exposed

### Caching
- Popular times cached for 24h
- Commute patterns cached for 7 days
- Smart suggestions cached for 1 hour
- Historical data pre-computed via materialized views

### Edge Functions
- Heavy analytics run server-side
- Client receives pre-computed results
- Scheduled daily/weekly analysis jobs
- Real-time features use lightweight algorithms

## Privacy

### User Control
- Toggle smart features on/off
- Clear pattern history
- Opt-out of data contribution
- Anonymous analytics only

### Data Usage
- Location history stays on device (unless cloud backup enabled)
- Aggregated patterns stored server-side (anonymized)
- No individual movement tracking
- Community data opt-in

## Testing Checklist

- [ ] Smart route suggestions detect home/work correctly
- [ ] Leave now reminders calculate accurate times
- [ ] Smart parking finder returns valid spots
- [ ] Fuel station suggestions show on-route stations
- [ ] Popular times chart displays correctly
- [ ] Commute insights calculate accurate averages
- [ ] Place recommendations are relevant
- [ ] Context-aware routing adapts to conditions
- [ ] All features respect privacy settings
- [ ] Opt-out disables data collection

## Summary

Phase 8 delivers Google Maps + Waze level intelligence:
- ✅ AI-powered route suggestions from patterns
- ✅ Smart "leave now" reminders with traffic
- ✅ Intelligent parking finder
- ✅ Context-aware fuel station suggestions
- ✅ Popular times and crowding data
- ✅ Commute pattern analysis
- ✅ Personalized place recommendations
- ✅ Context-aware smart navigation
- ✅ Privacy-first data collection
- ✅ Community-powered intelligence

Alsamos Maps now learns from user behavior to provide proactive, intelligent assistance.
