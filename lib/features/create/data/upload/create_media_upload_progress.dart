import 'create_media_upload_manifest.dart';

enum CreateMediaUploadProgressStatus {
  started,
  completed,
  failed,
  skipped,
  cancelled,
}

class CreateMediaUploadProgress {
  const CreateMediaUploadProgress({
    required this.itemId,
    required this.itemName,
    required this.done,
    required this.total,
    required this.status,
    this.publicUrl,
    this.errorMessage,
  });

  final String itemId;
  final String itemName;
  final int done;
  final int total;
  final CreateMediaUploadProgressStatus status;
  final String? publicUrl;
  final String? errorMessage;

  double get fraction => total <= 0 ? 1 : done.clamp(0, total) / total;

  bool get isTerminal =>
      status == CreateMediaUploadProgressStatus.completed ||
      status == CreateMediaUploadProgressStatus.failed ||
      status == CreateMediaUploadProgressStatus.cancelled ||
      status == CreateMediaUploadProgressStatus.skipped;

  CreateMediaUploadItemStatus get itemStatus {
    switch (status) {
      case CreateMediaUploadProgressStatus.started:
        return CreateMediaUploadItemStatus.uploading;
      case CreateMediaUploadProgressStatus.completed:
      case CreateMediaUploadProgressStatus.skipped:
        return CreateMediaUploadItemStatus.uploaded;
      case CreateMediaUploadProgressStatus.failed:
        return CreateMediaUploadItemStatus.failed;
      case CreateMediaUploadProgressStatus.cancelled:
        return CreateMediaUploadItemStatus.pending;
    }
  }
}
