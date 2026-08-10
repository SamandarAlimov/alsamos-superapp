import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/content_item.dart';

class ContentPostsCache {
  static const _databaseName = 'alsamos_content.db';
  static const _maxCachedPosts = 1000;

  Database? _db;
  bool _databaseFactoryReady = false;

  Future<Database> get _database async {
    final existing = _db;
    if (existing != null) return existing;
    _prepareDatabaseFactory();
    final path = p.join(await getDatabasesPath(), _databaseName);
    final opened = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE content_posts_cache (
            id TEXT PRIMARY KEY,
            payload_json TEXT NOT NULL,
            visibility TEXT,
            content_type TEXT,
            location_lat REAL,
            location_lng REAL,
            created_at TEXT,
            updated_at TEXT,
            cached_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_content_posts_cache_created ON content_posts_cache(created_at DESC)',
        );
        await db.execute(
          'CREATE INDEX idx_content_posts_cache_location ON content_posts_cache(location_lat, location_lng)',
        );
      },
    );
    _db = opened;
    return opened;
  }

  void _prepareDatabaseFactory() {
    if (_databaseFactoryReady) return;
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _databaseFactoryReady = true;
  }

  Future<List<ContentItem>> loadFeed({int limit = 20, int offset = 0}) async {
    final db = await _database;
    final rows = await db.query(
      'content_posts_cache',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> saveFeed(List<ContentItem> posts) async {
    if (posts.isEmpty) return;
    final db = await _database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();
    for (final post in posts) {
      batch.insert(
        'content_posts_cache',
        _toRow(post, now),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    await _trim(db);
  }

  Future<void> savePost(ContentItem post) async {
    final db = await _database;
    await db.insert(
      'content_posts_cache',
      _toRow(post, DateTime.now().toIso8601String()),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _trim(db);
  }

  Future<void> removePost(String id) async {
    final db = await _database;
    await db.delete('content_posts_cache', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _trim(Database db) async {
    final rows = await db.query(
      'content_posts_cache',
      columns: ['id'],
      orderBy: 'created_at DESC',
      limit: -1,
      offset: _maxCachedPosts,
    );
    if (rows.isEmpty) return;
    final ids = rows.map((e) => e['id']).whereType<String>().toList();
    await db.delete(
      'content_posts_cache',
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  Map<String, Object?> _toRow(ContentItem post, String cachedAt) {
    return {
      'id': post.id,
      'payload_json':
          jsonEncode(post.raw.isNotEmpty ? post.raw : post.toPostInsertMap()),
      'visibility': post.visibility,
      'content_type': post.type.name,
      'location_lat': post.location?.latitude,
      'location_lng': post.location?.longitude,
      'created_at': post.createdAt.toIso8601String(),
      'updated_at': post.updatedAt?.toIso8601String(),
      'cached_at': cachedAt,
    };
  }

  ContentItem _fromRow(Map<String, Object?> row) {
    final payload =
        jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
    return ContentItem.fromPostMap(payload);
  }
}
