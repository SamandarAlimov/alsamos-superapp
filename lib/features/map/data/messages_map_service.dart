// Messages + Map Integration Service
library;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Live location share (Telegram/WhatsApp style)
class LiveLocationShare {
  final String id;
  final String messageId;
  final String conversationId;
  final String senderId;
  final LatLng currentLocation;
  final LatLng? destination;
  final String? destinationName;
  final DateTime expiresAt;
  final bool isActive;
  final int updateIntervalSeconds;
  final DateTime lastUpdated;
  final DateTime createdAt;

  const LiveLocationShare({
    required this.id,
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.currentLocation,
    this.destination,
    this.destinationName,
    required this.expiresAt,
    this.isActive = true,
    this.updateIntervalSeconds = 30,
    required this.lastUpdated,
    required this.createdAt,
  });

  factory LiveLocationShare.fromMap(Map<String, dynamic> map) {
    return LiveLocationShare(
      id: map['id'] as String,
      messageId: map['message_id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      currentLocation: LatLng(
        map['current_latitude'] as double,
        map['current_longitude'] as double,
      ),
      destination: map['destination_latitude'] != null
          ? LatLng(
              map['destination_latitude'] as double,
              map['destination_longitude'] as double,
            )
          : null,
      destinationName: map['destination_name'] as String?,
      expiresAt: DateTime.parse(map['expires_at'] as String),
      isActive: map['is_active'] as bool? ?? true,
      updateIntervalSeconds: map['update_interval_seconds'] as int? ?? 30,
      lastUpdated: DateTime.parse(map['last_updated'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'message_id': messageId,
      'conversation_id': conversationId,
      'current_latitude': currentLocation.latitude,
      'current_longitude': currentLocation.longitude,
      'destination_latitude': destination?.latitude,
      'destination_longitude': destination?.longitude,
      'destination_name': destinationName,
      'expires_at': expiresAt.toIso8601String(),
      'update_interval_seconds': updateIntervalSeconds,
    };
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get remainingTime => expiresAt.difference(DateTime.now());
}

/// Location update for live tracking
class LiveLocationUpdate {
  final String id;
  final String liveLocationId;
  final LatLng location;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final int? batteryLevel;
  final DateTime createdAt;

  const LiveLocationUpdate({
    required this.id,
    required this.liveLocationId,
    required this.location,
    this.accuracy,
    this.speed,
    this.heading,
    this.batteryLevel,
    required this.createdAt,
  });

  factory LiveLocationUpdate.fromMap(Map<String, dynamic> map) {
    return LiveLocationUpdate(
      id: map['id'] as String,
      liveLocationId: map['live_location_id'] as String,
      location: LatLng(
        map['latitude'] as double,
        map['longitude'] as double,
      ),
      accuracy: map['accuracy'] as double?,
      speed: map['speed'] as double?,
      heading: map['heading'] as double?,
      batteryLevel: map['battery_level'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

/// Location message types
enum LocationMessageType {
  current, // Single point location
  live, // Continuously updating location
  checkIn, // Shared check-in
  place, // Shared place/POI
  meetHere, // Meet here invitation
}

/// Helper for creating location message metadata
class LocationMessageMetadata {
  /// Create metadata for current location message
  static Map<String, dynamic> currentLocation({
    required LatLng location,
    String? locationName,
    String? locationAddress,
  }) {
    return {
      'location_type': 'current',
      'location_lat': location.latitude,
      'location_lon': location.longitude,
      'location_name': locationName,
      'location_address': locationAddress,
    };
  }

  /// Create metadata for live location message
  static Map<String, dynamic> liveLocation({
    required String liveLocationId,
    required LatLng location,
    LatLng? destination,
    String? destinationName,
  }) {
    return {
      'location_type': 'live',
      'live_location_id': liveLocationId,
      'location_lat': location.latitude,
      'location_lon': location.longitude,
      'destination_lat': destination?.latitude,
      'destination_lon': destination?.longitude,
      'destination_name': destinationName,
    };
  }

  /// Create metadata for check-in message
  static Map<String, dynamic> checkIn({
    required String checkInId,
    required LatLng location,
    required String placeName,
    String? placeCategory,
    String? feeling,
    String? note,
  }) {
    return {
      'location_type': 'checkin',
      'shared_checkin_id': checkInId,
      'location_lat': location.latitude,
      'location_lon': location.longitude,
      'location_name': placeName,
      'place_category': placeCategory,
      'feeling': feeling,
      'note': note,
    };
  }

  /// Create metadata for place message
  static Map<String, dynamic> place({
    required LatLng location,
    required String placeName,
    String? placeAddress,
    String? placeId,
    String? placeCategory,
  }) {
    return {
      'location_type': 'place',
      'location_lat': location.latitude,
      'location_lon': location.longitude,
      'location_name': placeName,
      'location_address': placeAddress,
      'place_id': placeId,
      'place_category': placeCategory,
    };
  }

  /// Create metadata for meet here invitation message
  static Map<String, dynamic> meetHere({
    required String meetHereId,
    required LatLng location,
    required String placeName,
    DateTime? meetingTime,
    String? message,
  }) {
    return {
      'location_type': 'meet_here',
      'meet_here_id': meetHereId,
      'location_lat': location.latitude,
      'location_lon': location.longitude,
      'location_name': placeName,
      'meeting_time': meetingTime?.toIso8601String(),
      'message': message,
    };
  }

  /// Extract location from message metadata
  static LatLng? getLocation(Map<String, dynamic> metadata) {
    final lat = metadata['location_lat'];
    final lon = metadata['location_lon'];
    if (lat is num && lon is num) {
      return LatLng(lat.toDouble(), lon.toDouble());
    }
    return null;
  }

  /// Get location message type
  static LocationMessageType? getType(Map<String, dynamic> metadata) {
    final type = metadata['location_type'] as String?;
    return switch (type) {
      'current' => LocationMessageType.current,
      'live' => LocationMessageType.live,
      'checkin' => LocationMessageType.checkIn,
      'place' => LocationMessageType.place,
      'meet_here' => LocationMessageType.meetHere,
      _ => null,
    };
  }
}

/// Messages + Map Integration Service
class MessagesMapService {
  final _supabase = Supabase.instance.client;

  // ============================================================================
  // LIVE LOCATION SHARING
  // ============================================================================

  /// Start live location sharing in conversation
  Future<LiveLocationShare> startLiveLocationShare({
    required String messageId,
    required String conversationId,
    required LatLng currentLocation,
    LatLng? destination,
    String? destinationName,
    Duration duration = const Duration(hours: 1),
    int updateIntervalSeconds = 30,
  }) async {
    try {
      final expiresAt = DateTime.now().add(duration);

      final data = {
        'message_id': messageId,
        'conversation_id': conversationId,
        'sender_id': _supabase.auth.currentUser!.id,
        'current_latitude': currentLocation.latitude,
        'current_longitude': currentLocation.longitude,
        'destination_latitude': destination?.latitude,
        'destination_longitude': destination?.longitude,
        'destination_name': destinationName,
        'expires_at': expiresAt.toIso8601String(),
        'update_interval_seconds': updateIntervalSeconds,
      };

      final result = await _supabase
          .from('message_live_locations')
          .insert(data)
          .select()
          .single();

      debugPrint('[MessagesMap] Live location started: ${result['id']}');
      return LiveLocationShare.fromMap(result);
    } catch (e) {
      debugPrint('[MessagesMap] Start live location error: $e');
      rethrow;
    }
  }

  /// Update live location position
  Future<void> updateLiveLocationPosition({
    required String liveLocationId,
    required LatLng newLocation,
    double? accuracy,
    double? speed,
    double? heading,
    int? batteryLevel,
  }) async {
    try {
      await _supabase.rpc('update_live_location_position', params: {
        'live_loc_id': liveLocationId,
        'new_lat': newLocation.latitude,
        'new_lon': newLocation.longitude,
        'new_accuracy': accuracy,
        'new_speed': speed,
        'new_heading': heading,
        'new_battery': batteryLevel,
      });

      debugPrint('[MessagesMap] Live location updated');
    } catch (e) {
      debugPrint('[MessagesMap] Update live location error: $e');
      rethrow;
    }
  }

  /// Stop live location sharing
  Future<void> stopLiveLocationShare(String liveLocationId) async {
    try {
      await _supabase.rpc('stop_live_location_sharing', params: {
        'live_loc_id': liveLocationId,
      });

      debugPrint('[MessagesMap] Live location stopped: $liveLocationId');
    } catch (e) {
      debugPrint('[MessagesMap] Stop live location error: $e');
      rethrow;
    }
  }

  /// Get active live locations in conversation
  Future<List<LiveLocationShare>> getConversationLiveLocations(
      String conversationId) async {
    try {
      final results = await _supabase.rpc('get_conversation_live_locations',
          params: {'conv_id': conversationId});

      return (results as List)
          .map((r) => LiveLocationShare.fromMap(r))
          .toList();
    } catch (e) {
      debugPrint('[MessagesMap] Get live locations error: $e');
      return [];
    }
  }

  /// Get live location by ID
  Future<LiveLocationShare?> getLiveLocationById(String id) async {
    try {
      final result = await _supabase
          .from('message_live_locations')
          .select()
          .eq('id', id)
          .single();

      return LiveLocationShare.fromMap(result);
    } catch (e) {
      debugPrint('[MessagesMap] Get live location error: $e');
      return null;
    }
  }

  /// Get live location update history
  Future<List<LiveLocationUpdate>> getLiveLocationUpdates(
    String liveLocationId, {
    int limit = 50,
  }) async {
    try {
      final results = await _supabase
          .from('live_location_updates')
          .select()
          .eq('live_location_id', liveLocationId)
          .order('created_at', ascending: false)
          .limit(limit);

      return results.map((r) => LiveLocationUpdate.fromMap(r)).toList();
    } catch (e) {
      debugPrint('[MessagesMap] Get location updates error: $e');
      return [];
    }
  }

  // ============================================================================
  // MESSAGE HELPERS
  // ============================================================================

  /// Check if message has location
  bool messageHasLocation(Map<String, dynamic> metadata) {
    return metadata.containsKey('location_lat') &&
        metadata.containsKey('location_lon');
  }

  /// Get location from message
  LatLng? getMessageLocation(Map<String, dynamic> metadata) {
    return LocationMessageMetadata.getLocation(metadata);
  }

  /// Get location message type
  LocationMessageType? getMessageLocationType(Map<String, dynamic> metadata) {
    return LocationMessageMetadata.getType(metadata);
  }

  // ============================================================================
  // REALTIME SUBSCRIPTIONS
  // ============================================================================

  /// Subscribe to live location updates in conversation
  RealtimeChannel subscribeToConversationLiveLocations(
    String conversationId,
    void Function(LiveLocationShare) onUpdate,
  ) {
    return _supabase
        .channel('live_locations_$conversationId')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'message_live_locations',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'conversation_id',
        value: conversationId,
      ),
      callback: (payload) {
        try {
          final liveLocation = LiveLocationShare.fromMap(payload.newRecord);
          onUpdate(liveLocation);
        } catch (e) {
          debugPrint('[MessagesMap] Live location subscription error: $e');
        }
      },
    ).subscribe();
  }

  /// Subscribe to specific live location position updates
  RealtimeChannel subscribeToLiveLocationUpdates(
    String liveLocationId,
    void Function(LiveLocationUpdate) onUpdate,
  ) {
    return _supabase
        .channel('live_location_updates_$liveLocationId')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'live_location_updates',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'live_location_id',
        value: liveLocationId,
      ),
      callback: (payload) {
        try {
          final update = LiveLocationUpdate.fromMap(payload.newRecord);
          onUpdate(update);
        } catch (e) {
          debugPrint('[MessagesMap] Location update subscription error: $e');
        }
      },
    ).subscribe();
  }
}
