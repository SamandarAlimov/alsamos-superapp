// Mini Apps feed repozitoriysi.
//
// Web (`src/features/miniapps/api.ts`) bilan bir xil RPC'larni chaqiradi:
// filtr/sort/ranking klientda takrorlanmaydi — hammasi `mini_apps_feed` ichida.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mini_app_feed_item.dart';

class MiniAppsFeedRepository {
  MiniAppsFeedRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const int pageSize = 24;

  /// Proksi uchun API bazasi (mini-app-proxy edge funksiyasi).
  String get apiBase => _client.supabaseUrl.replaceAll(RegExp(r'/+$'), '');

  static String get platformName {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'desktop';
  }

  Future<MiniAppFeedPage> fetchFeed({
    String section = 'all',
    String? category,
    String? appType,
    String sort = 'recommended',
    bool verifiedOnly = false,
    String? priceModel,
    String? locale,
    String? query,
    int limit = pageSize,
    int offset = 0,
  }) async {
    final normalizedQuery = (query ?? '').trim();

    final response = await _client.rpc(
      'mini_apps_feed',
      params: <String, dynamic>{
        'p_section': section,
        'p_category': (category == null || category == 'all') ? null : category,
        'p_app_type': (appType == null || appType == 'all') ? null : appType,
        'p_sort': sort,
        'p_verified_only': verifiedOnly,
        'p_price_model': priceModel,
        'p_locale': locale,
        'p_query': normalizedQuery.isEmpty ? null : normalizedQuery,
        'p_limit': limit,
        'p_offset': offset,
      },
    );

    final rows = (response as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
    final items = rows.map(MiniAppFeedItem.fromRow).toList();
    final total = items.isEmpty ? 0 : items.first.totalCount;

    return MiniAppFeedPage(
      items: items,
      total: total,
      hasMore: offset + items.length < total,
    );
  }

  Future<List<MiniAppCategoryItem>> fetchCategories({String locale = 'uz'}) async {
    final rows = await _client
        .from('mini_app_categories')
        .select('id, sort_order, icon, labels')
        .eq('is_active', true)
        .order('sort_order');

    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map((row) => MiniAppCategoryItem.fromRow(row, locale))
        .toList();
  }

  /// Telemetriya UX ni bloklamasligi kerak — xatolik yuz bersa jimgina o'tadi.
  Future<void> trackEvent(
    String appId,
    String event, {
    int? durationMs,
    String? errorCode,
    String? sessionId,
  }) async {
    try {
      await _client.rpc(
        'mini_app_track_event',
        params: <String, dynamic>{
          'p_app_id': appId,
          'p_event': event,
          'p_platform': platformName,
          'p_duration_ms': durationMs,
          'p_error_code': errorCode,
          'p_session_id': sessionId,
        },
      );
    } catch (_) {
      // e'tiborsiz qoldiramiz
    }
  }

  Future<void> rate(String appId, int rating, {String? comment}) async {
    await _client.rpc(
      'mini_app_rate',
      params: <String, dynamic>{
        'p_app_id': appId,
        'p_rating': rating,
        'p_comment': comment,
      },
    );
  }

  Future<void> setInstalled(String appId, bool installed, {bool pinned = false}) async {
    await _client.rpc(
      'mini_app_set_install',
      params: <String, dynamic>{
        'p_app_id': appId,
        'p_installed': installed,
        'p_pinned': pinned,
      },
    );
  }

  Future<void> report(String appId, String reason, {String? details}) async {
    await _client.rpc(
      'mini_app_report',
      params: <String, dynamic>{
        'p_app_id': appId,
        'p_reason': reason,
        'p_details': details,
      },
    );
  }
}
