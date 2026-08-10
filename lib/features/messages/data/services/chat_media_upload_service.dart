import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_client.dart';

class ChatMediaUploadResult {
  final String bucket;
  final String mediaPath;
  final String signedUrl;
  final String? thumbPath;
  final String? thumbSignedUrl;

  const ChatMediaUploadResult({
    required this.bucket,
    required this.mediaPath,
    required this.signedUrl,
    this.thumbPath,
    this.thumbSignedUrl,
  });
}

class ChatMediaUploadService {
  const ChatMediaUploadService();

  Future<ChatMediaUploadResult> upload({
    required String conversationId,
    required String senderId,
    required String localPath,
    required String mediaType,
    required String mimeType,
    String? localThumbPath,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Media offline upload is not available on web yet');
    }
    final extension = _extensionFor(mimeType, localPath);
    final mediaPath =
        '$conversationId/$senderId/${DateTime.now().microsecondsSinceEpoch}.$extension';
    final mediaFile = File(localPath);
    final bucket = await _uploadWithFallback(
      mediaType: mediaType,
      path: mediaPath,
      file: mediaFile,
      contentType: mimeType,
    );
    String? thumbPath;
    String? thumbUrl;
    if (localThumbPath != null && File(localThumbPath).existsSync()) {
      thumbPath =
          '$conversationId/$senderId/thumbs/${DateTime.now().microsecondsSinceEpoch}.jpg';
      try {
        await supabase.storage.from('chat-thumbs').upload(
              thumbPath,
              File(localThumbPath),
              fileOptions:
                  const FileOptions(contentType: 'image/jpeg', upsert: false),
            );
        thumbUrl = await supabase.storage.from('chat-thumbs').createSignedUrl(
              thumbPath,
              60 * 60,
            );
      } catch (e) {
        debugPrint('[ChatMediaUploadService] thumb upload ignored: $e');
        thumbPath = null;
      }
    }
    final signed =
        await supabase.storage.from(bucket).createSignedUrl(mediaPath, 60 * 60);
    return ChatMediaUploadResult(
      bucket: bucket,
      mediaPath: mediaPath,
      signedUrl: signed,
      thumbPath: thumbPath,
      thumbSignedUrl: thumbUrl,
    );
  }

  Future<String?> signedUrlFor({
    required String mediaType,
    required String path,
    String? bucket,
  }) async {
    try {
      return supabase.storage
          .from(bucket ?? _bucketFor(mediaType))
          .createSignedUrl(path, 60 * 60);
    } catch (e) {
      debugPrint('[ChatMediaUploadService] signed url ignored: $e');
      return null;
    }
  }

  Future<String?> signedThumbUrl(String path) async {
    try {
      return supabase.storage.from('chat-thumbs').createSignedUrl(path, 60 * 60);
    } catch (e) {
      debugPrint('[ChatMediaUploadService] thumb signed url ignored: $e');
      return null;
    }
  }

  static List<int> waveformFromBytes(Uint8List bytes, {int samples = 48}) {
    if (bytes.isEmpty) return List<int>.filled(samples, 20);
    final chunk = math.max(1, bytes.length ~/ samples);
    return List<int>.generate(samples, (i) {
      final start = i * chunk;
      final end = math.min(bytes.length, start + chunk);
      if (start >= end) return 18;
      var sum = 0;
      for (var j = start; j < end; j++) {
        sum += (bytes[j] - 128).abs();
      }
      final avg = sum / (end - start);
      return (18 + (avg / 128) * 82).round().clamp(12, 100);
    });
  }

  String _bucketFor(String mediaType) {
    if (mediaType == 'voice' || mediaType == 'audio') return 'chat-audio';
    if (mediaType == 'video' || mediaType == 'video_note') return 'chat-video';
    return 'message-attachments';
  }

  Future<String> _uploadWithFallback({
    required String mediaType,
    required String path,
    required File file,
    required String contentType,
  }) async {
    Object? firstError;
    for (final bucket in _candidateBuckets(mediaType)) {
      try {
        await supabase.storage.from(bucket).upload(
              path,
              file,
              fileOptions: FileOptions(contentType: contentType, upsert: false),
            );
        return bucket;
      } catch (e) {
        firstError ??= e;
        if (!_isMissingBucket(e)) rethrow;
        debugPrint(
          '[ChatMediaUploadService] $bucket bucket missing; trying fallback. '
          'Apply 20260713102000_chat_voice_video_messages.sql for private media buckets.',
        );
      }
    }
    throw firstError ?? StateError('Media upload failed');
  }

  List<String> _candidateBuckets(String mediaType) {
    final preferred = _bucketFor(mediaType);
    if (preferred == 'message-attachments') return const ['message-attachments'];
    return [preferred, 'message-attachments'];
  }

  bool _isMissingBucket(Object error) {
    final lower = error.toString().toLowerCase();
    return lower.contains('bucket not found') || lower.contains('404');
  }

  String _extensionFor(String mimeType, String path) {
    final fromPath = path.contains('.') ? path.split('.').last : '';
    if (fromPath.isNotEmpty && fromPath.length <= 5) return fromPath;
    return switch (mimeType) {
      'audio/mp4' || 'audio/m4a' || 'audio/aac' => 'm4a',
      'audio/ogg' => 'ogg',
      'audio/webm' => 'webm',
      'video/quicktime' => 'mov',
      'video/webm' => 'webm',
      _ => 'mp4',
    };
  }
}
