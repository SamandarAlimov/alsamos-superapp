import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'create_media_upload_manifest.dart';

Future<void> uploadCreateMediaItemToStorage({
  required StorageFileApi storage,
  required String storagePath,
  required CreateMediaUploadItem item,
  required Duration timeout,
}) async {
  final filePath = item.filePath;
  final file = filePath == null ? null : File(filePath);

  if (file != null && await file.exists()) {
    await storage.upload(storagePath, file).timeout(timeout);
    return;
  }

  await storage
      .uploadBinary(storagePath, await item.readBytes())
      .timeout(timeout);
}
