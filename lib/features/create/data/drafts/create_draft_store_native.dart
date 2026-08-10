import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'create_draft.dart';
import 'create_draft_store_base.dart';

class LocalCreateDraftStore implements CreateDraftStore {
  LocalCreateDraftStore._();

  static final LocalCreateDraftStore instance = LocalCreateDraftStore._();

  static const _databaseName = 'alsamos_create_drafts.db';
  static const _table = 'create_drafts';

  Database? _db;
  bool _databaseFactoryReady = false;

  Future<Database> get _database async {
    final current = _db;
    if (current != null) return current;
    _prepareDatabaseFactory();
    final path = p.join(await getDatabasesPath(), _databaseName);
    final opened = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_table (
            id TEXT PRIMARY KEY,
            schema_version INTEGER NOT NULL,
            mode TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            payload_json TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_create_drafts_updated ON $_table(updated_at DESC)',
        );
        await db.execute(
          'CREATE INDEX idx_create_drafts_mode_updated '
          'ON $_table(mode, updated_at DESC)',
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

  @override
  Future<void> save(CreateDraft draft) async {
    final db = await _database;
    await db.insert(
      _table,
      _toRow(draft),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<CreateDraft>> list({String? mode, int? limit}) async {
    if (limit != null && limit <= 0) return const <CreateDraft>[];
    final db = await _database;
    final rows = await db.query(
      _table,
      where: mode == null ? null : 'mode = ?',
      whereArgs: mode == null ? null : [mode],
      orderBy: 'updated_at DESC, id DESC',
      limit: limit,
    );
    return _safeRows(rows);
  }

  @override
  Future<CreateDraft?> load(String id) async {
    final db = await _database;
    final rows = await db.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  @override
  Future<void> delete(String id) async {
    final db = await _database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> clear({String? mode}) async {
    final db = await _database;
    await db.delete(
      _table,
      where: mode == null ? null : 'mode = ?',
      whereArgs: mode == null ? null : [mode],
    );
  }

  Map<String, Object?> _toRow(CreateDraft draft) => {
        'id': draft.id,
        'schema_version': draft.schemaVersion,
        'mode': draft.mode,
        'updated_at': draft.updatedAt.toUtc().toIso8601String(),
        'payload_json': jsonEncode(draft.payload),
      };

  List<CreateDraft> _safeRows(List<Map<String, Object?>> rows) {
    return rows.map(_fromRow).whereType<CreateDraft>().toList(growable: false);
  }

  CreateDraft? _fromRow(Map<String, Object?> row) {
    try {
      final payloadRaw = row['payload_json'] as String? ?? '{}';
      final payloadDecoded = jsonDecode(payloadRaw);
      return CreateDraft(
        id: row['id'] as String,
        schemaVersion:
            (row['schema_version'] as int?) ?? CreateDraft.currentSchemaVersion,
        mode: row['mode'] as String,
        updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
        payload: payloadDecoded is Map
            ? Map<String, dynamic>.from(payloadDecoded)
            : const {},
      );
    } catch (_) {
      return null;
    }
  }
}
