import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';
import 'ad_model.dart';

/// Full web-parity port of `useAds.ts` / `useAdStats.ts`.
class AdsRepository extends BaseRepository {
  const AdsRepository({
    SupabaseDataSource db = const SupabaseDataSource(),
  }) : _db = db;

  final SupabaseDataSource _db;

  // ---------------------------- My ads ----------------------------

  Future<List<Ad>> fetchMyAds(String userId) async {
    return guard('fetchMyAds', () async {
      final data = await _db
          .table('ads')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return (data as List)
          .map((m) => Ad.fromMap(m as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> updateStatus(String adId, String status) async {
    return guard('updateStatus', () async {
      await _db.table('ads').update({'status': status}).eq('id', adId);
    });
  }

  Future<void> pauseAd(String adId) => updateStatus(adId, 'paused');
  Future<void> resumeAd(String adId) => updateStatus(adId, 'active');

  Future<void> deleteAd(String adId) async {
    return guard('deleteAd', () async {
      await _db.table('ads').delete().eq('id', adId);
    });
  }

  // --------------------------- Media upload -----------------------

  Future<String> uploadAdMedia({
    required Uint8List bytes,
    required String extension,
  }) async {
    return guard('uploadAdMedia', () async {
      final path =
          'ads/${DateTime.now().millisecondsSinceEpoch}.${extension.toLowerCase()}';
      await _db.storageBucket('message-attachments').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      return _db.storageBucket('message-attachments').getPublicUrl(path);
    });
  }

  // ----------------------------- Create ---------------------------

  Future<void> createAd({
    required String userId,
    required String title,
    String? description,
    required String mediaUrl,
    required String mediaType,
    String? destinationUrl,
    String? callToAction,
    String adType = 'feed',
    num budget = 1,
    num? dailyBudget,
    String billingType = 'cpm',
    String? targetGender,
    int? targetAgeMin,
    int? targetAgeMax,
  }) async {
    return guard('createAd', () async {
      await _db.table('ads').insert({
        'user_id': userId,
        'title': title,
        'description': description,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'destination_url': destinationUrl,
        'call_to_action': callToAction,
        'ad_type': adType,
        'budget': budget,
        'daily_budget': dailyBudget,
        'billing_type': billingType,
        'target_gender': targetGender,
        'target_age_min': targetAgeMin,
        'target_age_max': targetAgeMax,
        'status': 'pending',
      });
    });
  }

  // ------------------------ Feed/Story injection ------------------

  Future<List<Ad>> fetchActiveAds(
      {String adType = 'feed', int limit = 5}) async {
    return guard('fetchActiveAds', () async {
      try {
        final data = await _db
            .table('ads')
            .select('*')
            .eq('status', 'active')
            .or('ad_type.eq.$adType,ad_type.eq.both')
            .order('created_at', ascending: false)
            .limit(limit);
        return (data as List)
            .map((m) => Ad.fromMap(m as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return const [];
      }
    });
  }

  // --------------------------- Tracking ---------------------------

  Future<void> trackImpression({
    required String adId,
    String? userId,
    required String placement, // feed | story
  }) async {
    return guard('trackImpression', () async {
      try {
        await _db.table('ad_impressions').insert({
          'ad_id': adId,
          'user_id': userId,
          'placement': placement,
          'device_type': 'mobile',
        });
        if (userId != null) {
          await _db.table('ad_reach').upsert(
            {'ad_id': adId, 'user_id': userId},
            onConflict: 'ad_id,user_id',
          );
        }
      } catch (_) {}
    });
  }

  Future<void> trackClick({
    required String adId,
    String? userId,
    required String placement,
  }) async {
    return guard('trackClick', () async {
      try {
        await _db.table('ad_clicks').insert({
          'ad_id': adId,
          'user_id': userId,
          'placement': placement,
          'device_type': 'mobile',
        });
      } catch (_) {}
    });
  }

  // ---------------------------- Stats -----------------------------

  /// Mirrors web's `useAdStats` daily aggregation: ALWAYS returns exactly
  /// [days] entries (today − 6 … today) in ISO `YYYY-MM-DD` format, even
  /// when a day has zero impressions/clicks.
  Future<List<AdDailyStats>> fetchDailyStats(String adId,
      {int days = 7}) async {
    return guard('fetchDailyStats', () async {
      try {
        final now = DateTime.now();
        final since = now.subtract(Duration(days: days));
        final imps = await _db
            .table('ad_impressions')
            .select('created_at')
            .eq('ad_id', adId)
            .gte('created_at', since.toIso8601String());
        final clicks = await _db
            .table('ad_clicks')
            .select('created_at')
            .eq('ad_id', adId)
            .gte('created_at', since.toIso8601String());

        String dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';

        // Pre-seed exactly `days` buckets so empty days still render (web parity).
        final Map<String, _DayCount> byDay = {};
        for (var i = days - 1; i >= 0; i--) {
          final d = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: i));
          byDay[dateKey(d)] = _DayCount();
        }
        for (final r in (imps as List)) {
          final dt = DateTime.parse(r['created_at'] as String).toLocal();
          final k = dateKey(DateTime(dt.year, dt.month, dt.day));
          byDay[k]?.impressions++;
        }
        for (final r in (clicks as List)) {
          final dt = DateTime.parse(r['created_at'] as String).toLocal();
          final k = dateKey(DateTime(dt.year, dt.month, dt.day));
          byDay[k]?.clicks++;
        }
        final keys = byDay.keys.toList()..sort();
        return keys
            .map((k) => AdDailyStats(
                  date: k,
                  impressions: byDay[k]!.impressions,
                  clicks: byDay[k]!.clicks,
                ))
            .toList();
      } catch (_) {
        return const [];
      }
    });
  }
}

class _DayCount {
  int impressions = 0;
  int clicks = 0;
}
