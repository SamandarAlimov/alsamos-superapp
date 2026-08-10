import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

final mediaPickerManagerProvider =
    Provider<MediaPickerManager>((ref) => MediaPickerManager());

enum MediaType { image, video, audio, document, file }

class PickedMedia {
  final String path;
  final String name;
  final MediaType type;
  final int? size;
  final String? mimeType;
  final int? width;
  final int? height;
  final Duration? duration;

  const PickedMedia({
    required this.path,
    required this.name,
    required this.type,
    this.size,
    this.mimeType,
    this.width,
    this.height,
    this.duration,
  });

  bool get isImage => type == MediaType.image;
  bool get isVideo => type == MediaType.video;
  bool get isAudio => type == MediaType.audio;
  bool get isDocument => type == MediaType.document;
}

class MediaPickerManager {
  final _imagePicker = ImagePicker();

  Future<PickedMedia?> pickImage({
    ImageSource source = ImageSource.gallery,
    int? maxWidth,
    int? maxHeight,
    int? imageQuality,
  }) async {
    try {
      final file = await _imagePicker.pickImage(
        source: source,
        maxWidth: maxWidth?.toDouble(),
        maxHeight: maxHeight?.toDouble(),
        imageQuality: imageQuality,
      );
      if (file == null) return null;
      return PickedMedia(
        path: file.path,
        name: file.name,
        type: MediaType.image,
        mimeType: file.mimeType,
        size: await file.length(),
      );
    } catch (e) {
      debugPrint('[MediaPickerManager] pickImage: $e');
      return null;
    }
  }

  Future<List<PickedMedia>> pickMultipleImages({
    int? maxWidth,
    int? maxHeight,
    int? imageQuality,
    int? limit,
  }) async {
    try {
      final files = await _imagePicker.pickMultiImage(
        maxWidth: maxWidth?.toDouble(),
        maxHeight: maxHeight?.toDouble(),
        imageQuality: imageQuality,
        limit: limit,
      );
      final results = <PickedMedia>[];
      for (final file in files) {
        results.add(PickedMedia(
          path: file.path,
          name: file.name,
          type: MediaType.image,
          mimeType: file.mimeType,
          size: await file.length(),
        ));
      }
      return results;
    } catch (e) {
      debugPrint('[MediaPickerManager] pickMultipleImages: $e');
      return [];
    }
  }

  Future<PickedMedia?> pickVideo({
    ImageSource source = ImageSource.gallery,
    Duration? maxDuration,
  }) async {
    try {
      final file = await _imagePicker.pickVideo(
        source: source,
        maxDuration: maxDuration,
      );
      if (file == null) return null;
      return PickedMedia(
        path: file.path,
        name: file.name,
        type: MediaType.video,
        mimeType: file.mimeType,
        size: await file.length(),
      );
    } catch (e) {
      debugPrint('[MediaPickerManager] pickVideo: $e');
      return null;
    }
  }

  Future<List<PickedMedia>> pickFiles({
    List<String>? allowedExtensions,
    bool allowMultiple = false,
    FileType type = FileType.any,
  }) async {
    try {
      final result = await FilePicker.pickFiles(
        type: allowedExtensions != null ? FileType.custom : type,
        allowedExtensions: allowedExtensions,
        allowMultiple: allowMultiple,
      );
      if (result == null) return [];
      return result.files.where((f) => f.path != null).map((f) {
        return PickedMedia(
          path: f.path!,
          name: f.name,
          type: _typeFromExtension(f.extension),
          mimeType: null,
          size: f.size,
        );
      }).toList();
    } catch (e) {
      debugPrint('[MediaPickerManager] pickFiles: $e');
      return [];
    }
  }

  Future<PickedMedia?> pickDocument() async {
    final results = await pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
        'txt', 'csv', 'json', 'zip', 'rar',
      ],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<PickedMedia?> pickAudio() async {
    final results = await pickFiles(type: FileType.audio);
    if (results.isEmpty) return null;
    return PickedMedia(
      path: results.first.path,
      name: results.first.name,
      type: MediaType.audio,
      size: results.first.size,
    );
  }

  Future<bool> requestCameraPermission() async {
    if (kIsWeb) return true;
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  Future<bool> requestMicrophonePermission() async {
    if (kIsWeb) return true;
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> requestStoragePermission() async {
    if (kIsWeb) return true;
    if (Platform.isAndroid) {
      final status = await Permission.photos.request();
      if (status.isGranted) return true;
      return (await Permission.storage.request()).isGranted;
    }
    return (await Permission.photos.request()).isGranted;
  }

  MediaType _typeFromExtension(String? ext) {
    if (ext == null) return MediaType.file;
    final e = ext.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp'].contains(e)) {
      return MediaType.image;
    }
    if (['mp4', 'mov', 'avi', 'mkv', 'webm', 'flv'].contains(e)) {
      return MediaType.video;
    }
    if (['mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac', 'wma'].contains(e)) {
      return MediaType.audio;
    }
    if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv'].contains(e)) {
      return MediaType.document;
    }
    return MediaType.file;
  }
}
