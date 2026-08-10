import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../core/data/base_repository.dart';
import '../../../core/data/supabase_data_source.dart';
import 'mini_app_model.dart';

/// Real Supabase access for `mini_apps` table — ported from web MiniAppsPage.
class MiniAppsRepository extends BaseRepository {
  const MiniAppsRepository({
    SupabaseDataSource db = const SupabaseDataSource(),
  }) : _db = db;

  final SupabaseDataSource _db;
  static const _iconsBucket = 'mini-app-icons';

  Future<List<MiniApp>> fetchApps() async {
    return guard('fetchApps', () async {
      final res = await _db
          .table('mini_apps')
          .select(
              '*, profiles(username, display_name, avatar_url, is_verified)')
          .order('created_at', ascending: false);
      return (res as List)
          .map((e) => MiniApp.fromMap(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<String> uploadIcon({
    required String userId,
    required File file,
  }) async {
    return guard('uploadIcon', () async {
      final bytes = await file.readAsBytes();
      return uploadIconBytes(
        userId: userId,
        bytes: bytes,
        ext: p.extension(file.path).replaceFirst('.', '').toLowerCase(),
      );
    });
  }

  Future<String> uploadIconBytes({
    required String userId,
    required Uint8List bytes,
    String ext = 'png',
  }) async {
    return guard('uploadIconBytes', () async {
      final safeExt = ext.isEmpty ? 'png' : ext;
      final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$safeExt';
      await _db.storageBucket(_iconsBucket).uploadBinary(
            path,
            bytes,
          );
      return _db.storageBucket(_iconsBucket).getPublicUrl(path);
    });
  }

  Future<MiniApp?> createApp({
    required String userId,
    required String name,
    required String url,
    String? description,
    String? iconUrl,
    String category = 'other',
  }) async {
    return guard('createApp', () async {
      final inserted = await _db
          .table('mini_apps')
          .insert({
            'user_id': userId,
            'name': name,
            'url': url,
            'description': description,
            'icon_url': iconUrl,
            'category': category,
          })
          .select(
              '*, profiles(username, display_name, avatar_url, is_verified)')
          .maybeSingle();
      if (inserted == null) return null;
      return MiniApp.fromMap(inserted);
    });
  }

  Future<MiniApp?> updateApp({
    required String id,
    required String name,
    required String url,
    String? description,
    String? iconUrl,
    String category = 'other',
  }) async {
    return guard('updateApp', () async {
      final updated = await _db
          .table('mini_apps')
          .update({
            'name': name,
            'url': url,
            'description': description,
            'icon_url': iconUrl,
            'category': category,
          })
          .eq('id', id)
          .select(
              '*, profiles(username, display_name, avatar_url, is_verified)')
          .maybeSingle();
      if (updated == null) return null;
      return MiniApp.fromMap(updated);
    });
  }

  Future<void> deleteApp(String id) async {
    return guard('deleteApp', () async {
      await _db.table('mini_apps').delete().eq('id', id);
    });
  }
}
