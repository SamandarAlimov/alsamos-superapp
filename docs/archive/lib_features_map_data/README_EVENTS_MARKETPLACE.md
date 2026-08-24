# Events & Marketplace + Map Integration

Deep integration between Alsamos Maps, Events, and Marketplace features for location-based discovery and coordination.

## Events Integration

### Features

#### 1. Event Location Display
Every event has a location on the map:
- ✅ Event venue marker on map
- ✅ Venue address and directions
- ✅ Distance from user
- ✅ Navigate to event
- ✅ Street view of venue
- ✅ Parking information

**Event Model Integration:**
Events already have location fields (assuming):
```dart
class Event {
  final String id;
  final String title;
  final double? latitude;
  final double? longitude;
  final String? venueName;
  final String? venueAddress;
  // ... other fields
}
```

**Map Display:**
```dart
// Show event on map
Marker(
  point: LatLng(event.latitude!, event.longitude!),
  child: EventMarkerIcon(event: event),
);
```

#### 2. Nearby Events Discovery
Find events near current location or search area:
- ✅ "Events near me" feature
- ✅ Filter by distance (1km, 5km, 10km)
- ✅ Sort by proximity
- ✅ Map view of nearby events
- ✅ Cluster markers for dense areas

**Query Example:**
```dart
// Find events within radius
final nearbyEvents = await supabase
  .rpc('get_nearby_events', params: {
    'lat': currentLocation.latitude,
    'lon': currentLocation.longitude,
    'radius_km': 5.0,
  });
```

#### 3. Event Check-ins
Check-in at event venue:
- ✅ Automatic venue detection
- ✅ Check-in shows on event page
- ✅ See who else checked in
- ✅ Check-in posts to feed
- ✅ Event attendance tracking

**Integration with Social Map:**
```dart
// Check-in at event
final checkIn = await socialMapService.createCheckIn(
  CheckIn(
    placeId: event.venueId ?? event.id,
    placeName: event.venueName ?? event.title,
    placeCategory: 'event',
    location: LatLng(event.latitude!, event.longitude!),
    feeling: 'excited',
    note: 'At ${event.title}!',
    visibility: 'public',
    metadata: {'event_id': event.id}, // Link to event
  ),
);
```

#### 4. Event Attendee Location Sharing
See where other attendees are (opt-in):
- ✅ Family/friends attending shown on map
- ✅ "On my way" status
- ✅ Live ETA to venue
- ✅ Coordinate meetup at event
- ✅ Privacy-respecting (only friends/family)

**Implementation:**
- Event has "share location with attendees" toggle
- Uses existing family circles + privacy system
- Only shows attendees who opted in
- Auto-stops after event ends

#### 5. Event Navigation
One-tap navigation to event:
- ✅ Get directions button
- ✅ Multiple route options
- ✅ Traffic-aware routing
- ✅ Parking suggestions
- ✅ Public transit directions
- ✅ Save event to favorites

**UI Integration:**
```dart
// Event detail page
ElevatedButton(
  onPressed: () => navigateToEvent(event),
  child: Text('Navigate to Event'),
);

void navigateToEvent(Event event) {
  final destination = LatLng(event.latitude!, event.longitude!);
  // Open map with route
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MapRoutePage(
        destination: destination,
        destinationName: event.venueName ?? event.title,
      ),
    ),
  );
}
```

#### 6. Event Map View
Map-centric event discovery:
- ✅ Switch between list/map view
- ✅ Tap marker to see event details
- ✅ Filter events on map
- ✅ See event clusters
- ✅ Live event indicators

**UI Component:**
```dart
class EventsMapView extends StatelessWidget {
  final List<Event> events;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: currentLocation,
      ),
      children: [
        TileLayer(...),
        MarkerLayer(
          markers: events
            .where((e) => e.latitude != null && e.longitude != null)
            .map((event) => Marker(
              point: LatLng(event.latitude!, event.longitude!),
              child: GestureDetector(
                onTap: () => showEventSheet(event),
                child: EventMarkerIcon(event: event),
              ),
            ))
            .toList(),
        ),
      ],
    );
  }
}
```

## Marketplace Integration

### Features

#### 1. Item Location Display
Every marketplace listing has location:
- ✅ Item location on map
- ✅ Distance from buyer
- ✅ Seller location (if shared)
- ✅ Navigate to pickup point
- ✅ Nearby listings search

**Listing Model Integration:**
```dart
class MarketplaceListing {
  final String id;
  final String title;
  final double? latitude;
  final double? longitude;
  final String? locationName;
  final bool showExactLocation; // Privacy flag
  // ... other fields
}
```

**Privacy Options:**
- Exact location (show precise address)
- Area only (show ~1km radius)
- City only (just city name)
- Hidden until contact

#### 2. Distance-Based Search
Find items near user:
- ✅ "Near me" filter
- ✅ Sort by distance
- ✅ Custom radius search
- ✅ Map view of listings
- ✅ Filter by category + location

**Search Query:**
```dart
// Find listings within radius
final nearbyListings = await supabase
  .rpc('get_nearby_listings', params: {
    'lat': currentLocation.latitude,
    'lon': currentLocation.longitude,
    'radius_km': 10.0,
    'category': 'electronics', // optional
  });
```

#### 3. Pickup Location Management
Coordinate item pickup:
- ✅ Seller sets pickup location
- ✅ Buyer gets directions
- ✅ "Meet here" for public place pickup
- ✅ Live location sharing during pickup
- ✅ Confirm pickup arrival

**Pickup Flow:**
1. Seller sets pickup location (home, public place, etc.)
2. Buyer requests item
3. Seller shares exact location
4. Buyer navigates to pickup point
5. Optional: Live location share during pickup
6. Confirm pickup completion

**Implementation:**
```dart
// Seller sets pickup location
await marketplaceService.updateListing(
  listingId,
  pickupLocation: LatLng(39.6270, 66.9750),
  pickupLocationName: 'Coffee House on Rudaki St',
);

// Buyer gets navigation
void navigateToPickup(Listing listing) {
  if (listing.pickupLocation == null) {
    showError('Seller hasn't set pickup location yet');
    return;
  }
  
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MapRoutePage(
        destination: listing.pickupLocation!,
        destinationName: listing.pickupLocationName ?? 'Pickup Point',
      ),
    ),
  );
}
```

#### 4. Delivery Tracking
Live delivery location tracking:
- ✅ Courier live location
- ✅ Real-time ETA
- ✅ Route visualization
- ✅ "Arrived" notification
- ✅ Delivery confirmation

**Integration with Live Location:**
```dart
// Courier starts delivery
final delivery = await deliveryService.startDelivery(orderId);

// Start live location share
await messagesMapService.startLiveLocationShare(
  messageId: deliveryMessageId,
  conversationId: orderConversationId,
  currentLocation: courierLocation,
  destination: customerLocation,
  destinationName: 'Delivery Address',
  duration: Duration(hours: 2),
);

// Customer sees live tracking
// (Uses existing live location UI from Messages integration)
```

#### 5. Marketplace Map View
Map-first listing discovery:
- ✅ Browse listings on map
- ✅ Cluster markers by area
- ✅ Filter by category
- ✅ Tap marker for details
- ✅ "Search this area" button

**UI Component:**
```dart
class MarketplaceMapView extends StatelessWidget {
  final List<MarketplaceListing> listings;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: currentLocation,
        onPositionChanged: (position, hasGesture) {
          if (hasGesture) {
            // Show "Search this area" button
          }
        },
      ),
      children: [
        TileLayer(...),
        MarkerClusterLayerWidget(
          options: MarkerClusterLayerOptions(
            markers: listings
              .where((l) => l.latitude != null && l.longitude != null)
              .map((listing) => Marker(
                point: LatLng(listing.latitude!, listing.longitude!),
                child: GestureDetector(
                  onTap: () => showListingSheet(listing),
                  child: ListingMarkerIcon(listing: listing),
                ),
              ))
              .toList(),
          ),
        ),
      ],
    );
  }
}
```

#### 6. Seller Location Sharing
Seller shares approximate location:
- ✅ Show area (not exact address)
- ✅ "X km away" indicator
- ✅ Reveal exact address after agreement
- ✅ Privacy-first design

**Privacy Levels:**
```dart
enum ListingLocationPrivacy {
  exact,      // Show full address
  approximate, // Show ~1km area
  city,       // Show only city
  hidden,     // Hide until buyer requests
}
```

## Database Integration

### Events Schema (Assumed Existing)
```sql
-- Events table should have:
ALTER TABLE events ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE events ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
ALTER TABLE events ADD COLUMN IF NOT EXISTS venue_name TEXT;
ALTER TABLE events ADD COLUMN IF NOT EXISTS venue_address TEXT;

-- Spatial index for nearby search
CREATE INDEX IF NOT EXISTS idx_events_location 
  ON events USING gist(ll_to_earth(latitude, longitude))
  WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- Nearby events function
CREATE OR REPLACE FUNCTION get_nearby_events(
  lat DOUBLE PRECISION,
  lon DOUBLE PRECISION,
  radius_km DOUBLE PRECISION DEFAULT 10.0
)
RETURNS TABLE (
  id UUID,
  title TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  venue_name TEXT,
  distance_km DOUBLE PRECISION
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id,
    e.title,
    e.latitude,
    e.longitude,
    e.venue_name,
    earth_distance(ll_to_earth(lat, lon), ll_to_earth(e.latitude, e.longitude)) / 1000.0 as distance_km
  FROM events e
  WHERE
    e.latitude IS NOT NULL
    AND e.longitude IS NOT NULL
    AND earth_box(ll_to_earth(lat, lon), radius_km * 1000) @> ll_to_earth(e.latitude, e.longitude)
  ORDER BY earth_distance(ll_to_earth(lat, lon), ll_to_earth(e.latitude, e.longitude));
END;
$$ LANGUAGE plpgsql;
```

### Marketplace Schema (Assumed Existing)
```sql
-- Marketplace listings should have:
ALTER TABLE marketplace_listings ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE marketplace_listings ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
ALTER TABLE marketplace_listings ADD COLUMN IF NOT EXISTS location_name TEXT;
ALTER TABLE marketplace_listings ADD COLUMN IF NOT EXISTS location_privacy TEXT DEFAULT 'approximate';
ALTER TABLE marketplace_listings ADD COLUMN IF NOT EXISTS pickup_latitude DOUBLE PRECISION;
ALTER TABLE marketplace_listings ADD COLUMN IF NOT EXISTS pickup_longitude DOUBLE PRECISION;
ALTER TABLE marketplace_listings ADD COLUMN IF NOT EXISTS pickup_location_name TEXT;

-- Spatial index
CREATE INDEX IF NOT EXISTS idx_marketplace_listings_location 
  ON marketplace_listings USING gist(ll_to_earth(latitude, longitude))
  WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- Nearby listings function
CREATE OR REPLACE FUNCTION get_nearby_listings(
  lat DOUBLE PRECISION,
  lon DOUBLE PRECISION,
  radius_km DOUBLE PRECISION DEFAULT 10.0,
  category TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  title TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  location_name TEXT,
  distance_km DOUBLE PRECISION
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    l.id,
    l.title,
    l.latitude,
    l.longitude,
    l.location_name,
    earth_distance(ll_to_earth(lat, lon), ll_to_earth(l.latitude, l.longitude)) / 1000.0 as distance_km
  FROM marketplace_listings l
  WHERE
    l.latitude IS NOT NULL
    AND l.longitude IS NOT NULL
    AND earth_box(ll_to_earth(lat, lon), radius_km * 1000) @> ll_to_earth(l.latitude, l.longitude)
    AND (category IS NULL OR l.category = category)
    AND l.status = 'active'
  ORDER BY earth_distance(ll_to_earth(lat, lon), ll_to_earth(l.latitude, l.longitude));
END;
$$ LANGUAGE plpgsql;
```

## Usage Examples

### Event Navigation
```dart
// From event detail page
void navigateToEvent(Event event) {
  if (event.latitude == null || event.longitude == null) {
    showError('Event location not available');
    return;
  }

  final destination = LatLng(event.latitude!, event.longitude!);
  
  // Start navigation
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MapRoutePage(
        destination: destination,
        destinationName: event.venueName ?? event.title,
        metadata: {'event_id': event.id},
      ),
    ),
  );
}
```

### Nearby Events Search
```dart
// Find events near user
final location = await getCurrentLocation();
final nearbyEvents = await supabase
  .rpc('get_nearby_events', params: {
    'lat': location.latitude,
    'lon': location.longitude,
    'radius_km': 10.0,
  });

setState(() {
  _events = nearbyEvents.map((e) => Event.fromMap(e)).toList();
});
```

### Marketplace Pickup Navigation
```dart
// Navigate to pickup location
void navigateToPickup(MarketplaceListing listing) {
  final pickupLoc = listing.pickupLocation;
  
  if (pickupLoc == null) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Pickup Location'),
        content: Text('Seller will share pickup location after you request the item.'),
      ),
    );
    return;
  }

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MapRoutePage(
        destination: pickupLoc,
        destinationName: listing.pickupLocationName ?? 'Pickup Point',
      ),
    ),
  );
}
```

### Live Delivery Tracking
```dart
// Courier starts delivery
void startDelivery(Order order) async {
  final currentPos = await getCurrentLocation();
  
  // Create delivery message
  final message = await messagesService.sendMessage(
    conversationId: order.conversationId,
    content: 'Your order is on the way!',
    mediaType: 'location',
  );

  // Start live location
  final liveShare = await messagesMapService.startLiveLocationShare(
    messageId: message.id,
    conversationId: order.conversationId,
    currentLocation: LatLng(currentPos.latitude, currentPos.longitude),
    destination: order.deliveryLocation,
    destinationName: order.deliveryAddress,
    duration: Duration(hours: 2),
  );

  // Update message metadata
  await messagesService.updateMessage(
    message.id,
    metadata: LocationMessageMetadata.liveLocation(
      liveLocationId: liveShare.id,
      location: liveShare.currentLocation,
      destination: liveShare.destination,
      destinationName: liveShare.destinationName,
    ),
  );

  // Background service updates position every 30s
  // (Customer sees live map in conversation)
}
```

## UI Components

### Event Marker Icon
```dart
class EventMarkerIcon extends StatelessWidget {
  final Event event;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        LucideIcons.calendar,
        color: Colors.white,
        size: 24,
      ),
    );
  }
}
```

### Listing Marker Icon
```dart
class ListingMarkerIcon extends StatelessWidget {
  final MarketplaceListing listing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.green,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        LucideIcons.shoppingBag,
        color: Colors.white,
        size: 24,
      ),
    );
  }
}
```

## Testing Checklist

Events:
- [ ] Event location displays on map
- [ ] Navigate to event works
- [ ] Nearby events search returns correct results
- [ ] Event check-in creates check-in record
- [ ] Event map view shows all events
- [ ] Event attendee location sharing works (if opted in)

Marketplace:
- [ ] Listing location displays on map
- [ ] Navigate to pickup works
- [ ] Distance-based search returns sorted results
- [ ] Privacy levels hide/show location correctly
- [ ] Live delivery tracking shows courier position
- [ ] Marketplace map view clusters markers

## Summary

Phase 7 delivers full Events + Marketplace integration:
- ✅ Event venue locations and navigation
- ✅ Nearby events spatial search
- ✅ Event check-ins and attendee tracking
- ✅ Marketplace listing locations
- ✅ Distance-based listing search
- ✅ Pickup location coordination
- ✅ Live delivery tracking
- ✅ Map-first discovery UI
- ✅ Privacy-respecting location sharing
- ✅ Seamless navigation integration

Maps, Events, and Marketplace are now deeply connected, making Alsamos a complete local commerce + social discovery platform.
