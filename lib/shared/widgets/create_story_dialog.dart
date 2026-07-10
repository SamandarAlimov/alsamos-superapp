import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'dart:io';

import '../../app/theme/app_theme.dart';
import '../../app/theme/app_colors.dart';

/// v44: CreateStoryDialog — full form ported from web CreateStoryDialog.
/// Media pick (image/video) → text overlay → color picker → privacy → post.
enum StoryPrivacy { everyone, closeFriends, onlyMe }

extension on StoryPrivacy {
  String get label => switch (this) {
        StoryPrivacy.everyone => 'Hamma',
        StoryPrivacy.closeFriends => 'Yaqin do\'stlar',
        StoryPrivacy.onlyMe => 'Faqat men',
      };
  IconData get icon => switch (this) {
        StoryPrivacy.everyone => LucideIcons.globe,
        StoryPrivacy.closeFriends => LucideIcons.star,
        StoryPrivacy.onlyMe => LucideIcons.lock,
      };
}

class StoryResult {
  final String mediaPath;
  final String mediaType; // 'image' | 'video'
  final String? overlayText;
  final Color overlayBg;
  final StoryPrivacy privacy;
  const StoryResult({
    required this.mediaPath,
    required this.mediaType,
    this.overlayText,
    required this.overlayBg,
    required this.privacy,
  });
}

class CreateStoryDialog {
  static Future<StoryResult?> show(
    BuildContext context, {
    Future<bool> Function(StoryResult result)? onPost,
  }) {
    return Navigator.of(context).push<StoryResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CreateStoryPage(onPost: onPost),
      ),
    );
  }
}

class _CreateStoryPage extends StatefulWidget {
  final Future<bool> Function(StoryResult)? onPost;
  const _CreateStoryPage({this.onPost});
  @override
  State<_CreateStoryPage> createState() => _CreateStoryPageState();
}

class _CreateStoryPageState extends State<_CreateStoryPage> {
  XFile? _media;
  String _mediaType = 'image';
  final _text = TextEditingController();
  StoryPrivacy _privacy = StoryPrivacy.everyone;
  bool _posting = false;

  static const _palette = <Color>[
    Color(0xFF111827), // slate
    AppColors.alsamosOrange,
    Color(0xFFEC4899), // pink
    Color(0xFF8B5CF6), // violet
    Color(0xFF22C55E), // green
    Color(0xFF3B82F6), // blue
  ];
  Color _bg = const Color(0xFF111827);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick(bool isVideo) async {
    final picker = ImagePicker();
    final XFile? f = isVideo
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (f != null && mounted) {
      setState(() {
        _media = f;
        _mediaType = isVideo ? 'video' : 'image';
      });
    }
  }

  Future<void> _post() async {
    if (_media == null || _posting) return;
    setState(() => _posting = true);
    final result = StoryResult(
      mediaPath: _media!.path,
      mediaType: _mediaType,
      overlayText: _text.text.trim().isEmpty ? null : _text.text.trim(),
      overlayBg: _bg,
      privacy: _privacy,
    );
    final ok = await (widget.onPost?.call(result) ?? Future.value(true));
    if (!mounted) return;
    setState(() => _posting = false);
    if (ok) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          tooltip: 'Yopish',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Hikoya yaratish'),
        actions: [
          TextButton(
            onPressed: (_media != null && !_posting) ? _post : null,
            child: Text(
              _posting ? '...' : 'Joylash',
              style: TextStyle(
                color: (_media != null && !_posting)
                    ? AppColors.alsamosOrange
                    : Colors.white38,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Media preview / picker
          AspectRatio(
            aspectRatio: 9 / 16,
            child: Container(
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_media != null && _mediaType == 'image')
                      Image.file(File(_media!.path), fit: BoxFit.cover)
                    else if (_media != null && _mediaType == 'video')
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: Icon(LucideIcons.video,
                              color: Colors.white70, size: 60),
                        ),
                      )
                    else
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(LucideIcons.imagePlus,
                                color: Colors.white60, size: 48),
                            SizedBox(height: 8),
                            Text('Media tanlang',
                                style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                    if (_text.text.trim().isNotEmpty)
                      Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 24),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _text.text,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                              shadows: [
                                Shadow(blurRadius: 4, color: Colors.black54),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(false),
                  icon: const Icon(LucideIcons.image, size: 18),
                  label: const Text('Rasm'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(true),
                  icon: const Icon(LucideIcons.video, size: 18),
                  label: const Text('Video'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Text overlay
          TextField(
            controller: _text,
            style: const TextStyle(color: Colors.white),
            maxLength: 80,
            decoration: InputDecoration(
              hintText: 'Matn qo\'shing…',
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(LucideIcons.type, color: Colors.white70),
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          // Color palette
          const SizedBox(height: 8),
          const Text('Fon rangi',
              style: TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _palette.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final col = _palette[i];
                final sel = col.toARGB32() == _bg.toARGB32();
                return GestureDetector(
                  onTap: () => setState(() => _bg = col),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: col,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sel ? Colors.white : Colors.white24,
                        width: sel ? 3 : 1,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // Privacy
          const Text('Maxfiylik',
              style: TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Column(
            children: StoryPrivacy.values.map((p) {
              final sel = p == _privacy;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: sel ? Colors.white12 : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: sel ? AppColors.alsamosOrange : Colors.white24,
                  ),
                ),
                // ignore: deprecated_member_use
                child: RadioListTile<StoryPrivacy>(
                  value: p,
                  // ignore: deprecated_member_use
                  groupValue: _privacy,
                  activeColor: AppColors.alsamosOrange,
                  // ignore: deprecated_member_use
                  onChanged: (v) => setState(() => _privacy = v ?? _privacy),
                  title: Row(
                    children: [
                      Icon(p.icon,
                          size: 16,
                          color: sel
                              ? AppColors.alsamosOrange
                              : Colors.white70),
                      const SizedBox(width: 8),
                      Text(p.label,
                          style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                  dense: true,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Info
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: const [
                Icon(LucideIcons.info, color: Colors.white60, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hikoya 24 soatdan keyin avtomatik o\'chiriladi.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
