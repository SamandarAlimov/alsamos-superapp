import 'dart:async';
import 'dart:typed_data';

import 'package:alsamos_flutter/features/create/data/upload/create_media_upload_manifest.dart';
import 'package:alsamos_flutter/features/create/data/upload/create_media_upload_progress.dart';
import 'package:alsamos_flutter/features/create/data/upload/create_media_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CreateMediaUploadManifest manifestWith(List<CreateMediaUploadItem> items) {
    return CreateMediaUploadManifest(
      userId: 'user-1',
      items: List.unmodifiable(items),
    );
  }

  test('uploads bytes to message attachments and emits progress', () async {
    final calls = <String>[];
    final progress = <CreateMediaUploadProgressStatus>[];
    final service = CreateMediaUploadService(
      now: () => DateTime.fromMillisecondsSinceEpoch(123),
      uploadExecutor: ({
        required bucket,
        required storagePath,
        required item,
        required timeout,
      }) async {
        calls.add('$bucket|$storagePath|${item.name}|${timeout.inSeconds}');
        expect(await item.readBytes(), Uint8List.fromList([1, 2, 3]));
        return 'https://example.test/storage/v1/object/public/$bucket/$storagePath';
      },
    );

    final result = await service.uploadManifest(
      manifestWith([
        CreateMediaUploadItem.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          id: 'media-1',
          name: 'photo.JPG',
        ),
      ]),
      onProgress: (event) => progress.add(event.status),
    );

    expect(result.isComplete, isTrue);
    expect(
        result.uploadedUrls.single, contains('/message-attachments/user-1/'));
    expect(
      calls.single,
      'message-attachments|user-1/post-123-0.jpg|photo.JPG|60',
    );
    expect(progress, [
      CreateMediaUploadProgressStatus.started,
      CreateMediaUploadProgressStatus.completed,
    ]);
  });

  test('manifest owns an immutable snapshot of its items', () {
    final source = <CreateMediaUploadItem>[
      CreateMediaUploadItem.fromBytes(
        Uint8List.fromList([1]),
        id: 'one',
        name: 'one.png',
      ),
    ];

    final manifest = manifestWith(source);
    source.clear();

    expect(manifest.items, hasLength(1));
    expect(() => manifest.items.clear(), throwsUnsupportedError);
  });

  test('retry preserves completed urls and uploads only failed items',
      () async {
    final uploaded = CreateMediaUploadItem.fromBytes(
      Uint8List.fromList([1]),
      id: 'done',
      name: 'done.png',
    ).copyWith(
      status: CreateMediaUploadItemStatus.uploaded,
      storagePath: 'user-1/post-1-0.png',
      publicUrl: 'https://example.test/done.png',
    );
    final failed = CreateMediaUploadItem.fromBytes(
      Uint8List.fromList([2]),
      id: 'failed',
      name: 'failed.png',
    ).copyWith(
      status: CreateMediaUploadItemStatus.failed,
      storagePath: 'user-1/post-2-1.png',
      errorMessage: 'timeout',
    );
    final calls = <String>[];
    final service = CreateMediaUploadService(
      uploadExecutor: ({
        required bucket,
        required storagePath,
        required item,
        required timeout,
      }) async {
        calls.add('${item.id}|$storagePath');
        return 'https://example.test/$storagePath';
      },
    );

    final result =
        await service.uploadManifest(manifestWith([uploaded, failed]));

    expect(calls, ['failed|user-1/post-2-1.png']);
    expect(result.items.first.publicUrl, 'https://example.test/done.png');
    expect(result.items.last.publicUrl,
        'https://example.test/user-1/post-2-1.png');
    expect(result.isComplete, isTrue);
  });

  test('cancel stops starting new uploads after current item', () async {
    final token = CreateMediaUploadCancelToken();
    final started = <String>[];
    final progress = <CreateMediaUploadProgressStatus>[];
    final service = CreateMediaUploadService(
      uploadExecutor: ({
        required bucket,
        required storagePath,
        required item,
        required timeout,
      }) async {
        started.add(item.id);
        token.cancel();
        return 'https://example.test/$storagePath';
      },
    );

    final result = await service.uploadManifest(
      manifestWith([
        CreateMediaUploadItem.fromBytes(
          Uint8List.fromList([1]),
          id: 'one',
          name: 'one.png',
        ),
        CreateMediaUploadItem.fromBytes(
          Uint8List.fromList([2]),
          id: 'two',
          name: 'two.png',
        ),
      ]),
      cancelToken: token,
      onProgress: (event) => progress.add(event.status),
    );

    expect(started, ['one']);
    expect(result.items.first.status, CreateMediaUploadItemStatus.uploaded);
    expect(result.items.last.status, CreateMediaUploadItemStatus.pending);
    expect(progress, contains(CreateMediaUploadProgressStatus.cancelled));
  });

  test('marks failed items without losing retry state', () async {
    final service = CreateMediaUploadService(
      now: () => DateTime.fromMillisecondsSinceEpoch(999),
      uploadExecutor: ({
        required bucket,
        required storagePath,
        required item,
        required timeout,
      }) async {
        throw TimeoutException('slow');
      },
    );

    final result = await service.uploadManifest(
      manifestWith([
        CreateMediaUploadItem.fromBytes(
          Uint8List.fromList([9]),
          id: 'slow',
          name: 'slow.mp4',
        ),
      ]),
    );

    expect(result.hasFailures, isTrue);
    expect(result.items.single.status, CreateMediaUploadItemStatus.failed);
    expect(result.items.single.storagePath, 'user-1/post-999-0.mp4');
    expect(result.items.single.errorMessage, contains('TimeoutException'));
  });
}
