import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:easy_video_editor/easy_video_editor.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../../shared/content/data/content_post_repository.dart';
import '../../../shared/content/models/content_item.dart';
import '../../../shared/content/models/content_media.dart';
import '../../../shared/services/camera_capability.dart';
import '../../../shared/stories/story_avatar_ring.dart';
import '../../../shared/stories/story_presence_controller.dart';
import '../data/create_collaboration_repository.dart';
import '../data/create_product_tag_repository.dart';
import '../data/models/create_collaborator.dart';
import '../data/models/create_product_tag.dart';
import '../data/upload/create_media_upload_manifest.dart';
import '../data/upload/create_media_upload_progress.dart';
import '../data/upload/create_media_upload_service.dart';
import 'widgets/schedule_post_dialog.dart';
import 'widgets/poll_creator.dart';
import 'widgets/music_picker.dart';
import 'widgets/create_location_picker_sheet.dart';
import 'widgets/create_collaborator_picker.dart';
import 'widgets/create_media_preview_stage.dart';
import 'widgets/create_product_tag_picker.dart';
import 'widgets/publish_progress_banner.dart';
import 'widgets/create_video_edit_sheet.dart';
import 'widgets/create_live_tab.dart';
import 'widgets/create_post_tab.dart';
import 'widgets/create_reel_tab.dart';
import 'widgets/create_story_tab.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/error_mapper.dart';
import '../../map/presentation/providers/location_provider.dart';
import '../../live/presentation/widgets/live_stream_broadcast.dart';
import '../../stories/presentation/providers/stories_provider.dart';

final contentPostRepositoryProvider =
    Provider((ref) => ContentPostRepository());
final createCollaborationRepositoryProvider =
    Provider((ref) => const CreateCollaborationRepository());
final createProductTagRepositoryProvider =
    Provider((ref) => const CreateProductTagRepository());
final createMediaUploadServiceProvider =
    Provider((ref) => CreateMediaUploadService());

enum _Tab { post, story, reel, live }

class _CreatePublishCancelled implements Exception {
  const _CreatePublishCancelled();
}

// File attachment model for all file types
class _FileAttachment {
  final String? path;
  final Uint8List? bytes;
  final String name;
  final String extension;
  final int sizeBytes;

  _FileAttachment({
    this.path,
    this.bytes,
    required this.name,
    required this.extension,
    required this.sizeBytes,
  });

  String get sizeFormatted {
    if (sizeBytes < 1024) {
      return '$sizeBytes B';
    }
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  IconData get icon {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return LucideIcons.fileText;
      case 'doc':
      case 'docx':
        return LucideIcons.fileText;
      case 'xls':
      case 'xlsx':
        return LucideIcons.fileSpreadsheet;
      case 'ppt':
      case 'pptx':
        return LucideIcons.presentation;
      case 'zip':
      case 'rar':
      case '7z':
        return LucideIcons.fileArchive;
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'flac':
        return LucideIcons.music;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
        return LucideIcons.video;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return LucideIcons.image;
      case 'apk':
        return LucideIcons.smartphone;
      case 'exe':
      case 'msi':
        return LucideIcons.monitor;
      case 'txt':
      case 'md':
        return LucideIcons.fileText;
      default:
        return LucideIcons.file;
    }
  }

  Color get color {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return const Color(0xFFEF4444);
      case 'doc':
      case 'docx':
        return const Color(0xFF3B82F6);
      case 'xls':
      case 'xlsx':
        return const Color(0xFF22C55E);
      case 'ppt':
      case 'pptx':
        return const Color(0xFFF97316);
      case 'zip':
      case 'rar':
      case '7z':
        return const Color(0xFF8B5CF6);
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'flac':
        return const Color(0xFFEC4899);
      case 'apk':
        return const Color(0xFF22C55E);
      case 'exe':
      case 'msi':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF6B7280);
    }
  }

  bool get isImage {
    final ext = extension.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  bool get isVideo {
    final ext = extension.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'flv', 'wmv'].contains(ext);
  }

  bool get isAudio {
    final ext = extension.toLowerCase();
    return ['mp3', 'wav', 'ogg', 'flac', 'aac', 'm4a'].contains(ext);
  }
}

/// Professional Instagram/YouTube style Create Page
class CreatePage extends ConsumerStatefulWidget {
  const CreatePage({super.key, this.editPostId, this.editData});

  final String? editPostId;
  final Map<String, dynamic>? editData;

  bool get isEditing => editPostId != null;

  @override
  ConsumerState<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends ConsumerState<CreatePage> {
  final _content = TextEditingController();
  final _contentFocusNode = FocusNode();
  final _location = TextEditingController();
  final _tagInput = TextEditingController();
  final _storyMentionSearch = TextEditingController();
  _Tab _tab = _Tab.post;
  String _visibility = 'public';
  final List<String> _tags = [];
  final List<CreateCollaborator> _collaborators = [];
  final List<CreateProductTag> _productTags = [];
  ContentLocation? _selectedLocation;
  final List<_FileAttachment> _files = [];
  final List<XFile> _mediaFiles = []; // For quick image/video picker
  int _currentMediaIndex = 0;
  String _aspectPresetId = 'original';
  bool _submitting = false;
  int _publishUploadDone = 0;
  int _publishUploadTotal = 0;
  String? _publishUploadStatus;
  bool _publishUploadFailed = false;
  CreateMediaUploadManifest? _mediaUploadManifest;
  String? _mediaUploadManifestKey;
  CreateMediaUploadCancelToken? _mediaUploadCancelToken;
  bool _locatingForPost = false;
  bool _videoExporting = false;
  double _videoExportProgress = 0;
  DateTime? _scheduledAt;
  Map<String, dynamic>? _poll;
  MusicTrack? _musicTrack;
  bool _liveChatEnabled = true;
  bool _liveReactionsEnabled = true;
  bool _liveRecordingEnabled = false;
  // Story-only state
  Color _storyBg = const Color(0xFFF97316);
  double _storyTextSize = 28;
  String _storyFont = 'bold';
  TextAlign _storyTextAlign = TextAlign.center;
  Offset _storyTextPosition = const Offset(0.5, 0.52);
  final List<String> _storyMentions = [];
  bool get _usesDesktopPickers =>
      CameraCapability.shouldUseFilePickerForGallery;

  bool get _isEditing => widget.isEditing;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadEditData());
    }
  }

  Future<void> _loadEditData() async {
    final data = widget.editData;
    if (data != null) {
      _populateFromEditData(data);
      return;
    }
    final postId = widget.editPostId;
    if (postId == null) return;
    try {
      final post =
          await ref.read(contentPostRepositoryProvider).fetchPostById(postId);
      if (post == null || !mounted) return;
      _populateFromEditData(post.toEditMap());
    } catch (e) {
      if (mounted) AppToast.error(context, friendlyError(e));
    }
  }

  void _populateFromEditData(Map<String, dynamic> data) {
    setState(() {
      _content.text = (data['content'] as String?) ?? '';
      final tags = data['hashtags'] ?? data['tags'];
      if (tags is List) {
        _tags
          ..clear()
          ..addAll(tags.map((t) => t.toString()));
      }
      _visibility = (data['visibility'] as String?) ?? 'public';
      final locationName = data['location_name'] as String?;
      if (locationName != null && locationName.isNotEmpty) {
        _location.text = locationName;
        _selectedLocation = ContentLocation(
          latitude: (data['location_lat'] as num?)?.toDouble() ?? 0,
          longitude: (data['location_lng'] as num?)?.toDouble() ?? 0,
          name: locationName,
          address: data['location_address'] as String?,
          geohash: data['location_geohash'] as String?,
        );
      }
    });
  }

  @override
  void dispose() {
    _content.dispose();
    _contentFocusNode.dispose();
    _location.dispose();
    _tagInput.dispose();
    _storyMentionSearch.dispose();
    super.dispose();
  }

  // Pick any file type (documents, APKs, ZIPs, etc.)
  Future<void> _pickAnyFile() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: true,
    );
    if (result != null) {
      setState(() {
        for (final pf in result.files) {
          if (_files.length < 10) {
            final nameParts = pf.name.split('.');
            final ext =
                pf.extension ?? (nameParts.length > 1 ? nameParts.last : '');
            final size = pf.size > 0
                ? pf.size
                : (pf.path == null
                    ? (pf.bytes?.length ?? 0)
                    : File(pf.path!).lengthSync());
            _files.add(_FileAttachment(
              path: pf.path,
              bytes: pf.bytes,
              name: pf.name,
              extension: ext,
              sizeBytes: size,
            ));
          }
        }
      });
    }
  }

  // Pick image/video (quick picker for media)
  Future<void> _pickMedia({bool video = false}) async {
    try {
      if (_usesDesktopPickers) {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowMultiple: _tab == _Tab.post && !video,
          withData: false,
          allowedExtensions: video
              ? const ['mp4', 'mov', 'webm', 'm4v', 'avi', 'mkv']
              : const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
        );
        if (result == null || result.files.isEmpty) return;
        final picked = result.files
            .where((f) => f.path != null && f.path!.isNotEmpty)
            .map((f) => XFile(f.path!, name: f.name))
            .toList();
        if (picked.isEmpty) {
          if (mounted) {
            AppToast.error(context, 'Faylni o‘qib bo‘lmadi');
          }
          return;
        }
        setState(() {
          if (_tab != _Tab.post) {
            _mediaFiles
              ..clear()
              ..add(picked.first);
            _currentMediaIndex = 0;
          } else {
            for (final media in picked) {
              if (_mediaFiles.length < 10) {
                _mediaFiles.add(media);
                _currentMediaIndex = _mediaFiles.length - 1;
              }
            }
          }
        });
        return;
      }

      final picker = ImagePicker();
      if (video) {
        final v = await picker.pickVideo(source: ImageSource.gallery);
        if (v != null) {
          setState(() {
            if (_tab != _Tab.post) {
              _mediaFiles
                ..clear()
                ..add(v);
              _currentMediaIndex = 0;
            } else if (_mediaFiles.length < 10) {
              _mediaFiles.add(v);
              _currentMediaIndex = _mediaFiles.length - 1;
            }
          });
        }
      } else {
        final imgs = await picker.pickMultiImage(imageQuality: 85);
        if (imgs.isEmpty) return;
        setState(() {
          if (_tab != _Tab.post) {
            _mediaFiles
              ..clear()
              ..add(imgs.first);
            _currentMediaIndex = 0;
          } else {
            for (final img in imgs) {
              if (_mediaFiles.length < 10) {
                _mediaFiles.add(img);
                _currentMediaIndex = _mediaFiles.length - 1;
              }
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Media tanlab bo‘lmadi', error: e);
      }
    }
  }

  Future<void> _pickStoryCamera({bool video = false}) async {
    if (_usesDesktopPickers) {
      AppToast.warning(
        context,
        CameraCapability.unsupportedCaptureMessage,
      );
      await _pickMedia(video: video);
      return;
    }
    final picker = ImagePicker();
    try {
      final XFile? picked = video
          ? await picker.pickVideo(
              source: ImageSource.camera,
              maxDuration: const Duration(seconds: 60),
            )
          : await picker.pickImage(
              source: ImageSource.camera,
              imageQuality: 88,
              preferredCameraDevice: CameraDevice.rear,
            );
      if (picked == null) return;
      setState(() {
        _mediaFiles
          ..clear()
          ..add(picked);
        _currentMediaIndex = 0;
        _aspectPresetId = '9:16';
      });
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Kamerani ochib bo‘lmadi', error: e);
      }
    }
  }

  void _removeMedia(int i) => setState(() {
        _mediaFiles.removeAt(i);
        if (_currentMediaIndex >= _mediaFiles.length) {
          final lastIndex = _mediaFiles.length - 1;
          _currentMediaIndex = lastIndex < 0 ? 0 : lastIndex;
        }
      });
  void _removeFile(int i) => setState(() => _files.removeAt(i));

  bool get _supportsNativeImageEditor =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  bool get _supportsNativeVideoEditor =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _editCurrentMedia() async {
    if (_mediaFiles.isEmpty) return;
    final index = _currentMediaIndex.clamp(0, _mediaFiles.length - 1).toInt();
    final file = _mediaFiles[index];
    if (_isVideoPath(file.path)) {
      await _editCurrentVideo(index, file);
      return;
    }
    if (!_isImagePath(file.path)) {
      AppToast.warning(context, 'Bu fayl turini tahrirlab bo\'lmaydi');
      return;
    }
    if (!_supportsNativeImageEditor) {
      AppToast.warning(
        context,
        'Desktopda rasm tahriri uchun hozir aspect tugmalaridan foydalaning',
      );
      return;
    }
    try {
      final primary = Theme.of(context).colorScheme.primary;
      final cropped = await ImageCropper().cropImage(
        sourcePath: file.path,
        compressQuality: 92,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Media editor',
            toolbarColor: primary,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: primary,
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: 'Media editor',
            aspectRatioLockEnabled: false,
          ),
          WebUiSettings(
            context: context,
            presentStyle: WebPresentStyle.dialog,
            size: const CropperSize(width: 900, height: 620),
          ),
        ],
      );
      if (cropped == null || !mounted) return;
      setState(() {
        _mediaFiles[index] = XFile(cropped.path, name: file.name);
        _currentMediaIndex = index;
      });
      AppToast.success(context, 'Rasm tahrirlandi');
    } catch (error) {
      if (mounted) {
        AppToast.error(context, 'Rasmni tahrirlab bo\'lmadi', error: error);
      }
    }
  }

  Future<void> _editCurrentVideo(int index, XFile file) async {
    if (!_supportsNativeVideoEditor) {
      AppToast.warning(
        context,
        'Video editor Android/iOS qurilmalarda real export qiladi',
      );
      return;
    }
    if (_videoExporting) return;

    final result = await showModalBottomSheet<VideoEditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateVideoEditSheet(path: file.path),
    );
    if (result == null || !mounted) return;

    try {
      setState(() {
        _videoExporting = true;
        _videoExportProgress = 0;
      });

      final editor = VideoEditorBuilder(videoPath: file.path);
      if (result.trimChanged) {
        editor.trim(
          startTimeMs: result.start.inMilliseconds,
          endTimeMs: result.end.inMilliseconds,
        );
      }
      if (result.aspectRatio != null) {
        editor.crop(aspectRatio: result.aspectRatio!);
      }
      if (result.speed != 1) {
        editor.speed(speed: result.speed);
      }
      if (result.mute) {
        editor.removeAudio();
      }
      if (result.compress) {
        editor.compress(resolution: VideoResolution.p720);
      }

      final outputPath = await editor.export(
        onProgress: (progress) {
          if (mounted) {
            setState(() => _videoExportProgress = progress);
          }
        },
      );
      if (!mounted) return;
      if (outputPath == null || outputPath.isEmpty) {
        AppToast.error(context, 'Videoni tahrirlab bo\'lmadi');
        return;
      }
      setState(() {
        _mediaFiles[index] = XFile(outputPath, name: file.name);
        _currentMediaIndex = index;
      });
      AppToast.success(context, 'Video tahrirlandi');
    } catch (error) {
      if (mounted) {
        AppToast.error(context, 'Videoni tahrirlab bo\'lmadi', error: error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _videoExporting = false;
          _videoExportProgress = 0;
        });
      }
    }
  }

  void _selectTab(_Tab tab) {
    setState(() {
      _tab = tab;
      _currentMediaIndex = 0;
      if (tab != _Tab.post) {
        _files.clear();
        _poll = null;
        if (_mediaFiles.length > 1) {
          _mediaFiles.removeRange(1, _mediaFiles.length);
        }
      }
      if (tab == _Tab.reel) {
        _aspectPresetId = '9:16';
      } else if (tab == _Tab.story) {
        _aspectPresetId = '9:16';
      } else if (tab == _Tab.post) {
        _aspectPresetId = 'original';
      }
    });
  }

  void _addTag() {
    final t = _tagInput.text.trim().replaceFirst(RegExp(r'^#'), '');
    if (t.isNotEmpty && !_tags.contains(t) && _tags.length < 30) {
      setState(() {
        _tags.add(t);
        _tagInput.clear();
      });
    }
  }

  void _beginPublishProgress(int total, {int done = 0}) {
    if (!mounted) return;
    setState(() {
      _publishUploadDone = done;
      _publishUploadTotal = total;
      _publishUploadStatus = total > 0
          ? done > 0
              ? 'Yuklash davom ettirilmoqda...'
              : 'Fayllar tayyorlanmoqda...'
          : 'Post tayyorlanmoqda...';
      _publishUploadFailed = false;
    });
  }

  void _setPublishProgress({
    required String status,
    int? done,
    int? total,
  }) {
    if (!mounted) return;
    setState(() {
      if (done != null) _publishUploadDone = done;
      if (total != null) _publishUploadTotal = total;
      _publishUploadStatus = status;
      _publishUploadFailed = false;
    });
  }

  void _markPublishFailed() {
    if (!mounted) return;
    setState(() {
      _publishUploadFailed = true;
      _publishUploadStatus = 'Yuklash yakunlanmadi. Qayta urinib ko\'ring.';
    });
  }

  void _markPublishCancelled() {
    if (!mounted) return;
    setState(() {
      _publishUploadFailed = true;
      _publishUploadStatus = 'Yuklash to\'xtatildi. Tayyor fayllar saqlandi.';
    });
  }

  void _clearPublishProgress() {
    if (!mounted) return;
    setState(() {
      _publishUploadDone = 0;
      _publishUploadTotal = 0;
      _publishUploadStatus = null;
      _publishUploadFailed = false;
    });
  }

  void _cancelPublish() {
    final token = _mediaUploadCancelToken;
    if (token == null || token.isCancelled) return;
    token.cancel();
    _setPublishProgress(
      status: 'Joriy fayl tugagach yuklash to\'xtaydi...',
    );
  }

  String _buildUploadManifestKey() {
    final mediaLimit = _tab == _Tab.story ? 1 : _mediaFiles.length;
    final media = _mediaFiles.take(mediaLimit).map((file) => {
          'path': file.path,
          'name': file.name,
        });
    final files = _files.map((file) => {
          'path': file.path,
          'name': file.name,
          'size': file.sizeBytes,
          'bytes': file.bytes == null ? null : identityHashCode(file.bytes),
        });
    final music = _musicTrack;
    return jsonEncode({
      'media': media.toList(growable: false),
      'files': files.toList(growable: false),
      if (music?.isLocal ?? false)
        'music': {
          'id': music!.id,
          'path': music.localPath,
          'name': music.fileName,
          'size': music.sizeBytes,
          'bytes': music.localBytes == null
              ? null
              : identityHashCode(music.localBytes),
        },
    });
  }

  CreateMediaUploadManifest _prepareUploadManifest(String userId) {
    final key = _buildUploadManifestKey();
    final existing = _mediaUploadManifest;
    if (_mediaUploadManifestKey == key &&
        existing != null &&
        existing.userId == userId) {
      return existing;
    }

    final items = <CreateMediaUploadItem>[];
    final mediaLimit = _tab == _Tab.story ? 1 : _mediaFiles.length;
    final media = _mediaFiles.take(mediaLimit).toList(growable: false);
    for (var index = 0; index < media.length; index++) {
      items.add(CreateMediaUploadItem.fromXFile(
        media[index],
        id: 'media-$index',
      ));
    }
    for (var index = 0; index < _files.length; index++) {
      final attachment = _files[index];
      if (attachment.path != null) {
        items.add(CreateMediaUploadItem.fromFilePath(
          attachment.path!,
          id: 'file-$index',
          name: attachment.name,
          extension: attachment.extension,
        ));
      } else if (attachment.bytes != null) {
        items.add(CreateMediaUploadItem.fromBytes(
          attachment.bytes!,
          id: 'file-$index',
          name: attachment.name,
          extension: attachment.extension,
        ));
      }
    }

    final music = _musicTrack;
    if (music?.isLocal ?? false) {
      final extension =
          music!.extension?.isNotEmpty == true ? music.extension! : 'mp3';
      final name = music.fileName?.isNotEmpty == true
          ? music.fileName!
          : '${music.title}.$extension';
      if (music.localPath != null) {
        items.add(CreateMediaUploadItem.fromFilePath(
          music.localPath!,
          id: 'music',
          name: name,
          extension: extension,
          storagePrefix: 'music',
        ));
      } else if (music.localBytes != null) {
        items.add(CreateMediaUploadItem.fromBytes(
          music.localBytes!,
          id: 'music',
          name: name,
          extension: extension,
          storagePrefix: 'music',
        ));
      } else {
        throw StateError('Tanlangan musiqa faylini o\'qib bo\'lmadi');
      }
    }

    final manifest = CreateMediaUploadManifest(userId: userId, items: items);
    _mediaUploadManifest = manifest;
    _mediaUploadManifestKey = key;
    return manifest;
  }

  Future<CreateMediaUploadManifest> _uploadPublishAssets(
    CreateMediaUploadManifest manifest,
  ) async {
    final cancelToken = CreateMediaUploadCancelToken();
    _mediaUploadCancelToken = cancelToken;
    late final CreateMediaUploadManifest result;
    try {
      result = await ref.read(createMediaUploadServiceProvider).uploadManifest(
            manifest,
            cancelToken: cancelToken,
            onProgress: _handleUploadProgress,
          );
    } finally {
      _mediaUploadCancelToken = null;
    }
    _mediaUploadManifest = result;
    if (cancelToken.isCancelled && !result.isComplete) {
      throw const _CreatePublishCancelled();
    }
    if (result.hasFailures || !result.isComplete) {
      throw StateError('Bir yoki bir nechta fayl yuklanmadi');
    }
    return result;
  }

  void _handleUploadProgress(CreateMediaUploadProgress progress) {
    final label = progress.itemId == 'music'
        ? 'Musiqa'
        : progress.itemId.startsWith('file-')
            ? 'Fayl'
            : 'Media';
    final status = switch (progress.status) {
      CreateMediaUploadProgressStatus.started => '$label yuklanmoqda...',
      CreateMediaUploadProgressStatus.completed => '$label yuklandi',
      CreateMediaUploadProgressStatus.failed => '$label yuklanmadi',
      CreateMediaUploadProgressStatus.skipped => 'Tayyor fayllar saqlandi',
      CreateMediaUploadProgressStatus.cancelled => 'Yuklash to\'xtatildi',
    };
    _setPublishProgress(
      status: status,
      done: progress.done,
      total: progress.total,
    );
  }

  List<String> _uploadedMediaUrls(CreateMediaUploadManifest manifest) {
    return manifest.items
        .where((item) =>
            item.id.startsWith('media-') || item.id.startsWith('file-'))
        .map((item) => item.publicUrl)
        .whereType<String>()
        .toList(growable: false);
  }

  String? _uploadedMusicUrl(CreateMediaUploadManifest manifest) {
    for (final item in manifest.items) {
      if (item.id == 'music') return item.publicUrl;
    }
    return _musicTrack?.audioUrl;
  }

  bool _isVideoPath(String path) =>
      RegExp(r'\.(mp4|mov|webm|m4v|avi|mkv|flv|wmv)$', caseSensitive: false)
          .hasMatch(path);

  bool _isImagePath(String path) =>
      RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp|heic|heif)$', caseSensitive: false)
          .hasMatch(path);

  bool _isAudioPath(String path) =>
      RegExp(r'\.(mp3|wav|ogg|flac|aac|m4a)$', caseSensitive: false)
          .hasMatch(path);

  String? _mediaTypeForPublish() {
    if (_tab == _Tab.reel) {
      return 'video';
    }
    if (_mediaFiles.isNotEmpty) {
      final first = _mediaFiles.first.path;
      if (_isVideoPath(first)) {
        return 'video';
      }
      if (_isImagePath(first)) {
        return _musicTrack == null ? 'image' : 'image_music';
      }
      if (_isAudioPath(first)) {
        return 'audio';
      }
    }
    if (_files.isNotEmpty) {
      final first = _files.first;
      if (first.isVideo) {
        return 'video';
      }
      if (first.isImage) {
        return 'image';
      }
      if (first.isAudio) {
        return 'audio';
      }
      return 'file';
    }
    return null;
  }

  String _finalContent({String? uploadedMusicUrl}) {
    var content = _content.text.trim();
    if (_poll != null) {
      content = '[POLL]${jsonEncode(_poll)}[/POLL]\n$content'.trim();
    }
    if (_musicTrack != null) {
      content =
          '[MUSIC]${jsonEncode(_musicTrack!.toJson(uploadedUrl: uploadedMusicUrl))}[/MUSIC]\n$content'
              .trim();
    }
    if (_aspectPresetId != 'original') {
      content = '[ASPECT:$_aspectPresetId]\n$content'.trim();
    }
    if (_tags.isNotEmpty) {
      content += '\n\n${_tags.map((t) => '#$t').join(' ')}';
    }
    if (_location.text.trim().isNotEmpty) {
      content += '\n📍 ${_location.text.trim()}';
    }
    return content.trim();
  }

  String _finalStoryCaption({String? uploadedMusicUrl}) {
    final caption = _content.text.trim();
    final meta = <String, dynamic>{
      'textSize': _storyTextSize.round(),
      'font': _storyFont,
      'align': _storyTextAlign.name,
      'background': _storyBg.toARGB32(),
      'textX': double.parse(_storyTextPosition.dx.toStringAsFixed(3)),
      'textY': double.parse(_storyTextPosition.dy.toStringAsFixed(3)),
      if (_storyMentions.isNotEmpty) 'mentions': _storyMentions,
      if (_musicTrack != null)
        'music': _musicTrack!.toJson(uploadedUrl: uploadedMusicUrl),
    };
    return '[STORY_META]${jsonEncode(meta)}[/STORY_META]\n$caption'.trim();
  }

  ContentType _contentTypeForPublish(
      String? mediaType, List<String> mediaUrls) {
    if (_tab == _Tab.reel) {
      return ContentType.reel;
    }
    if (mediaUrls.length > 1) {
      return ContentType.album;
    }
    return switch (mediaType) {
      'video' => ContentType.video,
      'image' || 'image_music' => ContentType.image,
      _ => ContentType.text,
    };
  }

  ContentMediaType _contentMediaTypeForUrl(String url, String? mediaType) {
    if (mediaType == 'video' || _isVideoPath(url)) {
      return ContentMediaType.video;
    }
    if (mediaType == 'audio' || _isAudioPath(url)) {
      return ContentMediaType.audio;
    }
    if (mediaType == 'image' ||
        mediaType == 'image_music' ||
        _isImagePath(url)) {
      return ContentMediaType.image;
    }
    return ContentMediaType.document;
  }

  ContentItem _buildContentDraft({
    required String userId,
    required String content,
    required List<String> mediaUrls,
    required String? mediaType,
  }) {
    final now = DateTime.now().toUtc();
    final location = _effectiveLocation();
    return ContentItem(
      id: '',
      authorId: userId,
      type: _contentTypeForPublish(mediaType, mediaUrls),
      text: content,
      mediaUrl: mediaUrls.isEmpty ? null : mediaUrls.first,
      media: [
        for (var i = 0; i < mediaUrls.length; i++)
          ContentMedia(
            id: 'media-$i',
            type: _contentMediaTypeForUrl(mediaUrls[i], mediaType),
            url: mediaUrls[i],
          ),
      ],
      hashtags: List<String>.unmodifiable(_tags),
      productTags:
          List<String>.unmodifiable(_productTags.map((product) => product.id)),
      location: location,
      visibility: _visibility,
      createdAt: now,
      raw: {
        'media_urls': mediaUrls,
        'media_type': mediaType,
        if (_poll != null) 'poll_data': Map<String, dynamic>.from(_poll!),
        if (location != null) ...location.toPostMap(),
      },
    );
  }

  ContentLocation? _effectiveLocation() {
    final selected = _selectedLocation;
    if (selected == null) return null;
    final name = _location.text.trim();
    return ContentLocation(
      latitude: selected.latitude,
      longitude: selected.longitude,
      name: name.isEmpty ? selected.name : name,
      address: selected.address,
      geohash: selected.geohash,
    );
  }

  Future<void> _useCurrentLocation() async {
    if (_locatingForPost) return;
    setState(() => _locatingForPost = true);
    try {
      final position =
          await ref.read(locationProvider.notifier).acquireForButton();
      if (!mounted) return;
      if (position == null) {
        AppToast.warning(context, 'Joylashuv aniqlanmadi');
        return;
      }
      final coordinates =
          '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      setState(() {
        _selectedLocation = ContentLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          name: _location.text.trim().isEmpty
              ? 'Current location'
              : _location.text.trim(),
          address: coordinates,
        );
        if (_location.text.trim().isEmpty) {
          _location.text = 'Current location';
        }
      });
      AppToast.success(context, 'Joylashuv postga qo\'shildi');
    } catch (error) {
      if (mounted) {
        AppToast.error(
          context,
          'Joylashuvni olishda xatolik',
          error: error,
        );
      }
    } finally {
      if (mounted) setState(() => _locatingForPost = false);
    }
  }

  Future<void> _pickLocationFromMap() async {
    final current = ref.read(locationProvider).currentPosition;
    final initial = _selectedLocation != null
        ? LatLng(_selectedLocation!.latitude, _selectedLocation!.longitude)
        : current != null
            ? LatLng(current.latitude, current.longitude)
            : const LatLng(41.2995, 69.2401);
    final picked = await showModalBottomSheet<ContentLocation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateLocationPickerSheet(
        initial: initial,
        initialName: _location.text.trim(),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedLocation = picked;
      _location.text = picked.name?.trim().isNotEmpty == true
          ? picked.name!
          : picked.address ?? 'Selected location';
    });
  }

  void _clearSelectedLocation() {
    setState(() {
      _selectedLocation = null;
      _location.clear();
    });
  }

  Future<void> _showCollaboratorPicker() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) {
      AppToast.error(context, 'Avval tizimga kiring');
      return;
    }
    final selected = await showCreateCollaboratorPicker(
      context: context,
      onSearch: (query) =>
          ref.read(createCollaborationRepositoryProvider).searchProfiles(
                query: query,
                selectedIds: _collaborators.map((user) => user.id),
              ),
      onError: (error) {
        if (mounted) {
          AppToast.error(context, 'Hamkorlarni izlab bo\'lmadi', error: error);
        }
      },
    );
    if (selected == null || !mounted) return;
    if (_collaborators.any((user) => user.id == selected.id)) return;
    setState(() => _collaborators.add(selected));
  }

  Future<void> _sendCollaborationInvites({required String postId}) async {
    if (_collaborators.isEmpty) return;
    try {
      await ref
          .read(createCollaborationRepositoryProvider)
          .upsertPendingInvites(
            postId: postId,
            collaborators: _collaborators,
          );
    } catch (error) {
      if (mounted) {
        AppToast.warning(
          context,
          'Post joylandi, lekin hamkorlik so\'rovlari yuborilmadi',
          error: error,
        );
      }
    }
  }

  Future<void> _showProductTagPicker() async {
    final selected = await showCreateProductTagPicker(
      context: context,
      onSearch: (query) =>
          ref.read(createProductTagRepositoryProvider).searchProducts(
                query: query,
                selectedIds: _productTags.map((product) => product.id),
              ),
      onError: (error) {
        if (mounted) {
          AppToast.error(
            context,
            'Mahsulotlarni izlab bo\'lmadi',
            error: error,
          );
        }
      },
    );
    if (selected == null || !mounted) return;
    if (_productTags.any((product) => product.id == selected.id)) return;
    setState(() => _productTags.add(selected));
  }

  Future<void> _submit() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    if (_tab == _Tab.live) {
      await _openLiveBroadcast();
      return;
    }

    if (_tab == _Tab.reel &&
        (_mediaFiles.isEmpty || !_isVideoPath(_mediaFiles.first.path))) {
      AppToast.error(context, 'Reel uchun video tanlang');
      return;
    }

    if (_tab == _Tab.story &&
        _content.text.trim().isEmpty &&
        _mediaFiles.isEmpty &&
        _musicTrack == null) {
      AppToast.error(context, 'Story uchun rasm, video yoki matn qo\'shing');
      return;
    }

    if (_tab == _Tab.post && !_hasPostPublishPayload) {
      AppToast.error(context, 'Iltimos, matn yoki fayl qo\'shing');
      return;
    }
    setState(() => _submitting = true);
    try {
      final pendingManifest = _prepareUploadManifest(userId);
      final uploadTotal = pendingManifest.items.length;
      _beginPublishProgress(
        uploadTotal,
        done: pendingManifest.completedCount,
      );
      final uploadedManifest = await _uploadPublishAssets(pendingManifest);
      final mediaUrls = _uploadedMediaUrls(uploadedManifest);
      final uploadedMusicUrl = _uploadedMusicUrl(uploadedManifest);
      final content = _finalContent(uploadedMusicUrl: uploadedMusicUrl);
      _setPublishProgress(
        status: _tab == _Tab.story
            ? 'Story saqlanmoqda...'
            : _tab == _Tab.reel
                ? 'Reel saqlanmoqda...'
                : 'Post saqlanmoqda...',
        done: math.max(uploadTotal, 1),
        total: math.max(uploadTotal, 1),
      );

      if (_tab == _Tab.story) {
        final storyCaption =
            _finalStoryCaption(uploadedMusicUrl: uploadedMusicUrl);
        await ref.read(storiesRepositoryProvider).createStory(
              userId: userId,
              mediaUrl: mediaUrls.isEmpty ? '' : mediaUrls.first,
              mediaType: mediaUrls.isEmpty
                  ? 'text'
                  : (_mediaFiles.isNotEmpty &&
                          _isVideoPath(_mediaFiles.first.path)
                      ? 'video'
                      : 'image'),
              caption: storyCaption.isEmpty ? null : storyCaption,
            );
        ref.invalidate(storiesProvider);
        ref
            .read(storyPresenceControllerProvider.notifier)
            .invalidateUser(userId);
        ref.invalidate(storyAvatarRingProvider(userId));
        if (mounted) {
          _mediaUploadManifest = null;
          _mediaUploadManifestKey = null;
          _clearPublishProgress();
          AppToast.success(context, 'Story joylandi!');
          context.go('/home');
        }
        return;
      }

      final mediaType = _mediaTypeForPublish();

      if (_isEditing) {
        await ref.read(contentPostRepositoryProvider).updatePost(
              widget.editPostId!,
              text: content,
              hashtags: _tags.isNotEmpty ? _tags : null,
              productTags:
                  _productTags.isNotEmpty
                      ? _productTags.map((p) => p.id).toList()
                      : null,
              location: _selectedLocation,
            );
        if (mounted) {
          _mediaUploadManifest = null;
          _mediaUploadManifestKey = null;
          _clearPublishProgress();
          AppToast.success(context, 'Post yangilandi!');
          context.pop();
        }
      } else {
        final created =
            await ref.read(contentPostRepositoryProvider).createPost(
                  _buildContentDraft(
                    userId: userId,
                    content: content,
                    mediaUrls: mediaUrls,
                    mediaType: mediaType,
                  ),
                );
        await _sendCollaborationInvites(postId: created.id);
        if (mounted) {
          _mediaUploadManifest = null;
          _mediaUploadManifestKey = null;
          _clearPublishProgress();
          AppToast.success(
              context,
              _tab == _Tab.reel ? 'Reel joylandi!' : 'Post joylandi!');
          context.go(_tab == _Tab.reel ? '/videos' : '/home');
        }
      }
    } on _CreatePublishCancelled {
      _markPublishCancelled();
    } catch (e) {
      _markPublishFailed();
      _logSubmitError(e);
      if (mounted) {
        AppToast.error(context, friendlyError(e), error: e);
      }
    } finally {
      _mediaUploadCancelToken = null;
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool get _hasPostPublishPayload =>
      _content.text.trim().isNotEmpty ||
      _mediaFiles.isNotEmpty ||
      _files.isNotEmpty ||
      _poll != null ||
      _musicTrack != null ||
      _tags.isNotEmpty ||
      _productTags.isNotEmpty ||
      _selectedLocation != null;

  void _logSubmitError(Object error) {
    developer.log(
      '[CreatePage.submit] failed tab=${_tab.name} visibility=$_visibility mediaFiles=${_mediaFiles.length} files=${_files.length} tags=${_tags.length} products=${_productTags.length} collaborators=${_collaborators.length} hasLocation=${_selectedLocation != null} error=$error',
      name: 'create',
      error: error,
      level: 1000,
    );
    if (error is PostgrestException) {
      developer.log(
        '[CreatePage.submit] PostgrestException code=${error.code} message=${error.message} details=${error.details} hint=${error.hint}',
        name: 'create',
        error: error,
        level: 1000,
      );
    }
  }

  Future<void> _openLiveBroadcast() {
    final title = _content.text.trim();
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            LiveStreamBroadcast(initialTitle: title.isEmpty ? null : title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final profile = ref.watch(authProvider).profile;
    final isMobile = context.responsive.isMobile;

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          // Main content - full screen
          Column(
            children: [
              // Header - Instagram/YouTube style
              SafeArea(
                bottom: false,
                child: Container(
                  height: 56,
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 4),
                  decoration: BoxDecoration(
                      color: c.card,
                      border: Border(bottom: BorderSide(color: c.border))),
                  child: Row(
                    children: [
                      // Close button (X) - Instagram/YouTube style
                      IconButton(
                        onPressed: () => context.canPop()
                            ? context.pop()
                            : context.go('/home'),
                        icon: const Icon(LucideIcons.x, size: 22),
                        tooltip: 'Yopish',
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _isEditing
                              ? 'Tahrirlash'
                              : _tab == _Tab.post
                                  ? 'Yangi post'
                                  : _tab == _Tab.story
                                      ? 'Yangi story'
                                      : _tab == _Tab.reel
                                          ? 'Yangi reel'
                                          : 'Jonli efir',
                          style: const TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              fontWeight: FontWeight.bold,
                              fontSize: 18),
                        ),
                      ),
                      // Schedule button (only for post tab, not edit mode)
                      if (_tab == _Tab.post && !_isEditing)
                        IconButton(
                          onPressed: _submitting
                              ? null
                              : () async {
                                  final picked = await SchedulePostDialog.show(
                                      context,
                                      initialAt: _scheduledAt);
                                  if (picked != null) {
                                    setState(() => _scheduledAt = picked);
                                  }
                                },
                          tooltip: 'Rejalashtirish',
                          icon: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(LucideIcons.calendar,
                                  size: 20,
                                  color: _scheduledAt != null
                                      ? primary
                                      : c.mutedForeground),
                              if (_scheduledAt != null)
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                        color: primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: c.card, width: 1.5)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      _submitting
                          ? const SizedBox(
                              width: 80,
                              child: Center(
                                  child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))))
                          : FilledButton(
                              onPressed: _submit,
                              style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 10)),
                              child: Text(
                                _isEditing
                                    ? 'Saqlash'
                                    : _scheduledAt != null
                                        ? 'Schedule'
                                        : _tab == _Tab.post
                                            ? 'Post'
                                            : _tab == _Tab.story
                                                ? 'Share'
                                                : _tab == _Tab.reel
                                                    ? 'Post Reel'
                                                    : 'Start Live',
                              ),
                            ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _publishUploadStatus == null
                    ? const SizedBox.shrink()
                    : Padding(
                        key: const ValueKey('create-publish-progress'),
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: PublishProgressBanner(
                              status: _publishUploadStatus!,
                              progress: _publishUploadTotal <= 0
                                  ? null
                                  : (_publishUploadDone /
                                          math.max(_publishUploadTotal, 1))
                                      .clamp(0.0, 1.0)
                                      .toDouble(),
                              failed: _publishUploadFailed,
                              onRetry: _publishUploadFailed && !_submitting
                                  ? _submit
                                  : null,
                              onCancel: _mediaUploadCancelToken != null &&
                                      !_mediaUploadCancelToken!.isCancelled
                                  ? _cancelPublish
                                  : null,
                            ),
                          ),
                        ),
                      ),
              ),
              // Content area - extends under bottom tabs
              Expanded(
                child: _buildTabContent(c, primary, profile, isMobile),
              ),
            ],
          ),
          // Bottom tabs - Floating above content (Instagram style)
          if (!_isEditing)
          Positioned(
            left: 0,
            right: 0,
            bottom: 12, // Instagram style: floating higher from bottom
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: c.card.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: c.border.withValues(alpha: 0.4),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 10,
                                spreadRadius: 0,
                                offset: const Offset(0, 4),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 6,
                                spreadRadius: 0,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              (_Tab.post, LucideIcons.fileText, 'Post'),
                              (_Tab.story, LucideIcons.userCircle, 'Story'),
                              (_Tab.reel, LucideIcons.film, 'Reel'),
                              (_Tab.live, LucideIcons.radio, 'Live'),
                            ].map((entry) {
                              final active = _tab == entry.$1;
                              final color =
                                  active ? primary : c.mutedForeground;
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                child: Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    onTap: () => _selectTab(entry.$1),
                                    borderRadius: BorderRadius.circular(12),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      curve: Curves.easeOutCubic,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: active
                                            ? c.muted
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(entry.$2,
                                              size: 18, color: color),
                                          const SizedBox(width: 6),
                                          Text(
                                            entry.$3,
                                            style: TextStyle(
                                              color: color,
                                              fontSize: 14,
                                              fontWeight: active
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(
      AlsamosColors c, Color primary, dynamic profile, bool isMobile) {
    switch (_tab) {
      case _Tab.post:
        return _buildPostTab(c, primary, profile);
      case _Tab.story:
        return _buildStoryTab(c, primary, profile);
      case _Tab.reel:
        return _buildReelTab(c, primary, profile);
      case _Tab.live:
        return _buildLiveTab(c, primary, profile);
    }
  }

  Widget _buildPreviewStage(AlsamosColors c, Color primary,
      {required String emptyTitle,
      required String emptySubtitle,
      required bool reelOnly}) {
    return CreateMediaPreviewStage(
      colors: c,
      primary: primary,
      mediaFiles: _mediaFiles,
      currentMediaIndex: _currentMediaIndex,
      aspectPresetId: _aspectPresetId,
      emptyTitle: emptyTitle,
      emptySubtitle: emptySubtitle,
      reelOnly: reelOnly,
      videoExporting: _videoExporting,
      videoExportProgress: _videoExportProgress,
      onPickImage: () => _pickMedia(),
      onPickVideo: () => _pickMedia(video: true),
      onPickFile: _pickAnyFile,
      onEditSelected: _editCurrentMedia,
      onRemoveSelected: () => _removeMedia(_currentMediaIndex),
      onMediaSelected: (index) => setState(() => _currentMediaIndex = index),
      onAspectChanged: (id) => setState(() => _aspectPresetId = id),
    );
  }

  Widget _buildIdentityRow(AlsamosColors c, Color primary, dynamic profile) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        StoryAvatarRing(
          userId: profile?.id,
          avatarUrl: profile?.avatarUrl,
          fallback: profile?.initial ?? 'U',
          size: 48,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile?.displayName ?? 'User',
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _IdentityPill(
                    icon: _visIcon(_visibility),
                    label: _visLabel(_visibility),
                    colors: c,
                    onTap: () => _showVisibilityPicker(context, c),
                    trailing: LucideIcons.chevronDown,
                  ),
                  _IdentityPill(
                    icon: LucideIcons.users,
                    label: _collaborators.isEmpty
                        ? 'Hamkor qo\'shish'
                        : '${_collaborators.length} hamkor',
                    colors: c,
                    selected: _collaborators.isNotEmpty,
                    onTap: _showCollaboratorPicker,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildComposerTextField(AlsamosColors c,
      {required String hint, int maxLength = 2200}) {
    return TextField(
      controller: _content,
      focusNode: _contentFocusNode,
      minLines: 5,
      maxLines: 12,
      maxLength: maxLength,
      style: const TextStyle(
          fontSize: 16, height: 1.45, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: c.muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.75)),
        ),
        counterStyle: TextStyle(color: c.mutedForeground, fontSize: 11),
      ),
    );
  }

  Widget _buildMetaInputs(AlsamosColors c) {
    final primary = Theme.of(context).colorScheme.primary;
    final hasGeo = _selectedLocation != null;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasGeo ? primary.withValues(alpha: 0.35) : c.border,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    hasGeo ? LucideIcons.mapPinned : LucideIcons.mapPin,
                    size: 18,
                    color: hasGeo ? primary : c.mutedForeground,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _location,
                      decoration: const InputDecoration(
                        hintText: 'Joy nomi yoki manzil...',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (_) {
                        if (_selectedLocation != null) setState(() {});
                      },
                    ),
                  ),
                  if (hasGeo)
                    IconButton(
                      tooltip: 'Joylashuvni olib tashlash',
                      onPressed: _clearSelectedLocation,
                      icon: const Icon(LucideIcons.x, size: 16),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _locatingForPost ? null : _useCurrentLocation,
                      icon: _locatingForPost
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: primary,
                              ),
                            )
                          : const Icon(LucideIcons.locateFixed, size: 15),
                      label: const Text('Hozirgi joy'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _pickLocationFromMap,
                      icon: const Icon(LucideIcons.map, size: 15),
                      label: const Text('Xaritadan'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
              if (hasGeo) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_selectedLocation!.latitude.toStringAsFixed(5)}, '
                    '${_selectedLocation!.longitude.toStringAsFixed(5)}',
                    style: TextStyle(
                      color: c.mutedForeground,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tagInput,
                decoration: InputDecoration(
                  hintText: '#heshteg qo\'shing',
                  prefixIcon: Icon(LucideIcons.hash,
                      size: 18, color: c.mutedForeground),
                  filled: true,
                  fillColor: c.muted,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onSubmitted: (_) => _addTag(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _addTag,
              style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 15)),
              child: const Text('Qo\'sh'),
            ),
          ],
        ),
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tags
                  .map((t) => Chip(
                        label: Text('#$t',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                        onDeleted: () => setState(() => _tags.remove(t)),
                        deleteIcon: const Icon(LucideIcons.x, size: 12),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 10),
        CreateCollaboratorsSection(
          collaborators: _collaborators,
          onAdd: _showCollaboratorPicker,
          onRemove: (user) => setState(() => _collaborators.remove(user)),
        ),
        const SizedBox(height: 10),
        CreateSelectedProductTagsSection(
          products: _productTags,
          onAdd: _showProductTagPicker,
          onRemove: (product) => setState(() => _productTags.remove(product)),
        ),
      ],
    );
  }

  Widget _buildFileList(AlsamosColors c) {
    if (_files.isEmpty) return const SizedBox.shrink();
    return Column(
      children: _files.asMap().entries.map((entry) {
        final i = entry.key;
        final file = entry.value;
        return _FileAttachmentTile(
          file: file,
          colors: c,
          onRemove: () => _removeFile(i),
        );
      }).toList(),
    );
  }

  Future<void> _createPoll() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) {
      AppToast.error(context, 'Avval tizimga kiring');
      return;
    }
    final poll = await PollCreator.show(context, userId: userId);
    if (poll == null || !mounted) return;
    setState(() => _poll = {
          'question': poll.question,
          'options': [
            for (var i = 0; i < poll.options.length; i++)
              poll.options[i].toJson(i),
          ],
          'duration': poll.durationCode,
          'allowMultiple': poll.allowMultiple,
          'isAnonymous': poll.isAnonymous,
          'isQuiz': poll.isQuiz,
          'resultsMode': poll.resultsMode.name,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'expiresAt': poll.closesAt.toIso8601String(),
        });
  }

  Future<void> _pickMusic() async {
    final track = await MusicPicker.show(context);
    if (track == null || !mounted) return;
    setState(() => _musicTrack = track);
  }

  // POST TAB - Support for all file types
  Widget _buildPostTab(AlsamosColors c, Color primary, dynamic profile) {
    return CreatePostTab(
      colors: c,
      primary: primary,
      preview: _buildPreviewStage(
        c,
        primary,
        emptyTitle: 'Media, hujjat yoki fayl qo\'shing',
        emptySubtitle:
            'Rasm, video, musiqa, doc, pptx, apk, exe, zip va boshqa fayllar qo\'llanadi.',
        reelOnly: false,
      ),
      identityRow: _buildIdentityRow(c, primary, profile),
      composerField:
          _buildComposerTextField(c, hint: 'Nima haqida o\'ylayapsiz?'),
      metaInputs: _buildMetaInputs(c),
      fileList: _buildFileList(c),
      scheduleLabel: _scheduledAt == null ? null : _fmtSchedule(_scheduledAt!),
      poll: _poll,
      musicTrack: _musicTrack,
      onClearSchedule: () => setState(() => _scheduledAt = null),
      onClearPoll: () => setState(() => _poll = null),
      onClearMusic: () => setState(() => _musicTrack = null),
      onPickImage: () => _pickMedia(),
      onPickVideo: () => _pickMedia(video: true),
      onPickFile: _pickAnyFile,
      onCreatePoll: _createPoll,
      onPickMusic: _pickMusic,
    );
  }

  // STORY TAB - Instagram-style story creator
  Widget _buildStoryTab(AlsamosColors c, Color primary, dynamic profile) {
    return CreateStoryTab(
      colors: c,
      primary: primary,
      selectedMedia: _mediaFiles.isEmpty ? null : _mediaFiles.first,
      contentController: _content,
      composerField: _buildComposerTextField(
        c,
        hint: 'Story caption yoki text story yozing...',
        maxLength: 500,
      ),
      backgroundColor: _storyBg,
      textSize: _storyTextSize,
      font: _storyFont,
      textAlign: _storyTextAlign,
      textPosition: _storyTextPosition,
      mentions: _storyMentions,
      musicTrack: _musicTrack,
      profileUserId: profile?.id,
      profileAvatarUrl: profile?.avatarUrl,
      profileFallback: profile?.initial ?? 'U',
      profileDisplayName: profile?.displayName ?? 'User',
      onEditMedia: _editCurrentMedia,
      onRemoveMedia: () => _removeMedia(0),
      onTextPositionChanged: (value) =>
          setState(() => _storyTextPosition = value),
      onTextAlignChanged: (value) => setState(() => _storyTextAlign = value),
      onFontChanged: (value) => setState(() => _storyFont = value),
      onTextSizeChanged: (value) => setState(() => _storyTextSize = value),
      onResetTextPosition: () =>
          setState(() => _storyTextPosition = const Offset(0.5, 0.52)),
      onBackgroundColorChanged: (value) => setState(() => _storyBg = value),
      onOpenCamera: _pickStoryCamera,
      onRecordVideo: () => _pickStoryCamera(video: true),
      onPickPhoto: _pickMedia,
      onPickVideo: () => _pickMedia(video: true),
      onPickMusic: () async {
        final track = await MusicPicker.show(context);
        if (track != null && mounted) {
          setState(() => _musicTrack = track);
        }
      },
      onUseTextMode: () => setState(_mediaFiles.clear),
      onAddMention: _showStoryMentionPicker,
      onRemoveMention: (mention) =>
          setState(() => _storyMentions.remove(mention)),
      onClearMusic: () => setState(() => _musicTrack = null),
    );
  }

  // REEL TAB - TikTok/Instagram Reels style (vertical video creator)
  Widget _buildReelTab(AlsamosColors c, Color primary, dynamic profile) {
    return CreateReelTab(
      colors: c,
      primary: primary,
      selectedMedia: _mediaFiles.isEmpty ? null : _mediaFiles.first,
      contentController: _content,
      identityRow: _buildIdentityRow(c, primary, profile),
      composerField: _buildComposerTextField(
        c,
        hint: 'Reel tavsifini yozing...',
        maxLength: 300,
      ),
      metaInputs: _buildMetaInputs(c),
      musicTrack: _musicTrack,
      profileUserId: profile?.id,
      profileAvatarUrl: profile?.avatarUrl,
      profileFallback: profile?.initial ?? 'U',
      profileUsername: profile?.username ?? 'user',
      onEditMedia: _editCurrentMedia,
      onRemoveMedia: () => _removeMedia(0),
      onPickVideo: () => _pickMedia(video: true),
      onPickMusic: () async {
        final track = await MusicPicker.show(context);
        if (track != null) {
          setState(() => _musicTrack = track);
        }
      },
      onClearMusic: () => setState(() => _musicTrack = null),
      onFocusCaption: _contentFocusNode.requestFocus,
    );
  }

  // LIVE TAB - Professional live streaming interface
  Widget _buildLiveTab(AlsamosColors c, Color primary, dynamic profile) {
    return CreateLiveTab(
      colors: c,
      primary: primary,
      identityRow: _buildIdentityRow(c, primary, profile),
      topicController: _content,
      previewText: _content.text,
      chatEnabled: _liveChatEnabled,
      reactionsEnabled: _liveReactionsEnabled,
      recordingEnabled: _liveRecordingEnabled,
      onTopicChanged: (_) => setState(() {}),
      onChatChanged: (v) => setState(() => _liveChatEnabled = v),
      onReactionsChanged: (v) => setState(() => _liveReactionsEnabled = v),
      onRecordingChanged: (v) => setState(() => _liveRecordingEnabled = v),
      onStart: _openLiveBroadcast,
    );
  }

  Future<void> _showStoryMentionPicker() async {
    _storyMentionSearch.clear();
    var loading = false;
    var results = <Map<String, dynamic>>[];
    Future<void> search(
        String query, void Function(void Function()) setSheet) async {
      final q = query.trim().replaceFirst(RegExp(r'^@'), '');
      if (q.length < 2) {
        setSheet(() => results = []);
        return;
      }
      setSheet(() => loading = true);
      try {
        final rows = await Supabase.instance.client
            .from('profiles')
            .select('id, username, display_name, avatar_url')
            .or('username.ilike.%$q%,display_name.ilike.%$q%')
            .limit(15);
        setSheet(() {
          results = (rows as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          loading = false;
        });
      } catch (_) {
        setSheet(() => loading = false);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = AlsamosColors.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setSheet) => SafeArea(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: EdgeInsets.only(
                left: 14,
                right: 14,
                top: 14,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 14,
              ),
              decoration: BoxDecoration(
                color: c.background,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: c.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.atSign,
                          color: Theme.of(ctx).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Mention qo\'shish',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: c.foreground,
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                      ),
                      IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(LucideIcons.x)),
                    ],
                  ),
                  TextField(
                    controller: _storyMentionSearch,
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(LucideIcons.search, size: 16),
                      hintText: 'Username yoki ism...',
                      filled: true,
                      fillColor: c.muted,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) => search(v, setSheet),
                    onSubmitted: (v) {
                      final raw = v.trim().replaceFirst(RegExp(r'^@'), '');
                      if (raw.isEmpty) return;
                      final mention = '@$raw';
                      if (!_storyMentions.contains(mention)) {
                        setState(() => _storyMentions.add(mention));
                      }
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: 10),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: results.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: c.border),
                        itemBuilder: (_, i) {
                          final p = results[i];
                          final username = p['username']?.toString() ?? '';
                          final display =
                              p['display_name']?.toString() ?? username;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                if (username.isEmpty) return;
                                final mention = '@$username';
                                if (!_storyMentions.contains(mention)) {
                                  setState(() => _storyMentions.add(mention));
                                }
                                Navigator.pop(ctx);
                              },
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                child: Row(
                                  children: [
                                    StoryAvatarRing(
                                      userId: p['id']?.toString(),
                                      avatarUrl: p['avatar_url']?.toString(),
                                      fallback: display.isEmpty
                                          ? 'U'
                                          : display[0].toUpperCase(),
                                      size: 36,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(display,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: c.foreground,
                                                  fontWeight: FontWeight.w700)),
                                          Text('@$username',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: c.mutedForeground,
                                                  fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showVisibilityPicker(BuildContext context, AlsamosColors c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: c.card, borderRadius: BorderRadius.circular(20)),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: c.border, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 8),
              for (final v in ['public', 'followers', 'private'])
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: Icon(_visIcon(v)),
                    title: Text(_visLabel(v)),
                    trailing: _visibility == v
                        ? Icon(LucideIcons.check,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () {
                      setState(() => _visibility = v);
                      Navigator.pop(context);
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  IconData _visIcon(String v) {
    return v == 'public'
        ? LucideIcons.globe2
        : v == 'followers'
            ? LucideIcons.users
            : LucideIcons.lock;
  }

  String _visLabel(String v) {
    return v == 'public'
        ? 'Hamma'
        : v == 'followers'
            ? 'Obunachilar'
            : 'Shaxsiy';
  }

  String _fmtSchedule(DateTime d) {
    final months = [
      'Yan',
      'Fev',
      'Mar',
      'Apr',
      'May',
      'Iyun',
      'Iyul',
      'Avg',
      'Sen',
      'Okt',
      'Noy',
      'Dek'
    ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]}, $hh:$mm';
  }
}

class _IdentityPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final AlsamosColors colors;
  final VoidCallback onTap;
  final IconData? trailing;
  final bool selected;

  const _IdentityPill({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
    this.trailing,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final accent = selected ? primary : colors.mutedForeground;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? primary.withValues(alpha: 0.10) : colors.muted,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? primary.withValues(alpha: 0.35) : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: selected ? primary : colors.mutedForeground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                Icon(trailing, size: 12, color: colors.mutedForeground),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FileAttachmentTile extends StatelessWidget {
  final _FileAttachment file;
  final AlsamosColors colors;
  final VoidCallback onRemove;

  const _FileAttachmentTile({
    required this.file,
    required this.colors,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: file.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(file.icon, color: file.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '${file.extension.toUpperCase()} · ${file.sizeFormatted}',
                  style: TextStyle(
                    color: colors.mutedForeground,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: Icon(LucideIcons.x, color: colors.mutedForeground, size: 18),
            tooltip: 'Olib tashlash',
          ),
        ],
      ),
    );
  }
}
