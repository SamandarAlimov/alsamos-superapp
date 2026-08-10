import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/web_search_result.dart';

class SearchRepository {
  final SupabaseClient _supabase;

  SearchRepository({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  /// Call global web search Edge Function
  Future<WebSearchResponse> globalSearch({
    required String query,
    int page = 1,
    String safeSearch = 'moderate',
    String? language,
    String? region,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'global-search',
        body: {
          'query': query,
          'page': page,
          'safeSearch': safeSearch,
          'language': language ?? 'uz',
          'region': region ?? 'uz',
        },
      );

      if (response.status != 200) {
        final error = response.data?['error'] ?? 'Search failed';
        throw Exception(error);
      }

      return WebSearchResponse.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Failed to perform search: $e');
    }
  }

  /// Get user's search history
  Future<List<String>> getSearchHistory({int limit = 10}) async {
    try {
      final response = await _supabase
          .from('search_history')
          .select('query')
          .order('created_at', ascending: false)
          .limit(limit);

      return (response as List)
          .map((r) => r['query'] as String)
          .toSet() // Remove duplicates
          .toList();
    } catch (e) {
      // If table doesn't exist yet, return empty list
      print('Warning: search_history table not accessible: $e');
      return [];
    }
  }

  /// Clear user's search history
  Future<void> clearSearchHistory() async {
    try {
      await _supabase.from('search_history').delete().neq('id', '00000000-0000-0000-0000-000000000000');
    } catch (e) {
      // If table doesn't exist, ignore
      print('Warning: Could not clear search_history: $e');
    }
  }

  /// Get user's search preferences FROM LOCAL STORAGE
  /// This completely decouples Global search from database schema
  /// NO MORE 42703 ERRORS - preferences are device-local, UX settings
  Future<Map<String, String>> getSearchPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'safeSearch': prefs.getString('search_safe_mode') ?? 'moderate',
        'region': prefs.getString('search_region') ?? 'uz',
        'language': prefs.getString('search_language') ?? 'uz',
      };
    } catch (e) {
      // If SharedPreferences fails, return defaults
      print('Warning: Could not load local search preferences: $e');
      return {
        'safeSearch': 'moderate',
        'region': 'uz',
        'language': 'uz',
      };
    }
  }

  /// Update user's search preferences TO LOCAL STORAGE
  /// No database dependency = no schema errors
  Future<void> updateSearchPreferences({
    String? safeSearch,
    String? region,
    String? language,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (safeSearch != null) await prefs.setString('search_safe_mode', safeSearch);
      if (region != null) await prefs.setString('search_region', region);
      if (language != null) await prefs.setString('search_language', language);
    } catch (e) {
      // If SharedPreferences fails, silently ignore
      print('Warning: Could not save local search preferences: $e');
    }
  }
}
