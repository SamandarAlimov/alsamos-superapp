// Location Queue Service - Blink-style offline GPS tracking with background sync
// Stores location updates locally when offline and syncs when connection returns
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracking mode for battery optimization
enum TrackingMode {
  /// High accuracy, frequent updates (every 2s), best for navigation
  highAccuracy,

  /// Balanced mode (every 10s), good for general tracking
  balanced,

  /// Battery saver mode (every 30s), minimal battery drain
  batterySaver,

  /// Custom interval
  custom,
}

/// Location point queued for upload
class QueuedLocation {
  final int? id; // local SQLite ID
  final String userId;
  final double latitude;
  final double longitude;
  final double accuracy;
  final double? altitude;
  final double? heading;
  final double? speed;
  final DateTime recordedAt;
  final DateTime queuedAt;
  final int retryCount;
  final bool synced;

  const QueuedLocation({
    this.id,
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.altitude,
    this.heading,
    this.speed,
    required this.recordedAt,
    required this.queuedAt,
    this.retryCount = 0,
    this.synced = false,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'altitude': altitude,
        'heading': heading,
        'speed': speed,
        'recorded_at': recordedAt.toIso8601String(),
        'queued_at': queuedAt.toIso8601String(),
        'retry_count': retryCount,
        'synced': synced ? 1 : 0,
      };

  factory QueuedLocation.fromMap(Map<String, dynamic> map) => QueuedLocation(
        id: map['id'] as int?,
        userId: map['user_id'] as String,
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        accuracy: (map['accuracy'] as num).toDouble(),
        altitude: (map['altitude'] as num?)?.toDouble(),
        heading: (map['heading'] as num?)?.toDouble(),
        speed: (map['speed'] as num?)?.toDouble(),
        recordedAt: DateTime.parse(map['recorded_at'] as String),
        queuedAt: DateTime.parse(map['queued_at'] as String),
        retryCount: map['retry_count'] as int? ?? 0,
        synced: (map['synced'] as int?) == 1,
      );

  QueuedLocation copyWith({
    int? id,
    int? retryCount,
    bool? synced,
  }) =>
      QueuedLocation(
        id: id ?? this.id,
        userId: userId,
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        altitude: altitude,
        heading: heading,
        speed: speed,
        recordedAt: recordedAt,
        queuedAt: queuedAt,
        retryCount: retryCount ?? this.retryCount,
        synced: synced ?? this.synced,
      );
}

/// Statistics about the location queue
class QueueStats {
  final int totalQueued;
  final int unsynced;
  final int synced;
  final int failed;
  final DateTime? oldestUnsyncedAt;
  final DateTime? newestQueuedAt;
  final double unsyncedSizeKB;

  const QueueStats({
    this.totalQueued = 0,
    this.unsynced = 0,
    this.synced = 0,
    this.failed = 0,
    this.oldestUnsyncedAt,
    this.newestQueuedAt,
    this.unsyncedSizeKB = 0,
  });
}

/// Service for managing offline location queue with background sync
class LocationQueueService {
  LocationQueueService._();
  static final LocationQueueService instance = LocationQueueService._();

  Database? _db;
  Timer? _syncTimer;
  Timer? _cleanupTimer;

  // Configuration
  TrackingMode _trackingMode = TrackingMode.balanced;
  Duration _customInterval = const Duration(seconds: 10);
  int _maxQueueSize = 10000; // Max points to keep in local DB
  int _batchSize = 50; // Upload batch size
  Duration _syncInterval = const Duration(minutes: 1);
  final Duration _cleanupInterval = const Duration(hours: 1);
  final int _maxRetries = 5;
  Duration _retentionPeriod = const Duration(days: 90);

  // State
  bool _isInitialized = false;
  bool _isSyncing = false;
  final _statsController = StreamController<QueueStats>.broadcast();

  Stream<QueueStats> get statsStream => _statsController.stream;

  /// Initialize the queue service and start background tasks
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final dbPath = await getDatabasesPath();
      final dbFile = path.join(dbPath, 'location_queue.db');

      _db = await openDatabase(
        dbFile,
        version: 1,
        onCreate: _createDatabase,
        onUpgrade: _upgradeDatabase,
      );

      _isInitialized = true;

      // Start background sync and cleanup
      _startBackgroundTasks();

      debugPrint('[LocationQueueService] Initialized successfully');
    } catch (e, stack) {
      debugPrint('[LocationQueueService] Initialization failed: $e\n$stack');
      rethrow;
    }
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE location_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL NOT NULL,
        altitude REAL,
        heading REAL,
        speed REAL,
        recorded_at TEXT NOT NULL,
        queued_at TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        synced INTEGER DEFAULT 0,
        last_error TEXT
      )
    ''');

    // Indexes for efficient queries
    await db.execute(
        'CREATE INDEX idx_queue_synced ON location_queue(synced, queued_at)');
    await db.execute(
        'CREATE INDEX idx_queue_user ON location_queue(user_id, recorded_at DESC)');
    await db.execute(
        'CREATE INDEX idx_queue_retry ON location_queue(retry_count, synced)');
  }

  Future<void> _upgradeDatabase(
      Database db, int oldVersion, int newVersion) async {
    // Handle future schema migrations
    if (oldVersion < 2) {
      // Add columns for future versions
    }
  }

  void _startBackgroundTasks() {
    // Periodic sync
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) => syncQueue());

    // Periodic cleanup of old synced records
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => cleanupOldRecords());

    // Initial sync
    syncQueue();
  }

  /// Queue a location update for later sync
  Future<void> queueLocation(Position position) async {
    if (!_isInitialized) await initialize();

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final location = QueuedLocation(
        userId: user.id,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        heading: position.heading,
        speed: position.speed,
        recordedAt: position.timestamp,
        queuedAt: DateTime.now(),
      );

      await _db!.insert('location_queue', location.toMap());

      // Check queue size and trim if needed
      await _trimQueueIfNeeded();

      // Update stats
      _broadcastStats();

      debugPrint(
          '[LocationQueueService] Queued location: ${position.latitude},${position.longitude}');
    } catch (e, stack) {
      debugPrint('[LocationQueueService] Failed to queue location: $e\n$stack');
    }
  }

  /// Sync queued locations to Supabase
  Future<bool> syncQueue() async {
    if (!_isInitialized) return false;
    if (_isSyncing) return false;

    _isSyncing = true;

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        _isSyncing = false;
        return false;
      }

      // Fetch unsynced locations
      final unsynced = await _db!.query(
        'location_queue',
        where: 'synced = ? AND retry_count < ?',
        whereArgs: [0, _maxRetries],
        orderBy: 'queued_at ASC',
        limit: _batchSize,
      );

      if (unsynced.isEmpty) {
        _isSyncing = false;
        _broadcastStats();
        return true;
      }

      final locations =
          unsynced.map((m) => QueuedLocation.fromMap(m)).toList();

      debugPrint(
          '[LocationQueueService] Syncing ${locations.length} locations...');

      // Batch insert to Supabase
      final records = locations.map((loc) => {
            'user_id': loc.userId,
            'latitude': loc.latitude,
            'longitude': loc.longitude,
            'accuracy': loc.accuracy,
            'recorded_at': loc.recordedAt.toIso8601String(),
          });

      try {
        await Supabase.instance.client
            .from('location_history')
            .insert(records.toList());

        // Mark as synced in local DB
        final batch = _db!.batch();
        for (final loc in locations) {
          batch.update(
            'location_queue',
            {'synced': 1},
            where: 'id = ?',
            whereArgs: [loc.id],
          );
        }
        await batch.commit(noResult: true);

        debugPrint(
            '[LocationQueueService] Successfully synced ${locations.length} locations');
        _broadcastStats();
        return true;
      } catch (e) {
        // Update retry count on failure
        debugPrint('[LocationQueueService] Sync failed: $e');
        final batch = _db!.batch();
        for (final loc in locations) {
          batch.update(
            'location_queue',
            {
              'retry_count': loc.retryCount + 1,
              'last_error': e.toString().substring(0, 255),
            },
            where: 'id = ?',
            whereArgs: [loc.id],
          );
        }
        await batch.commit(noResult: true);

        _broadcastStats();
        return false;
      }
    } catch (e, stack) {
      debugPrint('[LocationQueueService] Sync error: $e\n$stack');
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  /// Clean up old synced records beyond retention period
  Future<void> cleanupOldRecords() async {
    if (!_isInitialized) return;

    try {
      final cutoff = DateTime.now().subtract(_retentionPeriod);
      final deleted = await _db!.delete(
        'location_queue',
        where: 'synced = 1 AND queued_at < ?',
        whereArgs: [cutoff.toIso8601String()],
      );

      if (deleted > 0) {
        debugPrint('[LocationQueueService] Cleaned up $deleted old records');
        _broadcastStats();
      }
    } catch (e) {
      debugPrint('[LocationQueueService] Cleanup error: $e');
    }
  }

  /// Trim queue if it exceeds max size (keep most recent)
  Future<void> _trimQueueIfNeeded() async {
    try {
      final count = Sqflite.firstIntValue(
          await _db!.rawQuery('SELECT COUNT(*) FROM location_queue'));
      if (count != null && count > _maxQueueSize) {
        final excess = count - _maxQueueSize;
        await _db!.rawDelete('''
          DELETE FROM location_queue 
          WHERE id IN (
            SELECT id FROM location_queue 
            WHERE synced = 1 
            ORDER BY queued_at ASC 
            LIMIT ?
          )
        ''', [excess]);
        debugPrint('[LocationQueueService] Trimmed $excess old records');
      }
    } catch (e) {
      debugPrint('[LocationQueueService] Trim error: $e');
    }
  }

  /// Get current queue statistics
  Future<QueueStats> getStats() async {
    if (!_isInitialized) return const QueueStats();

    try {
      final total = Sqflite.firstIntValue(
              await _db!.rawQuery('SELECT COUNT(*) FROM location_queue')) ??
          0;

      final unsynced = Sqflite.firstIntValue(await _db!
              .rawQuery('SELECT COUNT(*) FROM location_queue WHERE synced = 0')) ??
          0;

      final failed = Sqflite.firstIntValue(await _db!.rawQuery(
              'SELECT COUNT(*) FROM location_queue WHERE retry_count >= ?',
              [_maxRetries])) ??
          0;

      final oldestResult = await _db!.rawQuery(
          'SELECT queued_at FROM location_queue WHERE synced = 0 ORDER BY queued_at ASC LIMIT 1');
      final newestResult = await _db!.rawQuery(
          'SELECT queued_at FROM location_queue ORDER BY queued_at DESC LIMIT 1');

      final oldest = oldestResult.isNotEmpty
          ? DateTime.tryParse(oldestResult.first['queued_at'] as String)
          : null;
      final newest = newestResult.isNotEmpty
          ? DateTime.tryParse(newestResult.first['queued_at'] as String)
          : null;

      // Estimate size (rough calculation)
      final sizeKB = (unsynced * 150) / 1024; // ~150 bytes per record

      return QueueStats(
        totalQueued: total,
        unsynced: unsynced,
        synced: total - unsynced,
        failed: failed,
        oldestUnsyncedAt: oldest,
        newestQueuedAt: newest,
        unsyncedSizeKB: sizeKB,
      );
    } catch (e) {
      debugPrint('[LocationQueueService] Stats error: $e');
      return const QueueStats();
    }
  }

  void _broadcastStats() {
    getStats().then((stats) {
      if (!_statsController.isClosed) {
        _statsController.add(stats);
      }
    });
  }

  /// Get unsynced locations for manual inspection
  Future<List<QueuedLocation>> getUnsyncedLocations({int limit = 100}) async {
    if (!_isInitialized) return [];

    try {
      final results = await _db!.query(
        'location_queue',
        where: 'synced = 0',
        orderBy: 'queued_at DESC',
        limit: limit,
      );

      return results.map((m) => QueuedLocation.fromMap(m)).toList();
    } catch (e) {
      debugPrint('[LocationQueueService] Get unsynced error: $e');
      return [];
    }
  }

  /// Clear all failed records (retry count exceeded)
  Future<void> clearFailedRecords() async {
    if (!_isInitialized) return;

    try {
      final deleted = await _db!.delete(
        'location_queue',
        where: 'retry_count >= ?',
        whereArgs: [_maxRetries],
      );

      if (deleted > 0) {
        debugPrint('[LocationQueueService] Cleared $deleted failed records');
        _broadcastStats();
      }
    } catch (e) {
      debugPrint('[LocationQueueService] Clear failed error: $e');
    }
  }

  /// Reset retry count for failed records (retry them)
  Future<void> retryFailedRecords() async {
    if (!_isInitialized) return;

    try {
      final updated = await _db!.update(
        'location_queue',
        {'retry_count': 0, 'last_error': null},
        where: 'retry_count >= ? AND synced = 0',
        whereArgs: [_maxRetries],
      );

      if (updated > 0) {
        debugPrint('[LocationQueueService] Reset $updated failed records');
        _broadcastStats();
        // Trigger immediate sync
        syncQueue();
      }
    } catch (e) {
      debugPrint('[LocationQueueService] Retry failed error: $e');
    }
  }

  /// Clear all records (use with caution!)
  Future<void> clearAll() async {
    if (!_isInitialized) return;

    try {
      await _db!.delete('location_queue');
      debugPrint('[LocationQueueService] Cleared all records');
      _broadcastStats();
    } catch (e) {
      debugPrint('[LocationQueueService] Clear all error: $e');
    }
  }

  // Configuration setters
  void setTrackingMode(TrackingMode mode) {
    _trackingMode = mode;
  }

  void setCustomInterval(Duration interval) {
    _customInterval = interval;
  }

  void setSyncInterval(Duration interval) {
    _syncInterval = interval;
    _startBackgroundTasks(); // Restart with new interval
  }

  void setMaxQueueSize(int size) {
    _maxQueueSize = size;
  }

  void setBatchSize(int size) {
    _batchSize = size;
  }

  void setRetentionPeriod(Duration period) {
    _retentionPeriod = period;
  }

  // Getters
  TrackingMode get trackingMode => _trackingMode;
  Duration get customInterval => _customInterval;
  Duration get syncInterval => _syncInterval;
  bool get isInitialized => _isInitialized;
  bool get isSyncing => _isSyncing;

  /// Get tracking interval based on mode
  Duration getTrackingInterval() {
    switch (_trackingMode) {
      case TrackingMode.highAccuracy:
        return const Duration(seconds: 2);
      case TrackingMode.balanced:
        return const Duration(seconds: 10);
      case TrackingMode.batterySaver:
        return const Duration(seconds: 30);
      case TrackingMode.custom:
        return _customInterval;
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    _syncTimer?.cancel();
    _cleanupTimer?.cancel();
    await _statsController.close();
    await _db?.close();
    _isInitialized = false;
  }
}
