import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../core/supabase/supabase_client.dart';
import 'mini_app_model.dart';

/// Real Supabase access for `mini_apps` table — ported from web MiniAppsPage.
class MiniAppsRepository {
  static const _iconsBucket = 'mini-app-icons';

  Future<List<MiniApp>> fetchApps() async {
    final res = await supabase
        .from('mini_apps')
        .select('*, profiles(username, display_name, avatar_url, is_verified)')
        .order('created_at', ascending: false);
    return (res as List)
        .map((e) => MiniApp.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> uploadIcon({
    required String userId,
    required File file,
  }) async {
    final bytes = await file.readAsBytes();
    return uploadIconBytes(
      userId: userId,
      bytes: bytes,
      ext: p.extension(file.path).replaceFirst('.', '').toLowerCase(),
    );
  }

  Future<String> uploadIconBytes({
    required String userId,
    required Uint8List bytes,
    String ext = 'png',
  }) async {
    final safeExt = ext.isEmpty ? 'png' : ext;
    final path =
        '$userId/${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    await supabase.storage.from(_iconsBucket).uploadBinary(
      path,
      bytes,
    );
    return supabase.storage.from(_iconsBucket).getPublicUrl(path);
  }

  Future<MiniApp?> createApp({
    required String userId,
    required String name,
    required String url,
    String? description,
    String? iconUrl,
    String category = 'other',
  }) async {
    final inserted = await supabase
        .from('mini_apps')
        .insert({
          'user_id': userId,
          'name': name,
          'url': url,
          'description': description,
          'icon_url': iconUrl,
          'category': category,
        })
        .select('*, profiles(username, display_name, avatar_url, is_verified)')
        .maybeSingle();
    if (inserted == null) return null;
    return MiniApp.fromMap(inserted);
  }

  Future<MiniApp?> updateApp({
    required String id,
    required String name,
    required String url,
    String? description,
    String? iconUrl,
    String category = 'other',
  }) async {
    final updated = await supabase
        .from('mini_apps')
        .update({
          'name': name,
          'url': url,
          'description': description,
          'icon_url': iconUrl,
          'category': category,
        })
        .eq('id', id)
        .select('*, profiles(username, display_name, avatar_url, is_verified)')
        .maybeSingle();
    if (updated == null) return null;
    return MiniApp.fromMap(updated);
  }

  Future<void> deleteApp(String id) async {
    await supabase.from('mini_apps').delete().eq('id', id);
  }
}
