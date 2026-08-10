// Social Map Service - Check-ins, Reviews, Meet Here, Circles
library;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Check-in at a place
class CheckIn {
  final String id;
  final String userId;
  final String placeId;
  final String placeName;
  final String? placeCategory;
  final LatLng location;
  final String? feeling;
  final String? note;
  final String visibility;
  final List<String> photoUrls;
  final List<String> taggedUsers;
  final DateTime createdAt;

  const CheckIn({
    required this.id,
    required this.userId,
    required this.placeId,
    required this.placeName,
    this.placeCategory,
    required this.location,
    this.feeling,
    this.note,
    required this.visibility,
    this.photoUrls = const [],
    this.taggedUsers = const [],
    required this.createdAt,
  });

  factory CheckIn.fromMap(Map<String, dynamic> map) {
    return CheckIn(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      placeId: map['place_id'] as String,
      placeName: map['place_name'] as String,
      placeCategory: map['place_category'] as String?,
      location: LatLng(
        map['latitude'] as double,
        map['longitude'] as double,
      ),
      feeling: map['feeling'] as String?,
      note: map['note'] as String?,
      visibility: map['visibility'] as String? ?? 'friends',
      photoUrls: (map['photo_urls'] as List?)?.cast<String>() ?? [],
      taggedUsers: (map['tagged_users'] as List?)?.cast<String>() ?? [],
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'place_id': placeId,
      'place_name': placeName,
      'place_category': placeCategory,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'feeling': feeling,
      'note': note,
      'visibility': visibility,
      'photo_urls': photoUrls,
      'tagged_users': taggedUsers,
    };
  }
}

/// Place review
class PlaceReview {
  final String id;
  final String userId;
  final String placeId;
  final String placeName;
  final int rating;
  final String? reviewText;
  final Map<String, int>? categoryRatings;
  final List<String> photoUrls;
  final int helpfulCount;
  final DateTime? visitDate;
  final DateTime createdAt;
  final bool userHasVoted;

  const PlaceReview({
    required this.id,
    required this.userId,
    required this.placeId,
    required this.placeName,
    required this.rating,
    this.reviewText,
    this.categoryRatings,
    this.photoUrls = const [],
    this.helpfulCount = 0,
    this.visitDate,
    required this.createdAt,
    this.userHasVoted = false,
  });

  factory PlaceReview.fromMap(Map<String, dynamic> map) {
    Map<String, int>? catRatings;
    if (map['category_ratings'] != null) {
      final jsonRatings = map['category_ratings'] as Map<String, dynamic>;
      catRatings = jsonRatings.map((k, v) => MapEntry(k, v as int));
    }

    return PlaceReview(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      placeId: map['place_id'] as String,
      placeName: map['place_name'] as String,
      rating: map['rating'] as int,
      reviewText: map['review_text'] as String?,
      categoryRatings: catRatings,
      photoUrls: (map['photo_urls'] as List?)?.cast<String>() ?? [],
      helpfulCount: map['helpful_count'] as int? ?? 0,
      visitDate: map['visit_date'] != null
          ? DateTime.parse(map['visit_date'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      userHasVoted: map['user_has_voted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'place_id': placeId,
      'place_name': placeName,
      'rating': rating,
      'review_text': reviewText,
      'category_ratings': categoryRatings,
      'photo_urls': photoUrls,
      'visit_date': visitDate?.toIso8601String().split('T').first,
    };
  }
}

/// Meet Here invitation
class MeetHereInvitation {
  final String id;
  final String creatorId;
  final String placeId;
  final String placeName;
  final LatLng location;
  final DateTime? meetingTime;
  final String? message;
  final List<String> invitedUsers;
  final List<String> acceptedUsers;
  final List<String> declinedUsers;
  final String status;
  final DateTime createdAt;

  const MeetHereInvitation({
    required this.id,
    required this.creatorId,
    required this.placeId,
    required this.placeName,
    required this.location,
    this.meetingTime,
    this.message,
    this.invitedUsers = const [],
    this.acceptedUsers = const [],
    this.declinedUsers = const [],
    required this.status,
    required this.createdAt,
  });

  factory MeetHereInvitation.fromMap(Map<String, dynamic> map) {
    return MeetHereInvitation(
      id: map['id'] as String,
      creatorId: map['creator_id'] as String,
      placeId: map['place_id'] as String,
      placeName: map['place_name'] as String,
      location: LatLng(
        map['latitude'] as double,
        map['longitude'] as double,
      ),
      meetingTime: map['meeting_time'] != null
          ? DateTime.parse(map['meeting_time'] as String)
          : null,
      message: map['message'] as String?,
      invitedUsers: (map['invited_users'] as List?)?.cast<String>() ?? [],
      acceptedUsers: (map['accepted_users'] as List?)?.cast<String>() ?? [],
      declinedUsers: (map['declined_users'] as List?)?.cast<String>() ?? [],
      status: map['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'place_id': placeId,
      'place_name': placeName,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'meeting_time': meetingTime?.toIso8601String(),
      'message': message,
      'invited_users': invitedUsers,
    };
  }
}

/// Family Circle
class FamilyCircle {
  final String id;
  final String name;
  final String? description;
  final String creatorId;
  final List<String> memberIds;
  final List<String> adminIds;
  final Map<String, dynamic> settings;
  final DateTime createdAt;

  const FamilyCircle({
    required this.id,
    required this.name,
    this.description,
    required this.creatorId,
    this.memberIds = const [],
    this.adminIds = const [],
    this.settings = const {},
    required this.createdAt,
  });

  factory FamilyCircle.fromMap(Map<String, dynamic> map) {
    return FamilyCircle(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      creatorId: map['creator_id'] as String,
      memberIds: (map['member_ids'] as List?)?.cast<String>() ?? [],
      adminIds: (map['admin_ids'] as List?)?.cast<String>() ?? [],
      settings: (map['settings'] as Map?)?.cast<String, dynamic>() ??
          {
            'auto_share_location': true,
            'show_battery': true,
            'show_driving_status': true
          },
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'member_ids': memberIds,
      'admin_ids': adminIds,
      'settings': settings,
    };
  }

  FamilyCircle copyWith({
    String? name,
    String? description,
    List<String>? memberIds,
    List<String>? adminIds,
    Map<String, dynamic>? settings,
  }) {
    return FamilyCircle(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      creatorId: creatorId,
      memberIds: memberIds ?? this.memberIds,
      adminIds: adminIds ?? this.adminIds,
      settings: settings ?? this.settings,
      createdAt: createdAt,
    );
  }
}

/// Social Map Service
class SocialMapService {
  final _supabase = Supabase.instance.client;

  // ============================================================================
  // CHECK-INS
  // ============================================================================

  /// Create check-in
  Future<CheckIn> createCheckIn(CheckIn checkIn) async {
    try {
      final result =
          await _supabase.from('check_ins').insert(checkIn.toMap()).select().single();

      debugPrint('[SocialMap] Check-in created: ${result['id']}');
      return CheckIn.fromMap(result);
    } catch (e) {
      debugPrint('[SocialMap] Create check-in error: $e');
      rethrow;
    }
  }

  /// Get user's check-ins
  Future<List<CheckIn>> getUserCheckIns(String userId, {int limit = 50}) async {
    try {
      final results = await _supabase
          .from('check_ins')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);

      return results.map((r) => CheckIn.fromMap(r)).toList();
    } catch (e) {
      debugPrint('[SocialMap] Get user check-ins error: $e');
      return [];
    }
  }

  /// Get nearby check-ins
  Future<List<CheckIn>> getNearbyCheckIns(
    LatLng location, {
    double radiusKm = 5.0,
    int limit = 50,
  }) async {
    try {
      final results = await _supabase.rpc('get_nearby_check_ins', params: {
        'lat': location.latitude,
        'lon': location.longitude,
        'radius_km': radiusKm,
        'limit_count': limit,
      });

      return (results as List).map((r) => CheckIn.fromMap(r)).toList();
    } catch (e) {
      debugPrint('[SocialMap] Get nearby check-ins error: $e');
      return [];
    }
  }

  /// Delete check-in
  Future<void> deleteCheckIn(String checkInId) async {
    try {
      await _supabase.from('check_ins').delete().eq('id', checkInId);
      debugPrint('[SocialMap] Check-in deleted: $checkInId');
    } catch (e) {
      debugPrint('[SocialMap] Delete check-in error: $e');
      rethrow;
    }
  }

  // ============================================================================
  // REVIEWS
  // ============================================================================

  /// Create or update review
  Future<PlaceReview> createOrUpdateReview(PlaceReview review) async {
    try {
      final result = await _supabase
          .from('place_reviews')
          .upsert(review.toMap())
          .select()
          .single();

      debugPrint('[SocialMap] Review saved: ${result['id']}');
      return PlaceReview.fromMap(result);
    } catch (e) {
      debugPrint('[SocialMap] Save review error: $e');
      rethrow;
    }
  }

  /// Get place reviews
  Future<List<PlaceReview>> getPlaceReviews(String placeId,
      {int limit = 20}) async {
    try {
      final results = await _supabase.rpc('get_place_reviews', params: {
        'place_id_param': placeId,
        'limit_count': limit,
      });

      return (results as List).map((r) => PlaceReview.fromMap(r)).toList();
    } catch (e) {
      debugPrint('[SocialMap] Get place reviews error: $e');
      return [];
    }
  }

  /// Vote review as helpful
  Future<void> voteReviewHelpful(String reviewId, bool helpful) async {
    try {
      if (helpful) {
        await _supabase.from('review_helpful_votes').insert({
          'review_id': reviewId,
          'user_id': _supabase.auth.currentUser!.id,
        });
      } else {
        await _supabase
            .from('review_helpful_votes')
            .delete()
            .eq('review_id', reviewId)
            .eq('user_id', _supabase.auth.currentUser!.id);
      }
      debugPrint('[SocialMap] Review vote updated: $helpful');
    } catch (e) {
      debugPrint('[SocialMap] Vote review error: $e');
      rethrow;
    }
  }

  /// Delete review
  Future<void> deleteReview(String reviewId) async {
    try {
      await _supabase.from('place_reviews').delete().eq('id', reviewId);
      debugPrint('[SocialMap] Review deleted: $reviewId');
    } catch (e) {
      debugPrint('[SocialMap] Delete review error: $e');
      rethrow;
    }
  }

  // ============================================================================
  // MEET HERE
  // ============================================================================

  /// Create meet here invitation
  Future<MeetHereInvitation> createMeetHereInvitation(
      MeetHereInvitation invitation) async {
    try {
      final result = await _supabase
          .from('meet_here_invitations')
          .insert(invitation.toMap())
          .select()
          .single();

      debugPrint('[SocialMap] Meet here invitation created: ${result['id']}');
      return MeetHereInvitation.fromMap(result);
    } catch (e) {
      debugPrint('[SocialMap] Create meet here error: $e');
      rethrow;
    }
  }

  /// Get user's meet here invitations
  Future<List<MeetHereInvitation>> getMeetHereInvitations(
      {String status = 'pending'}) async {
    try {
      final userId = _supabase.auth.currentUser!.id;
      final results = await _supabase
          .from('meet_here_invitations')
          .select()
          .or('creator_id.eq.$userId,invited_users.cs.{$userId}')
          .eq('status', status)
          .order('meeting_time', ascending: true);

      return results.map((r) => MeetHereInvitation.fromMap(r)).toList();
    } catch (e) {
      debugPrint('[SocialMap] Get meet here invitations error: $e');
      return [];
    }
  }

  /// Respond to meet here invitation
  Future<void> respondToMeetHere(String invitationId, bool accept) async {
    try {
      final userId = _supabase.auth.currentUser!.id;
      final invitation = await _supabase
          .from('meet_here_invitations')
          .select()
          .eq('id', invitationId)
          .single();

      final acceptedUsers = List<String>.from(invitation['accepted_users'] ?? []);
      final declinedUsers = List<String>.from(invitation['declined_users'] ?? []);

      if (accept) {
        if (!acceptedUsers.contains(userId)) acceptedUsers.add(userId);
        declinedUsers.remove(userId);
      } else {
        if (!declinedUsers.contains(userId)) declinedUsers.add(userId);
        acceptedUsers.remove(userId);
      }

      await _supabase.from('meet_here_invitations').update({
        'accepted_users': acceptedUsers,
        'declined_users': declinedUsers,
      }).eq('id', invitationId);

      debugPrint('[SocialMap] Meet here response: $accept');
    } catch (e) {
      debugPrint('[SocialMap] Respond to meet here error: $e');
      rethrow;
    }
  }

  /// Cancel meet here invitation
  Future<void> cancelMeetHere(String invitationId) async {
    try {
      await _supabase
          .from('meet_here_invitations')
          .update({'status': 'cancelled'}).eq('id', invitationId);
      debugPrint('[SocialMap] Meet here cancelled: $invitationId');
    } catch (e) {
      debugPrint('[SocialMap] Cancel meet here error: $e');
      rethrow;
    }
  }

  // ============================================================================
  // FAMILY CIRCLES
  // ============================================================================

  /// Create family circle
  Future<FamilyCircle> createFamilyCircle(FamilyCircle circle) async {
    try {
      final result =
          await _supabase.from('family_circles').insert(circle.toMap()).select().single();

      debugPrint('[SocialMap] Family circle created: ${result['id']}');
      return FamilyCircle.fromMap(result);
    } catch (e) {
      debugPrint('[SocialMap] Create family circle error: $e');
      rethrow;
    }
  }

  /// Get user's family circles
  Future<List<FamilyCircle>> getUserFamilyCircles() async {
    try {
      final userId = _supabase.auth.currentUser!.id;
      final results = await _supabase
          .from('family_circles')
          .select()
          .or('creator_id.eq.$userId,member_ids.cs.{$userId}')
          .order('created_at', ascending: false);

      return results.map((r) => FamilyCircle.fromMap(r)).toList();
    } catch (e) {
      debugPrint('[SocialMap] Get family circles error: $e');
      return [];
    }
  }

  /// Update family circle
  Future<void> updateFamilyCircle(FamilyCircle circle) async {
    try {
      await _supabase
          .from('family_circles')
          .update(circle.toMap())
          .eq('id', circle.id);
      debugPrint('[SocialMap] Family circle updated: ${circle.id}');
    } catch (e) {
      debugPrint('[SocialMap] Update family circle error: $e');
      rethrow;
    }
  }

  /// Add member to circle
  Future<void> addCircleMember(String circleId, String userId) async {
    try {
      final circle =
          await _supabase.from('family_circles').select().eq('id', circleId).single();

      final memberIds = List<String>.from(circle['member_ids'] ?? []);
      if (!memberIds.contains(userId)) {
        memberIds.add(userId);
        await _supabase
            .from('family_circles')
            .update({'member_ids': memberIds}).eq('id', circleId);
        debugPrint('[SocialMap] Member added to circle: $userId');
      }
    } catch (e) {
      debugPrint('[SocialMap] Add circle member error: $e');
      rethrow;
    }
  }

  /// Remove member from circle
  Future<void> removeCircleMember(String circleId, String userId) async {
    try {
      final circle =
          await _supabase.from('family_circles').select().eq('id', circleId).single();

      final memberIds = List<String>.from(circle['member_ids'] ?? []);
      memberIds.remove(userId);

      final adminIds = List<String>.from(circle['admin_ids'] ?? []);
      adminIds.remove(userId);

      await _supabase.from('family_circles').update({
        'member_ids': memberIds,
        'admin_ids': adminIds,
      }).eq('id', circleId);

      debugPrint('[SocialMap] Member removed from circle: $userId');
    } catch (e) {
      debugPrint('[SocialMap] Remove circle member error: $e');
      rethrow;
    }
  }

  /// Delete family circle
  Future<void> deleteFamilyCircle(String circleId) async {
    try {
      await _supabase.from('family_circles').delete().eq('id', circleId);
      debugPrint('[SocialMap] Family circle deleted: $circleId');
    } catch (e) {
      debugPrint('[SocialMap] Delete family circle error: $e');
      rethrow;
    }
  }

  /// Invite user to circle
  Future<void> inviteToCircle(String circleId, String userId) async {
    try {
      await _supabase.from('circle_invitations').insert({
        'circle_id': circleId,
        'invited_user_id': userId,
        'invited_by_id': _supabase.auth.currentUser!.id,
      });
      debugPrint('[SocialMap] Circle invitation sent: $userId');
    } catch (e) {
      debugPrint('[SocialMap] Invite to circle error: $e');
      rethrow;
    }
  }

  /// Get circle invitations
  Future<List<Map<String, dynamic>>> getCircleInvitations(
      {String status = 'pending'}) async {
    try {
      final userId = _supabase.auth.currentUser!.id;
      final results = await _supabase
          .from('circle_invitations')
          .select('*, family_circles(*)')
          .eq('invited_user_id', userId)
          .eq('status', status)
          .order('created_at', ascending: false);

      return results.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[SocialMap] Get circle invitations error: $e');
      return [];
    }
  }

  /// Respond to circle invitation
  Future<void> respondToCircleInvitation(String invitationId,
      bool accept) async {
    try {
      if (accept) {
        final invitation = await _supabase
            .from('circle_invitations')
            .select()
            .eq('id', invitationId)
            .single();

        await addCircleMember(
          invitation['circle_id'] as String,
          invitation['invited_user_id'] as String,
        );
      }

      await _supabase.from('circle_invitations').update({
        'status': accept ? 'accepted' : 'declined',
      }).eq('id', invitationId);

      debugPrint('[SocialMap] Circle invitation response: $accept');
    } catch (e) {
      debugPrint('[SocialMap] Respond to circle invitation error: $e');
      rethrow;
    }
  }

  // ============================================================================
  // REALTIME SUBSCRIPTIONS
  // ============================================================================

  /// Subscribe to nearby check-ins
  RealtimeChannel subscribeToNearbyCheckIns(
    LatLng location,
    void Function(CheckIn) onCheckIn,
  ) {
    return _supabase.channel('nearby_check_ins').onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'check_ins',
      callback: (payload) {
        try {
          final checkIn = CheckIn.fromMap(payload.newRecord);
          // Calculate distance
          final distance = const Distance().as(
            LengthUnit.Kilometer,
            location,
            checkIn.location,
          );
          if (distance <= 5.0) {
            onCheckIn(checkIn);
          }
        } catch (e) {
          debugPrint('[SocialMap] Check-in subscription error: $e');
        }
      },
    ).subscribe();
  }

  /// Subscribe to meet here invitations
  RealtimeChannel subscribeToMeetHere(
    void Function(MeetHereInvitation) onInvitation,
  ) {
    final userId = _supabase.auth.currentUser!.id;
    return _supabase.channel('meet_here_$userId').onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'meet_here_invitations',
      callback: (payload) {
        try {
          final invitation = MeetHereInvitation.fromMap(payload.newRecord);
          if (invitation.invitedUsers.contains(userId) ||
              invitation.creatorId == userId) {
            onInvitation(invitation);
          }
        } catch (e) {
          debugPrint('[SocialMap] Meet here subscription error: $e');
        }
      },
    ).subscribe();
  }

  /// Subscribe to family circle updates
  RealtimeChannel subscribeToFamilyCircle(
    String circleId,
    void Function(FamilyCircle) onUpdate,
  ) {
    return _supabase.channel('circle_$circleId').onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'family_circles',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: circleId,
      ),
      callback: (payload) {
        try {
          final circle = FamilyCircle.fromMap(payload.newRecord);
          onUpdate(circle);
        } catch (e) {
          debugPrint('[SocialMap] Circle subscription error: $e');
        }
      },
    ).subscribe();
  }
}
