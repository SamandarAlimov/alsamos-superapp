import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

const createMediaUploadBucket = 'message-attachments';
const createMediaUploadTimeout = Duration(seconds: 60);

enum CreateMediaUploadItemStatus {
  pending,
  uploading,
  uploaded,
  failed,
}

enum CreateMediaUploadSourceKind {
  filePath,
  bytes,
  xFile,
}

class CreateMediaUploadManifest {
  CreateMediaUploadManifest({
    required this.userId,
    required List<CreateMediaUploadItem> items,
    this.bucket = createMediaUploadBucket,
    this.timeout = createMediaUploadTimeout,
  }) : items = List.unmodifiable(items);

  final String userId;
  final String bucket;
  final Duration timeout;
  final List<CreateMediaUploadItem> items;

  List<String> get uploadedUrls => [
        for (final item in items)
          if (item.status == CreateMediaUploadItemStatus.uploaded &&
              item.publicUrl != null)
            item.publicUrl!,
      ];

  bool get isComplete => items.every(
        (item) => item.status == CreateMediaUploadItemStatus.uploaded,
      );

  bool get hasFailures => items.any(
        (item) => item.status == CreateMediaUploadItemStatus.failed,
      );

  int get completedCount => items
      .where((item) => item.status == CreateMediaUploadItemStatus.uploaded)
      .length;

  int get remainingCount => items.length - completedCount;

  CreateMediaUploadManifest copyWith({
    String? userId,
    String? bucket,
    Duration? timeout,
    List<CreateMediaUploadItem>? items,
  }) {
    return CreateMediaUploadManifest(
      userId: userId ?? this.userId,
      bucket: bucket ?? this.bucket,
      timeout: timeout ?? this.timeout,
      items: List.unmodifiable(items ?? this.items),
    );
  }
}

class CreateMediaUploadItem {
  const CreateMediaUploadItem({
    required this.id,
    required this.name,
    required this.extension,
    required this.sourceKind,
    this.filePath,
    this.bytes,
    this.xFile,
    this.storagePrefix = 'post',
    this.storagePath,
    this.publicUrl,
    this.status = CreateMediaUploadItemStatus.pending,
    this.errorMessage,
  });

  factory CreateMediaUploadItem.fromXFile(
    XFile file, {
    required String id,
    String storagePrefix = 'post',
    String? name,
    String? extension,
  }) {
    final fileName =
        name ?? _nameFromPath(file.name.isEmpty ? file.path : file.name);
    return CreateMediaUploadItem(
      id: id,
      name: fileName,
      extension: _extensionFromName(extension ?? fileName),
      sourceKind: CreateMediaUploadSourceKind.xFile,
      filePath: file.path.isEmpty ? null : file.path,
      xFile: file,
      storagePrefix: storagePrefix,
    );
  }

  factory CreateMediaUploadItem.fromFilePath(
    String path, {
    required String id,
    String storagePrefix = 'post',
    String? name,
    String? extension,
  }) {
    final fileName = name ?? _nameFromPath(path);
    return CreateMediaUploadItem(
      id: id,
      name: fileName,
      extension: _extensionFromName(extension ?? fileName),
      sourceKind: CreateMediaUploadSourceKind.filePath,
      filePath: path,
      storagePrefix: storagePrefix,
    );
  }

  factory CreateMediaUploadItem.fromFile(
    Object file, {
    required String id,
    String storagePrefix = 'post',
    String? name,
    String? extension,
  }) {
    final path = (file as dynamic).path as String;
    return CreateMediaUploadItem.fromFilePath(
      path,
      id: id,
      storagePrefix: storagePrefix,
      name: name,
      extension: extension,
    );
  }

  factory CreateMediaUploadItem.fromBytes(
    Uint8List bytes, {
    required String id,
    required String name,
    String storagePrefix = 'post',
    String? extension,
  }) {
    return CreateMediaUploadItem(
      id: id,
      name: name,
      extension: _extensionFromName(extension ?? name),
      sourceKind: CreateMediaUploadSourceKind.bytes,
      bytes: Uint8List.fromList(bytes),
      storagePrefix: storagePrefix,
    );
  }

  final String id;
  final String name;
  final String extension;
  final CreateMediaUploadSourceKind sourceKind;
  final String? filePath;
  final Uint8List? bytes;
  final XFile? xFile;
  final String storagePrefix;
  final String? storagePath;
  final String? publicUrl;
  final CreateMediaUploadItemStatus status;
  final String? errorMessage;

  bool get isUploaded =>
      status == CreateMediaUploadItemStatus.uploaded && publicUrl != null;

  bool get shouldUpload => !isUploaded;

  Future<Uint8List> readBytes() async {
    final inMemory = bytes;
    if (inMemory != null) return Uint8List.fromList(inMemory);

    final picked = xFile;
    if (picked != null) return picked.readAsBytes();

    final path = filePath;
    if (path != null && path.isNotEmpty) return XFile(path).readAsBytes();

    throw StateError('No upload source is available for $id');
  }

  CreateMediaUploadItem copyWith({
    String? id,
    String? name,
    String? extension,
    CreateMediaUploadSourceKind? sourceKind,
    String? filePath,
    Uint8List? bytes,
    XFile? xFile,
    String? storagePrefix,
    String? storagePath,
    String? publicUrl,
    CreateMediaUploadItemStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CreateMediaUploadItem(
      id: id ?? this.id,
      name: name ?? this.name,
      extension: extension ?? this.extension,
      sourceKind: sourceKind ?? this.sourceKind,
      filePath: filePath ?? this.filePath,
      bytes: bytes == null ? this.bytes : Uint8List.fromList(bytes),
      xFile: xFile ?? this.xFile,
      storagePrefix: storagePrefix ?? this.storagePrefix,
      storagePath: storagePath ?? this.storagePath,
      publicUrl: publicUrl ?? this.publicUrl,
      status: status ?? this.status,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  static String _nameFromPath(String value) {
    final normalized = value.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty || parts.last.isEmpty ? 'upload.bin' : parts.last;
  }

  static String _extensionFromName(String value) {
    final normalized = value.split('?').first;
    final index = normalized.lastIndexOf('.');
    if (index < 0 || index == normalized.length - 1) return 'bin';
    return normalized.substring(index + 1).toLowerCase();
  }
}
