import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Ports `src/components/CreateStoryDialog.tsx`.
/// Pick image/video (20MB max), preview, optional caption, upload + insert into `stories`.
class CreateStoryDialog extends ConsumerStatefulWidget {
  const CreateStoryDialog({super.key, this.onSuccess});
  final VoidCallback? onSuccess;

  static Future<void> show(BuildContext context, {VoidCallback? onSuccess}) => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
  File? _file;
  String _type = 'image';
  VideoPlayerController? _preview;
  bool _posting = false;

  @override
  void dispose() {
    _preview?.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 2048, imageQuality: 85);
    if (x == null) return;
    final f = File(x.path);
    if (await f.length() > 20 * 1024 * 1024) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File size must be less than 20MB')));
      return;
    }
    setState(() { _file = f; _type = 'image'; _preview?.dispose(); _preview = null; });
  }

  Future<void> _pickVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60));
    if (x == null) return;
    final f = File(x.path);
    if (await f.length() > 20 * 1024 * 1024) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File size must be less than 20MB')));
      return;
    }
    final v = VideoPlayerController.file(f)..setLooping(true);
    await v.initialize();
    await v.play();
    if (!mounted) return;
    setState(() { _file = f; _type = 'video'; _preview = v; });
  }

  void _clear() {
    setState(() {
      _file = null;
      _caption.clear();
      _preview?.dispose();
      _preview = null;
    });
  }

  Future<void> _post() async {
    final me = ref.read(authProvider).user?.id;
    if (me == null || _file == null) return;
    setState(() => _posting = true);
    try {
      final ext = _file!.path.split('.').last.toLowerCase();
      final key = 'stories/$me/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _client.storage.from('media').upload(key, _file!, fileOptions: const FileOptions(upsert: false));
      final url = _client.storage.from('media').getPublicUrl(key);
      await _client.from('stories').insert({
        'user_id': me,
        'media_url': url,
        'media_type': _type,
        'caption': _caption.text.isEmpty ? null : _caption.text,
        'expires_at': DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Story posted!')));
      widget.onSuccess?.call();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to post story')));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(color: c.card, borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), border: Border.all(color: c.border)),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(margin: const EdgeInsets.only(bottom: 8), width: 40, height: 4, decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)))),
        const Text('Create story', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        if (_file == null)
          Row(children: [
            Expanded(child: _pickerBtn(c, LucideIcons.image, 'Photo', _pickImage)),
            const SizedBox(width: 8),
            Expanded(child: _pickerBtn(c, LucideIcons.film, 'Video', _pickVideo)),
          ])
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: Stack(children: [
                Container(color: Colors.black),
                if (_type == 'video' && _preview != null)
                  Center(child: AspectRatio(aspectRatio: _preview!.value.aspectRatio, child: VideoPlayer(_preview!)))
                else
                  Center(child: Image.file(_file!, fit: BoxFit.contain)),
                Positioned(
                  top: 8, right: 8,
                  child: GestureDetector(
                    onTap: _clear,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(LucideIcons.x, color: Colors.white, size: 18),
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
            ),
            maxLength: 200,
          ),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: _file == null || _posting ? null : _post,
              style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.primary),
              child: _posting ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Post story'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _pickerBtn(AlsamosColors c, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 100,
        decoration: BoxDecoration(color: c.muted.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
        alignment: Alignment.center,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 24),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}
