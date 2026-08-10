import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../shared/services/camera_capability.dart';
import '../../../../shared/utils/video_controller_lifecycle.dart';
import '../../../../shared/widgets/app_toast.dart';

/// Ports `src/components/CreateStoryDialog.tsx`.
/// Pick image/video (20MB max), preview, optional caption, upload + insert into `stories`.
class CreateStoryDialog extends ConsumerStatefulWidget {
  const CreateStoryDialog({super.key, this.onSuccess});
  final VoidCallback? onSuccess;

  static Future<void> show(BuildContext context, {VoidCallback? onSuccess}) =>
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: CreateStoryDialog(onSuccess: onSuccess),
        ),
      );

  @override
  ConsumerState<CreateStoryDialog> createState() => _CreateStoryState();
}

class _CreateStoryState extends ConsumerState<CreateStoryDialog> {
  final _client = Supabase.instance.client;
  final _picker = ImagePicker();
  final _caption = TextEditingController();
  XFile? _media;
  Uint8List? _previewBytes;
  String _type = 'image';
  VideoPlayerController? _preview;
  bool _posting = false;

  @override
  void dispose() {
    disposeVideoControllerSafely(_preview);
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (CameraCapability.shouldUseFilePickerForGallery) {
      await _pickWithFilePicker(type: 'image');
      return;
    }
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      imageQuality: 85,
    );
    if (x == null) return;
    await _setPickedMedia(x, 'image');
  }

  Future<void> _pickVideo() async {
    if (CameraCapability.shouldUseFilePickerForGallery) {
      await _pickWithFilePicker(type: 'video');
      return;
    }
    final x = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );
    if (x == null) return;
    await _setPickedMedia(x, 'video');
  }

  Future<void> _pickWithFilePicker({required String type}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      withData: true,
      allowedExtensions: type == 'video'
          ? const ['mp4', 'mov']
          : const ['jpg', 'jpeg', 'png', 'webp', 'gif'],
    );
    final file = result?.files.single;
    if (file == null) return;
    final path = file.path;
    final bytes = file.bytes;
    if (path == null && bytes == null) {
      if (mounted) AppToast.error(context, 'Faylni ochib bo\'lmadi');
      return;
    }
    await _setPickedMedia(
      path != null
          ? XFile(path, name: file.name)
          : XFile.fromData(bytes!, name: file.name),
      type,
      initialBytes: bytes,
    );
  }

  Future<void> _setPickedMedia(
    XFile media,
    String type, {
    Uint8List? initialBytes,
  }) async {
    final size = await media.length();
    if (size > 20 * 1024 * 1024) {
      if (mounted) {
        AppToast.error(context, 'Fayl hajmi 20MB dan kichik bo\'lishi kerak');
      }
      return;
    }
    final bytes = initialBytes ?? await media.readAsBytes();
    VideoPlayerController? controller;
    if (type == 'video' && media.path.isNotEmpty) {
      final uri = kIsWeb ? Uri.parse(media.path) : Uri.file(media.path);
      controller = VideoPlayerController.networkUrl(uri)..setLooping(true);
      await controller.initialize();
      await controller.play();
    }
    if (!mounted) {
      disposeVideoControllerSafely(controller);
      return;
    }
    setState(() {
      disposeVideoControllerSafely(_preview);
      _media = media;
      _previewBytes = bytes;
      _type = type;
      _preview = controller;
    });
  }

  void _clear() {
    setState(() {
      _media = null;
      _previewBytes = null;
      _caption.clear();
      disposeVideoControllerSafely(_preview);
      _preview = null;
    });
  }

  Future<void> _post() async {
    final me = ref.read(authProvider).user?.id;
    final media = _media;
    final bytes = _previewBytes;
    if (me == null || media == null || bytes == null) return;
    setState(() => _posting = true);
    try {
      final ext =
          _extensionFor(media.name.isNotEmpty ? media.name : media.path);
      final key = '$me/stories/${DateTime.now().millisecondsSinceEpoch}.$ext';
      final storage = _client.storage.from('message-attachments');
      await storage.uploadBinary(
        key,
        bytes,
        fileOptions: FileOptions(
          upsert: false,
          contentType: _contentTypeFor(ext, _type),
        ),
      );
      final url = storage.getPublicUrl(key);
      await _client.from('stories').insert({
        'user_id': me,
        'media_url': url,
        'media_type': _type,
        'caption': _caption.text.isEmpty ? null : _caption.text,
        'expires_at':
            DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.success(context, 'Story joylandi!');
      widget.onSuccess?.call();
    } catch (error) {
      if (mounted) {
        AppToast.error(context, 'Story joylab bo\'lmadi', error: error);
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  String _extensionFor(String value) {
    final clean = value.split('?').first;
    final ext = clean.contains('.') ? clean.split('.').last.toLowerCase() : '';
    if (ext.isNotEmpty && ext.length <= 5) return ext;
    return _type == 'video' ? 'mp4' : 'jpg';
  }

  String _contentTypeFor(String ext, String type) {
    if (type == 'video') {
      return ext == 'mov' ? 'video/quicktime' : 'video/mp4';
    }
    return switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: c.border)),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: c.border,
                        borderRadius: BorderRadius.circular(2)))),
            const Text('Create story',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (_media == null)
              Row(children: [
                Expanded(
                    child:
                        _pickerBtn(c, LucideIcons.image, 'Photo', _pickImage)),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        _pickerBtn(c, LucideIcons.film, 'Video', _pickVideo)),
              ])
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: Stack(children: [
                    Container(color: Colors.black),
                    if (_type == 'video' && _preview != null)
                      Center(
                          child: AspectRatio(
                              aspectRatio: _preview!.value.aspectRatio,
                              child: VideoPlayer(_preview!)))
                    else
                      Center(
                          child: Image.memory(_previewBytes!,
                              fit: BoxFit.contain)),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: _clear,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(LucideIcons.x,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _caption,
                decoration: InputDecoration(
                  hintText: 'Add a caption\u2026',
                  isDense: true,
                  filled: true,
                  fillColor: c.muted.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: c.border)),
                ),
                maxLength: 200,
              ),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'))),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _media == null || _posting ? null : _post,
                  style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary),
                  child: _posting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Post story'),
                ),
              ),
            ]),
          ]),
    );
  }

  Widget _pickerBtn(
      AlsamosColors c, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border)),
        alignment: Alignment.center,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 24),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}
