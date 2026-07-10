import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import 'admin_models.dart';

/// Ported from web AdminPage + useAdminAccess + useAdminAnalytics +
/// useAdminOnlineUsers — real `user_roles`, `verification_requests`,
/// `profiles`, `notifications`, `posts`, `comments`, RPCs.
class AdminRepository {
  SupabaseClient get _c => supabase;

  // ─────────────────────────────────────────────────────────────
  // Access
  // ─────────────────────────────────────────────────────────────

  Future<bool> isAdmin(String userId) async {
    final res = await _c
        .from('user_roles')
        .select('role')
        .eq('user_id', userId)
        .eq('role', 'admin')
        .maybeSingle();
    return res != null;
  }

  // ─────────────────────────────────────────────────────────────
  // Verification requests
  // ─────────────────────────────────────────────────────────────

  Future<List<VerificationRequest>> fetchRequests() async {
    final res = await _c
        .from('verification_requests')
        .select(
            '*, profile:profiles!verification_requests_user_id_fkey(username, display_name, avatar_url, is_verified)')
        .order('created_at', ascending: false);
    return (res as List)
        .map((e) => VerificationRequest.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> approve(VerificationRequest req, String reviewerId) async {
    await _c.from('verification_requests').update({
      'status': 'approved',
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      'reviewed_by': reviewerId,
    }).eq('id', req.id);
    await _c
        .from('profiles')
        .update({'is_verified': true}).eq('id', req.userId);
    await _c.from('notifications').insert({
      'user_id': req.userId,
      'type': 'verification',
      'title': 'Verification Approved',
      'body': 'Congratulations! Your account has been verified.',
      'data': {'request_id': req.id},
    });
  }

  Future<void> reject(
      VerificationRequest req, String reviewerId, String reason) async {
    await _c.from('verification_requests').update({
      'status': 'rejected',
      'rejection_reason': reason,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      'reviewed_by': reviewerId,
    }).eq('id', req.id);
    await _c.from('notifications').insert({
      'user_id': req.userId,
      'type': 'verification',
      'title': 'Verification Rejected',
      'body': reason.isEmpty
          ? 'Your verification request was not approved.'
          : reason,
      'data': {'request_id': req.id},
    });
  }

  // ─────────────────────────────────────────────────────────────
  // Admin roles
  // ─────────────────────────────────────────────────────────────

  Future<List<AdminUser>> fetchAdmins() async {
    final res = await _c
        .from('user_roles')
        .select(
            '*, profile:profiles!user_roles_user_id_fkey(username, display_name, avatar_url)')
        .eq('role', 'admin');
    return (res as List)
        .map((e) => AdminUser.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns an error message string when grant fails, null on success.
  Future<String?> grantAdminByUsername(
      String username, String grantedBy) async {
    final profile = await _c
        .from('profiles')
        .select('id')
        .eq('username', username.replaceAll('@', ''))
        .maybeSingle();
    if (profile == null) return 'User not found';
    try {
      await _c.from('user_roles').insert({
        'user_id': profile['id'],
        'role': 'admin',
        'granted_by': grantedBy,
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> revokeAdmin(String userId) async {
    await _c
        .from('user_roles')
        .delete()
        .eq('user_id', userId)
        .eq('role', 'admin');
  }

  // ─────────────────────────────────────────────────────────────
  // Content management
  // ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPosts({int limit = 100}) async {
    final r = await _c
        .from('posts')
        .select(
            '*, profile:profiles!posts_user_id_fkey(username, display_name, avatar_url, is_verified)')
        .order('created_at', ascending: false)
        .limit(limit);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchComments({int limit = 100}) async {
    final r = await _c
        .from('comments')
        .select(
            '*, profile:profiles!comments_user_id_fkey(username, display_name, avatar_url, is_verified)')
        .order('created_at', ascending: false)
        .limit(limit);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchUsers({int limit = 100}) async {
    final r = await _c
        .from('profiles')
        .select('*')
        .order('created_at', ascending: false)
        .limit(limit);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchUserPosts(String userId,
      {int limit = 50}) async {
    final r = await _c
        .from('posts')
        .select(
            '*, profile:profiles!posts_user_id_fkey(username, display_name, avatar_url, is_verified)')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchUserComments(String userId,
      {int limit = 50}) async {
    final r = await _c
        .from('comments')
        .select(
            '*, profile:profiles!comments_user_id_fkey(username, display_name, avatar_url, is_verified)')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<void> deletePost(String id) async =>
      _c.from('posts').delete().eq('id', id);
  Future<void> deleteComment(String id) async =>
      _c.from('comments').delete().eq('id', id);

  Future<void> toggleVerification(String userId, bool current) async {
    await _c
        .from('profiles')
        .update({'is_verified': !current}).eq('id', userId);
  }

  // ─────────────────────────────────────────────────────────────
  // Counters (legacy)
  // ─────────────────────────────────────────────────────────────

  Future<AdminStats> fetchStats() async {
    Future<int> count(String table) async {
      try {
        return await _c.from(table).count();
      } catch (_) {
        return 0;
      }
    }

    final results = await Future.wait([
      count('profiles'),
      count('posts'),
      count('products'),
      count('channels'),
    ]);
    return AdminStats(
      users: results[0],
      posts: results[1],
      products: results[2],
      channels: results[3],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Analytics (7 RPCs — see useAdminAnalytics.ts)
  // ─────────────────────────────────────────────────────────────

  Future<AdminAnalyticsSnapshot> fetchAnalytics() async {
    Future<dynamic> rpc(String name) async {
      try {
        return await _c.rpc(name);
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait([
      rpc('get_admin_platform_stats'),
      rpc('get_admin_hourly_activity'),
      rpc('get_admin_page_stats'),
      rpc('get_admin_country_stats'),
      rpc('get_admin_age_stats'),
      rpc('get_admin_dau_trend'),
      rpc('get_admin_weekly_pattern'),
    ]);

    PlatformStats stats = const PlatformStats();
    final r0 = results[0];
    if (r0 is Map<String, dynamic>) {
      stats = PlatformStats.fromMap(r0);
    } else if (r0 is List && r0.isNotEmpty && r0.first is Map) {
      stats = PlatformStats.fromMap(r0.first as Map<String, dynamic>);
    }

    List<T> parseList<T>(
        dynamic raw, T Function(Map<String, dynamic>) parse) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(parse)
          .toList();
    }

    return AdminAnalyticsSnapshot(
      stats: stats,
      hourly: parseList(results[1], HourlyActivity.fromMap),
      pages: parseList(results[2], PageStat.fromMap),
      countries: parseList(results[3], CountryStat.fromMap),
      ages: parseList(results[4], AgeStat.fromMap),
      dau: parseList(results[5], DauPoint.fromMap),
      weekly: parseList(results[6], WeeklyPoint.fromMap),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Online users — mirrors useAdminOnlineUsers.ts
  // ─────────────────────────────────────────────────────────────

  Future<List<OnlineUser>> fetchOnlineUsers() async {
    final cutoff =
        DateTime.now().toUtc().subtract(const Duration(seconds: 30));
    final r = await _c
        .from('profiles')
        .select('id, username, display_name, avatar_url, country, last_seen')
        .eq('is_online', true)
        .gte('last_seen', cutoff.toIso8601String())
        .limit(500);
    return (r as List)
        .map((e) => OnlineUser.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Groups online users by country and attaches centroid coords.
  /// Filters out countries without known coordinates (same as web).
  List<OnlineCountry> groupByCountry(List<OnlineUser> users) {
    final byCountry = <String, List<OnlineUser>>{};
    for (final u in users) {
      final country = u.country ?? 'Unknown';
      byCountry.putIfAbsent(country, () => []).add(u);
    }
    final list = byCountry.entries
        .map((e) {
          final coords = kCountryCoords[e.key];
          if (coords == null) return null;
          return OnlineCountry(
            country: e.key,
            count: e.value.length,
            lat: coords.lat,
            lng: coords.lng,
            users: e.value,
          );
        })
        .whereType<OnlineCountry>()
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return list;
  }
}
