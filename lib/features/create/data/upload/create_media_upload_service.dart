import 'dart:async';

import '../../../../core/data/base_repository.dart';
import '../../../../core/data/supabase_data_source.dart';
import 'create_media_upload_manifest.dart';
import 'create_media_upload_progress.dart';
import 'create_media_upload_storage.dart';

typedef CreateMediaUploadProgressCallback = void Function(
  CreateMediaUploadProgress progress,
);

typedef CreateMediaUploadExecutor = Future<String> Function({
  required String bucket,
  required String storagePath,
  required CreateMediaUploadItem item,
  required Duration timeout,
});

class CreateMediaUploadCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

class CreateMediaUploadService extends BaseRepository {
  CreateMediaUploadService({
    SupabaseDataSource? dataSource,
    CreateMediaUploadExecutor? uploadExecutor,
    DateTime Function()? now,
  })  : _dataSource = dataSource ?? const SupabaseDataSource(),
        _uploadExecutor = uploadExecutor,
        _now = now ?? DateTime.now;

  final SupabaseDataSource _dataSource;
  final CreateMediaUploadExecutor? _uploadExecutor;
  final DateTime Function() _now;

  Future<CreateMediaUploadManifest> uploadManifest(
    CreateMediaUploadManifest manifest, {
    CreateMediaUploadProgressCallback? onProgress,
    CreateMediaUploadCancelToken? cancelToken,
  }) {
    return guard('uploadCreateMediaManifest', () async {
      var items = List<CreateMediaUploadItem>.of(manifest.items);
      final total = items.length;

      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        if (item.isUploaded) {
          onProgress?.call(
            CreateMediaUploadProgress(
              itemId: item.id,
              itemName: item.name,
              done: _completedCount(items),
              total: total,
              status: CreateMediaUploadProgressStatus.skipped,
              publicUrl: item.publicUrl,
            ),
          );
          continue;
        }

        if (cancelToken?.isCancelled ?? false) {
          onProgress?.call(
            CreateMediaUploadProgress(
              itemId: item.id,
              itemName: item.name,
              done: _completedCount(items),
              total: total,
              status: CreateMediaUploadProgressStatus.cancelled,
            ),
          );
          break;
        }

        final storagePath = item.storagePath ??
            _buildStoragePath(
              userId: manifest.userId,
              item: item,
              ordinal: index,
            );
        items[index] = item.copyWith(
          storagePath: storagePath,
          status: CreateMediaUploadItemStatus.uploading,
          clearError: true,
        );
        onProgress?.call(
          CreateMediaUploadProgress(
            itemId: item.id,
            itemName: item.name,
            done: _completedCount(items),
            total: total,
            status: CreateMediaUploadProgressStatus.started,
          ),
        );

        try {
          final publicUrl = await _upload(
            bucket: manifest.bucket,
            storagePath: storagePath,
            item: item,
            timeout: manifest.timeout,
          );
          items[index] = items[index].copyWith(
            publicUrl: publicUrl,
            status: CreateMediaUploadItemStatus.uploaded,
            clearError: true,
          );
          onProgress?.call(
            CreateMediaUploadProgress(
              itemId: item.id,
              itemName: item.name,
              done: _completedCount(items),
              total: total,
              status: CreateMediaUploadProgressStatus.completed,
              publicUrl: publicUrl,
            ),
          );
        } catch (error) {
          items[index] = items[index].copyWith(
            status: CreateMediaUploadItemStatus.failed,
            errorMessage: error.toString(),
          );
          onProgress?.call(
            CreateMediaUploadProgress(
              itemId: item.id,
              itemName: item.name,
              done: _completedCount(items),
              total: total,
              status: CreateMediaUploadProgressStatus.failed,
              errorMessage: error.toString(),
            ),
          );
        }
      }

      return manifest.copyWith(items: items);
    });
  }

  Future<String> _upload({
    required String bucket,
    required String storagePath,
    required CreateMediaUploadItem item,
    required Duration timeout,
  }) async {
    final injected = _uploadExecutor;
    if (injected != null) {
      return injected(
        bucket: bucket,
        storagePath: storagePath,
        item: item,
        timeout: timeout,
      );
    }

    final storage = _dataSource.storageBucket(bucket);
    await uploadCreateMediaItemToStorage(
      storage: storage,
      storagePath: storagePath,
      item: item,
      timeout: timeout,
    );
    return storage.getPublicUrl(storagePath);
  }

  String _buildStoragePath({
    required String userId,
    required CreateMediaUploadItem item,
    required int ordinal,
  }) {
    final prefix = _sanitizeSegment(item.storagePrefix);
    final ext = _sanitizeExtension(item.extension);
    final stamp = _now().millisecondsSinceEpoch;
    return '$userId/$prefix-$stamp-$ordinal.$ext';
  }

  int _completedCount(List<CreateMediaUploadItem> items) {
    return items
        .where((item) => item.status == CreateMediaUploadItemStatus.uploaded)
        .length;
  }

  String _sanitizeSegment(String value) {
    final clean = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
    return clean.isEmpty ? 'post' : clean;
  }

  String _sanitizeExtension(String value) {
    final clean = value.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '').toLowerCase();
    return clean.isEmpty ? 'bin' : clean;
  }
}
