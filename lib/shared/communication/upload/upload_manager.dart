import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';

final uploadManagerProvider =
    StateNotifierProvider<UploadManager, UploadManagerState>(
        (ref) => UploadManager());

enum UploadStatus { queued, uploading, paused, completed, failed }

class UploadTask {
  final String id;
  final String localPath;
  final String remotePath;
  final String bucket;
  final String contentType;
  final UploadStatus status;
  final double progress;
  final String? signedUrl;
  final String? error;
  final int retryCount;

  const UploadTask({
    required this.id,
    required this.localPath,
    required this.remotePath,
    required this.bucket,
    required this.contentType,
    this.status = UploadStatus.queued,
    this.progress = 0.0,
    this.signedUrl,
    this.error,
    this.retryCount = 0,
  });

  UploadTask copyWith({
    UploadStatus? status,
    double? progress,
    String? signedUrl,
    String? error,
    int? retryCount,
  }) =>
      UploadTask(
        id: id,
        localPath: localPath,
        remotePath: remotePath,
        bucket: bucket,
        contentType: contentType,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        signedUrl: signedUrl ?? this.signedUrl,
        error: error ?? this.error,
        retryCount: retryCount ?? this.retryCount,
      );

  bool get isActive =>
      status == UploadStatus.uploading || status == UploadStatus.queued;
}

class UploadManagerState {
  final Map<String, UploadTask> tasks;
  final int concurrentLimit;

  const UploadManagerState({
    this.tasks = const {},
    this.concurrentLimit = 3,
  });

  List<UploadTask> get activeTasks =>
      tasks.values.where((t) => t.isActive).toList();

  List<UploadTask> get completedTasks =>
      tasks.values.where((t) => t.status == UploadStatus.completed).toList();

  List<UploadTask> get failedTasks =>
      tasks.values.where((t) => t.status == UploadStatus.failed).toList();

  double get totalProgress {
    if (tasks.isEmpty) return 0;
    final total = tasks.values.fold<double>(0, (s, t) => s + t.progress);
    return total / tasks.length;
  }

  UploadManagerState copyWith({
    Map<String, UploadTask>? tasks,
    int? concurrentLimit,
  }) =>
      UploadManagerState(
        tasks: tasks ?? this.tasks,
        concurrentLimit: concurrentLimit ?? this.concurrentLimit,
      );
}

class UploadManager extends StateNotifier<UploadManagerState> {
  UploadManager() : super(const UploadManagerState());

  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 5);
  final Map<String, Completer<String?>> _completers = {};
  int _activeCount = 0;

  Future<String?> enqueue({
    required String localPath,
    required String remotePath,
    required String bucket,
    required String contentType,
    String? taskId,
  }) async {
    final id = taskId ?? '${DateTime.now().microsecondsSinceEpoch}_${localPath.hashCode}';
    final task = UploadTask(
      id: id,
      localPath: localPath,
      remotePath: remotePath,
      bucket: bucket,
      contentType: contentType,
    );

    final tasks = Map<String, UploadTask>.from(state.tasks);
    tasks[id] = task;
    state = state.copyWith(tasks: tasks);

    final completer = Completer<String?>();
    _completers[id] = completer;

    _processQueue();
    return completer.future;
  }

  void cancel(String taskId) {
    final tasks = Map<String, UploadTask>.from(state.tasks);
    tasks.remove(taskId);
    state = state.copyWith(tasks: tasks);
    _completers[taskId]?.complete(null);
    _completers.remove(taskId);
  }

  void cancelAll() {
    for (final id in state.tasks.keys.toList()) {
      cancel(id);
    }
  }

  Future<void> retry(String taskId) async {
    final task = state.tasks[taskId];
    if (task == null || task.status != UploadStatus.failed) return;

    final tasks = Map<String, UploadTask>.from(state.tasks);
    tasks[taskId] = task.copyWith(
      status: UploadStatus.queued,
      progress: 0,
      error: null,
    );
    state = state.copyWith(tasks: tasks);

    if (!_completers.containsKey(taskId)) {
      _completers[taskId] = Completer<String?>();
    }
    _processQueue();
  }

  void clearCompleted() {
    final tasks = Map<String, UploadTask>.from(state.tasks);
    tasks.removeWhere((_, t) => t.status == UploadStatus.completed);
    state = state.copyWith(tasks: tasks);
  }

  void _processQueue() {
    if (_activeCount >= state.concurrentLimit) return;

    final queued = state.tasks.values
        .where((t) => t.status == UploadStatus.queued)
        .toList();

    for (final task in queued) {
      if (_activeCount >= state.concurrentLimit) break;
      _activeCount++;
      _uploadTask(task);
    }
  }

  Future<void> _uploadTask(UploadTask task) async {
    _updateTask(task.id, task.copyWith(status: UploadStatus.uploading, progress: 0.1));

    try {
      if (kIsWeb) {
        throw UnsupportedError('File upload from web not supported in this path');
      }

      final file = File(task.localPath);
      if (!await file.exists()) {
        throw StateError('File not found: ${task.localPath}');
      }

      await supabase.storage.from(task.bucket).upload(
        task.remotePath,
        file,
        fileOptions: FileOptions(contentType: task.contentType, upsert: false),
      );

      _updateTask(task.id, task.copyWith(status: UploadStatus.uploading, progress: 0.9));

      final signedUrl = await supabase.storage
          .from(task.bucket)
          .createSignedUrl(task.remotePath, 60 * 60);

      _updateTask(task.id, task.copyWith(
        status: UploadStatus.completed,
        progress: 1.0,
        signedUrl: signedUrl,
      ));

      _completers[task.id]?.complete(signedUrl);
      _completers.remove(task.id);
    } catch (e) {
      debugPrint('[UploadManager] upload failed (${task.id}): $e');

      if (task.retryCount < _maxRetries) {
        _updateTask(task.id, task.copyWith(
          status: UploadStatus.queued,
          retryCount: task.retryCount + 1,
          progress: 0,
        ));
        await Future.delayed(_retryDelay);
        if (mounted) _processQueue();
        return;
      }

      _updateTask(task.id, task.copyWith(
        status: UploadStatus.failed,
        error: e.toString(),
      ));
      _completers[task.id]?.complete(null);
      _completers.remove(task.id);
    } finally {
      _activeCount--;
      if (mounted) _processQueue();
    }
  }

  void _updateTask(String id, UploadTask task) {
    if (!mounted) return;
    final tasks = Map<String, UploadTask>.from(state.tasks);
    tasks[id] = task;
    state = state.copyWith(tasks: tasks);
  }
}
