import 'package:supabase_flutter/supabase_flutter.dart';

import 'create_media_upload_manifest.dart';

Future<void> uploadCreateMediaItemToStorage({
  required StorageFileApi storage,
  required String storagePath,
  required CreateMediaUploadItem item,
  required Duration timeout,
}) async {
  await storage
      .uploadBinary(storagePath, await item.readBytes())
      .timeout(timeout);
}
