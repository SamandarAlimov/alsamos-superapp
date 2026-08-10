// Privacy Service - Location privacy, ghost mode, privacy zones
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Location visibility level
enum LocationVisibility {
  public, // Everyone can see
  followers, // Only followers
  friends, // Only mutual friends
  family, // Only family circle
  selected, // Selected users only
  nobody, // Completely hidden (ghost mode)
}

/// Privacy zone where location is hidden
class PrivacyZone {
  final String id;
  final String userId;
  final String name;
  final LatLng center;
  final double radiusMeters;
  final bool isActive;
  final DateTime createdAt;

  const PrivacyZone({
    required this.id,
    required this.userId,
    required this.name,
    required this.center,
    required this.radiusMeters,
    this.isActive = true,
    required this.createdAt,
  });

  factory PrivacyZone.fromMap(Map<String, dynamic> map) {
    final centerStr = map['center'] as String;
    final parts = centerStr.split(',');
    
    return PrivacyZone(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      name: map['name'] as String,
      center: LatLng(
        double.parse(parts[0]),
        double.parse(parts[1]),
      ),
      radiusMeters: (map['radius_meters'] as num).toDouble(),
      isActive: map['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        if (id.isNotEmpty) 'id': id,
        'user_id': userId,
        'name': name,
        'center': '${center.latitude},${center.longitude}',
        'radius_meters': radiusMeters,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
      };

  bool containsLocation(LatLng location) {
    return _calculateDistance(center, location) <= radiusMeters;
  }

  double _calculateDistance(LatLng p1, LatLng p2) {
    const R = 6371000.0; // Earth radius in meters
    final dLat = _toRadians(p2.latitude - p1.latitude);
    final dLon = _toRadians(p2.longitude - p1.longitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(p1.latitude)) *
            math.cos(_toRadians(p2.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;
}

/// Temporary location share token
class LocationShareToken {
  final String id;
  final String userId;
  final DateTime expiresAt;
  final List<String> allowedUserIds;
  final bool isActive;

  const LocationShareToken({
    required this.id,
    required this.userId,
    required this.expiresAt,
    this.allowedUserIds = const [],
    this.isActive = true,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  factory LocationShareToken.fromMap(Map<String, dynamic> map) =>
      LocationShareToken(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        expiresAt: DateTime.parse(map['expires_at'] as String),
        allowedUserIds: map['allowed_users'] != null
            ? List<String>.from(map['allowed_users'] as List)
            : [],
        isActive: map['is_active'] as bool? ?? true,
      );
}

/// Privacy settings for location sharing
class PrivacySettings {
  final LocationVisibility visibility;
  final bool ghostModeEnabled;
  final bool incognitoModeEnabled;
  final bool shareHistory;
  final bool shareAccurateLocation; // False = fuzzy location
  final List<String> blockedUserIds;
  final List<String> allowedUserIds;
  final bool pauseTracking;

  const PrivacySettings({
    this.visibility = LocationVisibility.followers,
    this.ghostModeEnabled = false,
    this.incognitoModeEnabled = false,
    this.shareHistory = true,
    this.shareAccurateLocation = true,
    this.blockedUserIds = const [],
    this.allowedUserIds = const [],
    this.pauseTracking = false,
  });

  factory PrivacySettings.fromMap(Map<String, dynamic> map) => PrivacySettings(
        visibility: LocationVisibility.values.firstWhere(
          (v) => v.name == (map['visibility'] as String?),
          orElse: () => LocationVisibility.followers,
        ),
        ghostModeEnabled: map['ghost_mode_enabled'] as bool? ?? false,
        incognitoModeEnabled: map['incognito_mode_enabled'] as bool? ?? false,
        shareHistory: map['share_history'] as bool? ?? true,
        shareAccurateLocation: map['share_accurate_location'] as bool? ?? true,
        blockedUserIds: map['blocked_users'] != null
            ? List<String>.from(map['blocked_users'] as List)
            : [],
        allowedUserIds: map['allowed_users'] != null
            ? List<String>.from(map['allowed_users'] as List)
            : [],
        pauseTracking: map['pause_tracking'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'visibility': visibility.name,
        'ghost_mode_enabled': ghostModeEnabled,
        'incognito_mode_enabled': incognitoModeEnabled,
        'share_history': shareHistory,
        'share_accurate_location': shareAccurateLocation,
        'blocked_users': blockedUserIds,
        'allowed_users': allowedUserIds,
        'pause_tracking': pauseTracking,
      };

  PrivacySettings copyWith({
    LocationVisibility? visibility,
    bool? ghostModeEnabled,
    bool? incognitoModeEnabled,
    bool? shareHistory,
    bool? shareAccurateLocation,
    List<String>? blockedUserIds,
    List<String>? allowedUserIds,
    bool? pauseTracking,
  }) =>
      PrivacySettings(
        visibility: visibility ?? this.visibility,
        ghostModeEnabled: ghostModeEnabled ?? this.ghostModeEnabled,
        incognitoModeEnabled: incognitoModeEnabled ?? this.incognitoModeEnabled,
        shareHistory: shareHistory ?? this.shareHistory,
        shareAccurateLocation:
            shareAccurateLocation ?? this.shareAccurateLocation,
        blockedUserIds: blockedUserIds ?? this.blockedUserIds,
        allowedUserIds: allowedUserIds ?? this.allowedUserIds,
        pauseTracking: pauseTracking ?? this.pauseTracking,
      );
}

/// Privacy Service
class PrivacyService {
  final _supabase = Supabase.instance.client;

  // ═══════════════════════════════════════════════════════════════════════
  // Privacy Settings
  // ═══════════════════════════════════════════════════════════════════════

  /// Get current privacy settings
  Future<PrivacySettings> getSettings() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return const PrivacySettings();

      final result = await _supabase
          .from('privacy_settings')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (result == null) {
        return const PrivacySettings();
      }

      return PrivacySettings.fromMap(result);
    } catch (e) {
      debugPrint('[PrivacyService] Get settings error: $e');
      return const PrivacySettings();
    }
  }

  /// Update privacy settings
  Future<void> updateSettings(PrivacySettings settings) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase.from('privacy_settings').upsert({
        'user_id': user.id,
        ...settings.toMap(),
      });
    } catch (e) {
      debugPrint('[PrivacyService] Update settings error: $e');
    }
  }

  /// Enable ghost mode (hide from everyone)
  Future<void> enableGhostMode() async {
    final settings = await getSettings();
    await updateSettings(settings.copyWith(
      ghostModeEnabled: true,
      visibility: LocationVisibility.nobody,
    ));

    // Stop sharing location
    await _stopLocationSharing();
  }

  /// Disable ghost mode
  Future<void> disableGhostMode() async {
    final settings = await getSettings();
    await updateSettings(settings.copyWith(
      ghostModeEnabled: false,
      visibility: LocationVisibility.followers,
    ));
  }

  /// Enable incognito mode (no history recording)
  Future<void> enableIncognitoMode() async {
    final settings = await getSettings();
    await updateSettings(settings.copyWith(
      incognitoModeEnabled: true,
      shareHistory: false,
    ));
  }

  /// Disable incognito mode
  Future<void> disableIncognitoMode() async {
    final settings = await getSettings();
    await updateSettings(settings.copyWith(
      incognitoModeEnabled: false,
      shareHistory: true,
    ));
  }

  Future<void> _stopLocationSharing() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase
          .from('profiles')
          .update({'location': null}).eq('id', user.id);
    } catch (e) {
      debugPrint('[PrivacyService] Stop sharing error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Privacy Zones
  // ═══════════════════════════════════════════════════════════════════════

  /// Get all privacy zones
  Future<List<PrivacyZone>> getPrivacyZones() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final results = await _supabase
          .from('privacy_zones')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      return (results as List)
          .map((m) => PrivacyZone.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[PrivacyService] Get zones error: $e');
      return [];
    }
  }

  /// Add privacy zone
  Future<void> addPrivacyZone(PrivacyZone zone) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase.from('privacy_zones').insert({
        'user_id': user.id,
        'name': zone.name,
        'center': '${zone.center.latitude},${zone.center.longitude}',
        'radius_meters': zone.radiusMeters,
        'is_active': zone.isActive,
      });
    } catch (e) {
      debugPrint('[PrivacyService] Add zone error: $e');
    }
  }

  /// Update privacy zone
  Future<void> updatePrivacyZone(PrivacyZone zone) async {
    try {
      await _supabase.from('privacy_zones').update({
        'name': zone.name,
        'center': '${zone.center.latitude},${zone.center.longitude}',
        'radius_meters': zone.radiusMeters,
        'is_active': zone.isActive,
      }).eq('id', zone.id);
    } catch (e) {
      debugPrint('[PrivacyService] Update zone error: $e');
    }
  }

  /// Delete privacy zone
  Future<void> deletePrivacyZone(String zoneId) async {
    try {
      await _supabase.from('privacy_zones').delete().eq('id', zoneId);
    } catch (e) {
      debugPrint('[PrivacyService] Delete zone error: $e');
    }
  }

  /// Check if location is in any privacy zone
  Future<bool> isInPrivacyZone(LatLng location) async {
    final zones = await getPrivacyZones();
    return zones.any((zone) => zone.isActive && zone.containsLocation(location));
  }

  /// Get fuzzy location (for approximate sharing)
  LatLng getFuzzyLocation(LatLng accurate) {
    // Add random offset: ±0.01 degrees (~1km)
    final random = math.Random();
    final latOffset = (random.nextDouble() - 0.5) * 0.02;
    final lngOffset = (random.nextDouble() - 0.5) * 0.02;

    return LatLng(
      accurate.latitude + latOffset,
      accurate.longitude + lngOffset,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Temporary Location Sharing
  // ═══════════════════════════════════════════════════════════════════════

  /// Create temporary share token
  Future<String?> createShareToken({
    required Duration duration,
    List<String> allowedUserIds = const [],
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final result = await _supabase.from('location_share_tokens').insert({
        'user_id': user.id,
        'expires_at': DateTime.now().add(duration).toIso8601String(),
        'allowed_users': allowedUserIds.isEmpty ? null : allowedUserIds,
      }).select('id');

      if (result.isEmpty) return null;
      return (result.first as Map)['id'] as String;
    } catch (e) {
      debugPrint('[PrivacyService] Create token error: $e');
      return null;
    }
  }

  /// Revoke share token
  Future<void> revokeShareToken(String tokenId) async {
    try {
      await _supabase
          .from('location_share_tokens')
          .update({'is_active': false}).eq('id', tokenId);
    } catch (e) {
      debugPrint('[PrivacyService] Revoke token error: $e');
    }
  }

  /// Get active share tokens
  Future<List<LocationShareToken>> getActiveTokens() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final results = await _supabase
          .from('location_share_tokens')
          .select()
          .eq('user_id', user.id)
          .eq('is_active', true)
          .gte('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false);

      return (results as List)
          .map((m) => LocationShareToken.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[PrivacyService] Get tokens error: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // User Blocking
  // ═══════════════════════════════════════════════════════════════════════

  /// Block user from seeing location
  Future<void> blockUser(String userId) async {
    final settings = await getSettings();
    final blocked = [...settings.blockedUserIds];
    if (!blocked.contains(userId)) {
      blocked.add(userId);
      await updateSettings(settings.copyWith(blockedUserIds: blocked));
    }
  }

  /// Unblock user
  Future<void> unblockUser(String userId) async {
    final settings = await getSettings();
    final blocked = [...settings.blockedUserIds];
    blocked.remove(userId);
    await updateSettings(settings.copyWith(blockedUserIds: blocked));
  }

  /// Check if user is blocked
  Future<bool> isUserBlocked(String userId) async {
    final settings = await getSettings();
    return settings.blockedUserIds.contains(userId);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Location History Privacy
  // ═══════════════════════════════════════════════════════════════════════

  /// Delete location history for date range
  Future<void> deleteHistory({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase
          .from('location_history')
          .delete()
          .eq('user_id', user.id)
          .gte('recorded_at', startDate.toIso8601String())
          .lte('recorded_at', endDate.toIso8601String());
    } catch (e) {
      debugPrint('[PrivacyService] Delete history error: $e');
    }
  }

  /// Delete all location history
  Future<void> deleteAllHistory() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase
          .from('location_history')
          .delete()
          .eq('user_id', user.id);
    } catch (e) {
      debugPrint('[PrivacyService] Delete all history error: $e');
    }
  }

  /// Export location history (for data portability)
  Future<Map<String, dynamic>> exportHistory() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return {};

      final history = await _supabase
          .from('location_history')
          .select()
          .eq('user_id', user.id)
          .order('recorded_at', ascending: false);

      return {
        'export_date': DateTime.now().toIso8601String(),
        'user_id': user.id,
        'count': (history as List).length,
        'data': history,
      };
    } catch (e) {
      debugPrint('[PrivacyService] Export history error: $e');
      return {};
    }
  }
}
