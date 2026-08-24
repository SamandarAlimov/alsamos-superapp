# Messages + Map Integration

Deep integration between Alsamos Messages and Maps features, inspired by Telegram Live Location, WhatsApp Location Sharing, and iMessage location features.

## Features

### 1. Live Location Sharing
Real-time location sharing in conversations (Telegram/WhatsApp style):
- ✅ Share live location for custom duration (15 min, 1 hour, 8 hours)
- ✅ Continuous position updates (every 30 seconds by default)
- ✅ Show destination and ETA
- ✅ Battery level indicator
- ✅ Speed and heading tracking
- ✅ Stop sharing anytime
- ✅ Auto-expire after duration
- ✅ Real-time updates for recipients
- ✅ Location history trail

**Use cases**:
- "I'm on my way" - share ETA with friend
- Family tracking during travel
- Coordinate pickup/delivery
- Safety - let someone track your journey

**Database**: `message_live_locations` + `live_location_updates` tables

**How it works**:
1. User starts live location share in chat
2. Creates message with `live_location_id` in metadata
3. Background service updates position every 30s
4. Recipients see live marker on map
5. Auto-stops after expiration time

### 2. Current Location Messages
Send single-point location (like dropping a pin):
- ✅ Share current position
- ✅ Include location name/address
- ✅ Tap to open in map
- ✅ Get directions to location
- ✅ Simple one-time share

**Metadata format**:
```json
{
  "location_type": "current",
  "location_lat": 39.6270,
  "location_lon": 66.9750,
  "location_name": "Registan Square",
  "location_address": "Samarkand, Uzbekistan"
}
```

### 3. Check-in Sharing
Share check-ins in conversations:
- ✅ Send check-in as message
- ✅ Includes place info, feeling, note
- ✅ Recipients can view on map
- ✅ One-tap to check-in at same place
- ✅ Social exploration

**Metadata format**:
```json
{
  "location_type": "checkin",
  "shared_checkin_id": "uuid",
  "location_lat": 39.6270,
  "location_lon": 66.9750,
  "location_name": "Platan Restaurant",
  "place_category": "restaurant",
  "feeling": "hungry",
  "note": "Amazing plov!"
}
```

### 4. Place Sharing
Share places/POIs in chat:
- ✅ Share restaurant, hotel, landmark
- ✅ Include place details
- ✅ Recipients get directions
- ✅ View reviews and ratings
- ✅ Check-in directly from message

**Metadata format**:
```json
{
  "location_type": "place",
  "location_lat": 39.6270,
  "location_lon": 66.9750,
  "location_name": "Registan Square",
  "location_address": "Samarkand, Uzbekistan",
  "place_id": "osm_12345",
  "place_category": "landmark"
}
```

### 5. Meet Here Invitations
Send meetup invitations via chat:
- ✅ Share meet here invitation
- ✅ Include meeting time and message
- ✅ Recipients accept/decline in chat
- ✅ All attendees see location
- ✅ Get navigation to meeting point

**Metadata format**:
```json
{
  "location_type": "meet_here",
  "meet_here_id": "uuid",
  "location_lat": 39.6270,
  "location_lon": 66.9750,
  "location_name": "Coffee House",
  "meeting_time": "2026-08-03T15:00:00Z",
  "message": "Let's meet for coffee!"
}
```

## Architecture

### Service Layer
`MessagesMapService` (`lib/features/map/data/messages_map_service.dart`):

**Live Location**:
- `startLiveLocationShare(...)` - Start sharing live location
- `updateLiveLocationPosition(...)` - Update current position
- `stopLiveLocationShare(id)` - Stop sharing
- `getConversationLiveLocations(conversationId)` - Get active shares
- `getLiveLocationUpdates(id)` - Get position history

**Message Helpers**:
- `messageHasLocation(metadata)` - Check if message contains location
- `getMessageLocation(metadata)` - Extract LatLng from metadata
- `getMessageLocationType(metadata)` - Get location message type

**Metadata Builders**:
- `LocationMessageMetadata.currentLocation(...)` - Create current location metadata
- `LocationMessageMetadata.liveLocation(...)` - Create live location metadata
- `LocationMessageMetadata.checkIn(...)` - Create check-in metadata
- `LocationMessageMetadata.place(...)` - Create place metadata
- `LocationMessageMetadata.meetHere(...)` - Create meet here metadata

**Realtime**:
- `subscribeToConversationLiveLocations(conversationId, callback)` - Live location updates
- `subscribeToLiveLocationUpdates(liveLocationId, callback)` - Position updates

### Database Layer
Migration: `supabase/migrations/20260803030000_messages_map_integration.sql`

**Tables**:
1. `message_live_locations` - Active live location shares
2. `live_location_updates` - Position update history

**Functions**:
- `get_conversation_live_locations(conv_id)` - Get active shares with sender info
- `update_live_location_position(...)` - Update position (with history insert)
- `stop_live_location_sharing(live_loc_id)` - Deactivate share
- `deactivate_expired_live_locations()` - Auto-expire (cron job)
- `get_message_location(metadata)` - Extract location from JSON

**RLS Policies**: Conversation members can view, sender can update/delete

### Message Model Integration
Uses existing `Message.metadata` field - no model changes needed.

Location messages are regular messages with special metadata:
```dart
final message = Message(
  id: uuid,
  conversationId: conversationId,
  senderId: currentUser.id,
  content: 'Live location', // or null
  metadata: LocationMessageMetadata.liveLocation(...),
  createdAt: DateTime.now(),
);
```

## Usage Examples

### Start Live Location Share
```dart
final service = MessagesMapService();

// 1. Create message first (via messages service)
final message = await messagesService.sendMessage(
  conversationId: conversationId,
  content: 'Live location',
  mediaType: 'location',
);

// 2. Start live location share
final liveShare = await service.startLiveLocationShare(
  messageId: message.id,
  conversationId: conversationId,
  currentLocation: LatLng(39.6270, 66.9750),
  destination: LatLng(39.6542, 66.9756),
  destinationName: 'Home',
  duration: Duration(hours: 1),
);

// 3. Update message metadata
await messagesService.updateMessage(
  message.id,
  metadata: LocationMessageMetadata.liveLocation(
    liveLocationId: liveShare.id,
    location: liveShare.currentLocation,
    destination: liveShare.destination,
    destinationName: liveShare.destinationName,
  ),
);

// 4. Start background updates
Timer.periodic(Duration(seconds: 30), (timer) async {
  if (liveShare.isExpired) {
    timer.cancel();
    return;
  }

  final currentPos = await getCurrentPosition();
  await service.updateLiveLocationPosition(
    liveLocationId: liveShare.id,
    newLocation: LatLng(currentPos.latitude, currentPos.longitude),
    accuracy: currentPos.accuracy,
    speed: currentPos.speed,
    heading: currentPos.heading,
    batteryLevel: await getBatteryLevel(),
  );
});
```

### Send Current Location
```dart
await messagesService.sendMessage(
  conversationId: conversationId,
  content: null, // Location messages can have no text
  mediaType: 'location',
  metadata: LocationMessageMetadata.currentLocation(
    location: LatLng(39.6270, 66.9750),
    locationName: 'Registan Square',
    locationAddress: 'Samarkand, Uzbekistan',
  ),
);
```

### Share Check-in
```dart
// After creating check-in
final checkIn = await socialMapService.createCheckIn(...);

// Share in chat
await messagesService.sendMessage(
  conversationId: conversationId,
  content: 'Just checked in at ${checkIn.placeName}!',
  mediaType: 'location',
  metadata: LocationMessageMetadata.checkIn(
    checkInId: checkIn.id,
    location: checkIn.location,
    placeName: checkIn.placeName,
    placeCategory: checkIn.placeCategory,
    feeling: checkIn.feeling,
    note: checkIn.note,
  ),
);
```

### Share Place
```dart
await messagesService.sendMessage(
  conversationId: conversationId,
  content: 'Check out this place!',
  mediaType: 'location',
  metadata: LocationMessageMetadata.place(
    location: LatLng(39.6270, 66.9750),
    placeName: 'Platan Restaurant',
    placeAddress: 'Rudaki St, Samarkand',
    placeId: 'restaurant_123',
    placeCategory: 'restaurant',
  ),
);
```

### Subscribe to Live Location Updates
```dart
final channel = service.subscribeToConversationLiveLocations(
  conversationId,
  (liveLocation) {
    print('Live location updated:');
    print('  Position: ${liveLocation.currentLocation}');
    print('  Expires in: ${liveLocation.remainingTime}');
    // Update UI map marker
  },
);

// Later: channel.unsubscribe()
```

## UI Integration

### Message Bubble Rendering
```dart
if (service.messageHasLocation(message.metadata)) {
  final location = service.getMessageLocation(message.metadata)!;
  final type = service.getMessageLocationType(message.metadata);

  return switch (type) {
    LocationMessageType.live => LiveLocationMessageBubble(
      message: message,
      location: location,
    ),
    LocationMessageType.current => CurrentLocationMessageBubble(
      location: location,
      name: message.metadata['location_name'],
    ),
    LocationMessageType.checkIn => CheckInMessageBubble(
      checkInId: message.metadata['shared_checkin_id'],
      location: location,
    ),
    LocationMessageType.place => PlaceMessageBubble(
      location: location,
      placeName: message.metadata['location_name'],
    ),
    LocationMessageType.meetHere => MeetHereMessageBubble(
      meetHereId: message.metadata['meet_here_id'],
      location: location,
    ),
    _ => Text('Unknown location type'),
  };
}
```

### Live Location Map Widget
```dart
class LiveLocationMap extends ConsumerStatefulWidget {
  final String liveLocationId;
  
  @override
  Widget build(BuildContext context) {
    final service = ref.read(messagesMapServiceProvider);
    
    // Subscribe to updates
    useEffect(() {
      final channel = service.subscribeToLiveLocationUpdates(
        liveLocationId,
        (update) {
          setState(() => _currentPosition = update.location);
        },
      );
      return () => channel.unsubscribe();
    }, [liveLocationId]);

    return FlutterMap(
      options: MapOptions(center: _currentPosition),
      children: [
        TileLayer(...),
        MarkerLayer(
          markers: [
            Marker(
              point: _currentPosition,
              child: LiveMarkerIcon(
                accuracy: _accuracy,
                heading: _heading,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
```

## Security

### RLS Policies
- Only conversation members can view live locations
- Only sender can update/stop their own live location
- Location updates logged with sender_id check

### Privacy
- Respects Ghost Mode (live location auto-stops)
- Privacy zones can pause updates
- Battery level sharing optional
- Recipients see accuracy radius

### Auto-Expire
- Cron job deactivates expired shares
- Client-side timers also stop updates
- No infinite location leaking

## Performance

### Background Updates
- 30-second interval by default (configurable)
- Battery-optimized accuracy modes
- Pauses when app backgrounded (optional)
- Stops when destination reached

### Database
- Indexed on conversation_id, sender_id, expires_at
- Old location updates auto-deleted (retention policy)
- Materialized view for active shares (future)

### Realtime
- Filtered subscriptions per conversation
- Debounced UI updates
- Only active shares subscribed

## Testing Checklist

- [ ] Start live location share creates message + DB entry
- [ ] Position updates insert to updates table
- [ ] Recipients see live marker on map
- [ ] Marker moves as sender moves
- [ ] Expiration timer shows correctly
- [ ] Auto-stop after expiration works
- [ ] Manual stop works
- [ ] Current location message displays map preview
- [ ] Check-in message shows place info
- [ ] Place message allows navigation
- [ ] Meet here invitation shows in chat
- [ ] Realtime subscriptions trigger
- [ ] RLS policies prevent unauthorized access
- [ ] Ghost mode stops live sharing
- [ ] Privacy zones pause updates

## Future Enhancements

### Phase 7+
- Location message reactions (arrived, on my way)
- Group live location (all members sharing)
- Location-based auto-reply
- Geofence notifications (arrived at destination)
- Route preview in message bubble
- Traffic updates in live location
- Shared ride tracking
- Public transit integration

## File Structure
```
lib/features/map/
├── data/
│   ├── messages_map_service.dart           # Integration service
│   └── README_MESSAGES_INTEGRATION.md      # This file
└── ...

supabase/migrations/
└── 20260803030000_messages_map_integration.sql  # Database schema
```

## Summary

Phase 6 delivers Telegram/WhatsApp level location sharing in messages:
- ✅ Live location sharing with real-time updates
- ✅ Current location pin drop
- ✅ Check-in sharing in chat
- ✅ Place/POI sharing
- ✅ Meet here invitation integration
- ✅ Battery and ETA indicators
- ✅ Position update history
- ✅ Real-time subscriptions
- ✅ Auto-expiration system
- ✅ Full privacy integration

Maps and Messages are now deeply integrated, positioning Alsamos as a complete communication + navigation platform.
