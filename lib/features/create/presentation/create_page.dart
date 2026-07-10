import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../data/create_repository.dart';
import 'widgets/schedule_post_dialog.dart';
import 'widgets/poll_creator.dart';
import 'widgets/music_picker.dart';
import 'pages/live_stream_page.dart';

final createRepositoryProvider = Provider((ref) => const CreateRepository());

enum _Tab { post, story, reel, live }

class _AspectPreset {
  final String id;
  final String label;
  final double? ratio;
  final IconData icon;

  const _AspectPreset(this.id, this.label, this.ratio, this.icon);
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
  const CreatePage({super.key});
  @override
  ConsumerState<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends ConsumerState<CreatePage> {
  final _content = TextEditingController();
  final _location = TextEditingController();
  final _tagInput = TextEditingController();
  _Tab _tab = _Tab.post;
  String _visibility = 'public';
  final List<String> _tags = [];
  final List<_FileAttachment> _files = [];
  final List<XFile> _mediaFiles = []; // For quick image/video picker
  int _currentMediaIndex = 0;
  String _aspectPresetId = 'original';
  bool _submitting = false;
  DateTime? _scheduledAt;
  Map<String, dynamic>? _poll;
  String? _musicTrack;
  bool _liveChatEnabled = true;
  bool _liveReactionsEnabled = true;
  bool _liveRecordingEnabled = false;
  // Story-only state
  Color _storyBg = const Color(0xFFF97316);
  static const _storyPalette = [
    Color(0xFFF97316),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF3B82F6),
    Color(0xFF06B6D4),
    Color(0xFF22C55E),
    Color(0xFFEAB308),
    Color(0xFF111827),
  ];

  static const _aspectPresets = <_AspectPreset>[
    _AspectPreset('original', 'Original', null, LucideIcons.maximize2),
    _AspectPreset('1:1', '1:1', 1, LucideIcons.square),
    _AspectPreset('4:5', '4:5', 4 / 5, LucideIcons.rectangleVertical),
    _AspectPreset('3:4', '3:4', 3 / 4, LucideIcons.rectangleVertical),
    _AspectPreset('16:9', '16:9', 16 / 9, LucideIcons.rectangleHorizontal),
    _AspectPreset('9:16', '9:16', 9 / 16, LucideIcons.smartphone),
  ];

  _AspectPreset get _selectedAspect => _aspectPresets.firstWhere(
        (p) => p.id == _aspectPresetId,
        orElse: () => _aspectPresets.first,
      );

  @override
  void dispose() {
    _content.dispose();
    _location.dispose();
    _tagInput.dispose();
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
    final picker = ImagePicker();
    if (video) {
      final v = await picker.pickVideo(source: ImageSource.gallery);
      if (v != null) {
        setState(() {
          if (_tab != _Tab.post) _mediaFiles.clear();
          if (_mediaFiles.length < 10) {
            _mediaFiles.add(v);
            _currentMediaIndex = _mediaFiles.length - 1;
          }
        });
      }
    } else {
      final imgs = await picker.pickMultiImage(imageQuality: 85);
      if (imgs.isNotEmpty) {
        setState(() {
          if (_tab != _Tab.post) _mediaFiles.clear();
          for (final img in imgs) {
            if (_mediaFiles.length < 10) {
              _mediaFiles.add(img);
              _currentMediaIndex = _mediaFiles.length - 1;
            }
          }
        });
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

  Future<List<String>> _uploadMedia(String userId) async {
    final supabase = Supabase.instance.client;
    final storage = supabase.storage.from('message-attachments');
    final urls = <String>[];
    for (final xf in _mediaFiles) {
      final file = File(xf.path);
      final ext = xf.path.split('.').last;
      final path =
          '$userId/post-${DateTime.now().millisecondsSinceEpoch}-${urls.length}.$ext';
      if (await file.exists()) {
        await storage.upload(path, file);
      } else {
        await storage.uploadBinary(path, await xf.readAsBytes());
      }
      urls.add(storage.getPublicUrl(path));
    }
    // Also upload all other files
    for (final fa in _files) {
      final file = fa.path == null ? null : File(fa.path!);
      final ext = fa.extension.isEmpty ? 'bin' : fa.extension;
      final path =
          '$userId/post-${DateTime.now().millisecondsSinceEpoch}-${urls.length}.$ext';
      if (file != null && await file.exists()) {
        await storage.upload(path, file);
      } else if (fa.bytes != null) {
        await storage.uploadBinary(path, fa.bytes!);
      } else {
        continue;
      }
      urls.add(storage.getPublicUrl(path));
    }
    return urls;
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
    if (_poll != null) {
      return 'poll';
    }
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

  String _finalContent() {
    var content = _content.text.trim();
    if (_poll != null) {
      content = '[POLL]$_poll[/POLL]\n$content'.trim();
    }
    if (_musicTrack != null) {
      content = '[MUSIC:$_musicTrack]\n$content'.trim();
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

  Future<void> _submit() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    if (_tab == _Tab.live) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LiveStreamPage()),
      );
      return;
    }

    if (_tab == _Tab.reel &&
        (_mediaFiles.isEmpty || !_isVideoPath(_mediaFiles.first.path))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reel uchun video tanlang')),
      );
      return;
    }

    if (_tab == _Tab.story &&
        _content.text.trim().isEmpty &&
        _mediaFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Story uchun rasm, video yoki matn qo\'shing')),
      );
      return;
    }

    if (_tab == _Tab.post &&
        _content.text.trim().isEmpty &&
        _mediaFiles.isEmpty &&
        _files.isEmpty &&
        _poll == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Iltimos, matn yoki fayl qo\'shing')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final content = _finalContent();

      final mediaUrls = (_mediaFiles.isNotEmpty || _files.isNotEmpty)
          ? await _uploadMedia(userId)
          : <String>[];

      if (_tab == _Tab.story) {
        await Supabase.instance.client.from('stories').insert({
          'user_id': userId,
          'media_url': mediaUrls.isEmpty ? null : mediaUrls.first,
          'media_type': mediaUrls.isEmpty
              ? 'text'
              : (_mediaFiles.isNotEmpty && _isVideoPath(_mediaFiles.first.path)
                  ? 'video'
                  : 'image'),
          'caption': content.isEmpty ? null : content,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Story joylandi!')),
          );
          context.go('/home');
        }
        return;
      }

      await ref.read(createRepositoryProvider).createPost(
            userId: userId,
            content: content,
            visibility: _visibility,
            mediaUrls: mediaUrls,
            mediaType: _mediaTypeForPublish(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(_tab == _Tab.reel ? 'Reel joylandi!' : 'Post joylandi!')));
        context.go(_tab == _Tab.reel ? '/videos' : '/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Xatolik: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final profile = ref.watch(authProvider).profile;
    final isMobile = MediaQuery.sizeOf(context).width < 768;

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
                          _tab == _Tab.post
                              ? 'New post'
                              : _tab == _Tab.story
                                  ? 'New story'
                                  : _tab == _Tab.reel
                                      ? 'New reel'
                                      : 'Go live',
                          style: const TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              fontWeight: FontWeight.bold,
                              fontSize: 18),
                        ),
                      ),
                      // Schedule button (only for post tab)
                      if (_tab == _Tab.post)
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
                                _scheduledAt != null
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
              // Content area - extends under bottom tabs
              Expanded(
                child: _buildTabContent(c, primary, profile, isMobile),
              ),
            ],
          ),
          // Bottom tabs - Floating above content (Instagram style)
          Positioned(
            left: 8,
            right: 8,
            bottom: 12, // Instagram style: floating higher from bottom
            child: SafeArea(
              top: false,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          (_Tab.post, LucideIcons.fileText, 'Post'),
                          (_Tab.story, LucideIcons.userCircle, 'Story'),
                          (_Tab.reel, LucideIcons.film, 'Reel'),
                          (_Tab.live, LucideIcons.radio, 'Live'),
                        ].map((entry) {
                          final active = _tab == entry.$1;
                          final color = active ? primary : c.mutedForeground;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                onTap: () => _selectTab(entry.$1),
                                borderRadius: BorderRadius.circular(12),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOutCubic,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color:
                                        active ? c.muted : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(entry.$2, size: 18, color: color),
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
    final selectedIndex = _mediaFiles.isEmpty
        ? 0
        : _currentMediaIndex.clamp(0, _mediaFiles.length - 1).toInt();
    final selected = _mediaFiles.isEmpty ? null : _mediaFiles[selectedIndex];
    final aspect = _selectedAspect.ratio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: selected == null
              ? _EmptyMediaStage(
                  title: emptyTitle,
                  subtitle: emptySubtitle,
                  primary: primary,
                  onImage: reelOnly ? null : () => _pickMedia(),
                  onVideo: () => _pickMedia(video: true),
                  onFile: reelOnly ? null : _pickAnyFile,
                )
              : _LocalMediaFrame(
                  file: selected,
                  aspectRatio: aspect,
                  forceReel: reelOnly,
                  onRemove: () => _removeMedia(_currentMediaIndex),
                ),
        ),
        const SizedBox(height: 14),
        _buildAspectSelector(c, primary, reelOnly: reelOnly),
        if (_mediaFiles.length > 1) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _mediaFiles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _MediaThumb(
                file: _mediaFiles[i],
                selected: i == _currentMediaIndex,
                onTap: () => setState(() => _currentMediaIndex = i),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAspectSelector(AlsamosColors c, Color primary,
      {required bool reelOnly}) {
    final presets = reelOnly
        ? _aspectPresets
            .where((p) => p.id == '9:16' || p.id == 'original')
            .toList()
        : _aspectPresets;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: presets.map((preset) {
          final selected = preset.id == _aspectPresetId;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selected,
              showCheckmark: false,
              avatar: Icon(
                preset.icon,
                size: 15,
                color: selected ? Colors.white : c.mutedForeground,
              ),
              label: Text(preset.label),
              onSelected: (_) => setState(() => _aspectPresetId = preset.id),
              selectedColor: primary,
              backgroundColor: c.card,
              side: BorderSide(color: selected ? primary : c.border),
              labelStyle: TextStyle(
                color: selected ? Colors.white : c.foreground,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildIdentityRow(AlsamosColors c, Color primary, dynamic profile) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        UserAvatar(
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
              GestureDetector(
                onTap: () => _showVisibilityPicker(context, c),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: c.muted,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_visIcon(_visibility),
                          size: 13, color: c.mutedForeground),
                      const SizedBox(width: 6),
                      Text(
                        _visLabel(_visibility),
                        style: TextStyle(
                            fontSize: 12,
                            color: c.mutedForeground,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      Icon(LucideIcons.chevronDown,
                          size: 12, color: c.mutedForeground),
                    ],
                  ),
                ),
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
    return Column(
      children: [
        TextField(
          controller: _location,
          decoration: InputDecoration(
            hintText: 'Joylashuvni qo\'shish...',
            prefixIcon:
                Icon(LucideIcons.mapPin, size: 18, color: c.mutedForeground),
            filled: true,
            fillColor: c.muted,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
      ],
    );
  }

  Widget _buildToolTray(AlsamosColors c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _MediaChip(
            icon: LucideIcons.image,
            label: 'Rasm',
            color: const Color(0xFF22C55E),
            onTap: () => _pickMedia(),
          ),
          _MediaChip(
            icon: LucideIcons.video,
            label: 'Video',
            color: const Color(0xFF3B82F6),
            onTap: () => _pickMedia(video: true),
          ),
          _MediaChip(
            icon: LucideIcons.fileArchive,
            label: 'Fayl',
            color: const Color(0xFF8B5CF6),
            onTap: _pickAnyFile,
          ),
          _MediaChip(
            icon: LucideIcons.barChart3,
            label: 'So\'rovnoma',
            color: const Color(0xFFEC4899),
            onTap: () async {
              final poll = await PollCreator.show(context);
              if (poll != null) {
                setState(() => _poll = {
                      'question': poll.question,
                      'options': poll.options,
                      'duration': poll.duration.name,
                      'allowMultiple': poll.allowMultiple,
                    });
              }
            },
          ),
          _MediaChip(
            icon: LucideIcons.music,
            label: 'Musiqa',
            color: const Color(0xFFEAB308),
            onTap: () async {
              final track = await MusicPicker.show(context);
              if (track != null) {
                setState(() => _musicTrack =
                    '${track.title}${track.artist != null ? ' - ${track.artist}' : ''}');
              }
            },
          ),
        ],
      ),
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

  // POST TAB - Support for all file types
  Widget _buildPostTab(AlsamosColors c, Color primary, dynamic profile) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildIdentityRow(c, primary, profile),
            const SizedBox(height: 16),
            _buildComposerTextField(c, hint: 'Nima haqida o\'ylayapsiz?'),
            if (_scheduledAt != null) _buildScheduleBanner(c, primary),
            if (_poll != null) _buildPollBanner(c),
            if (_musicTrack != null) _buildMusicBanner(c),
            const SizedBox(height: 12),
            _buildMetaInputs(c),
            const SizedBox(height: 14),
            _buildFileList(c),
            const SizedBox(height: 14),
            _buildToolTray(c),
          ],
        );

        final preview = _buildPreviewStage(
          c,
          primary,
          emptyTitle: 'Media, hujjat yoki fayl qo\'shing',
          emptySubtitle:
              'Rasm, video, musiqa, doc, pptx, apk, exe, zip va boshqa fayllar qo\'llanadi.',
          reelOnly: false,
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: preview),
                        const SizedBox(width: 28),
                        Expanded(flex: 5, child: details),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        preview,
                        const SizedBox(height: 24),
                        details,
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  // STORY TAB - Instagram-style story creator
  Widget _buildStoryTab(AlsamosColors c, Color primary, dynamic profile) {
    final selected = _mediaFiles.isEmpty ? null : _mediaFiles.first;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 820;
              final preview = Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: selected == null ? _storyBg : Colors.black,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 30,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (selected != null)
                              _LocalMediaFrame(
                                file: selected,
                                aspectRatio: 9 / 16,
                                forceReel: true,
                                onRemove: () => _removeMedia(0),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.all(28),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      _storyBg,
                                      Color.lerp(_storyBg, Colors.black, 0.28)!,
                                    ],
                                  ),
                                ),
                                child: Text(
                                  _content.text.trim().isEmpty
                                      ? 'Story matni shu yerda ko\'rinadi'
                                      : _content.text.trim(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    height: 1.25,
                                    shadows: [
                                      Shadow(
                                          color: Colors.black54,
                                          blurRadius: 10,
                                          offset: Offset(0, 3)),
                                    ],
                                  ),
                                ),
                              ),
                            Positioned(
                              left: 14,
                              right: 14,
                              top: 14,
                              child: Row(
                                children: [
                                  UserAvatar(
                                    avatarUrl: profile?.avatarUrl,
                                    fallback: profile?.initial ?? 'U',
                                    size: 34,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    profile?.displayName ?? 'User',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800),
                                  ),
                                  const Spacer(),
                                  const Icon(LucideIcons.moreHorizontal,
                                      color: Colors.white),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );

              final controls = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildComposerTextField(c,
                      hint: 'Story caption yoki text story yozing...',
                      maxLength: 500),
                  const SizedBox(height: 14),
                  Text('Fon rangi',
                      style: TextStyle(
                          color: c.mutedForeground,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _storyPalette.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) {
                        final color = _storyPalette[i];
                        final active = color.toARGB32() == _storyBg.toARGB32();
                        return GestureDetector(
                          onTap: () => setState(() => _storyBg = color),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: active ? Colors.white : c.border,
                                  width: active ? 3 : 1),
                              boxShadow: active
                                  ? [
                                      BoxShadow(
                                          color: color.withValues(alpha: 0.45),
                                          blurRadius: 16,
                                          offset: const Offset(0, 6))
                                    ]
                                  : null,
                            ),
                            child: active
                                ? const Icon(LucideIcons.check,
                                    color: Colors.white, size: 20)
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.border),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MediaChip(
                            icon: LucideIcons.image,
                            label: 'Photo',
                            color: const Color(0xFF22C55E),
                            onTap: () => _pickMedia()),
                        _MediaChip(
                            icon: LucideIcons.video,
                            label: 'Video',
                            color: const Color(0xFF3B82F6),
                            onTap: () => _pickMedia(video: true)),
                        _MediaChip(
                          icon: LucideIcons.music,
                          label: 'Music',
                          color: const Color(0xFFEC4899),
                          onTap: () async {
                            final track = await MusicPicker.show(context);
                            if (track != null) {
                              setState(() => _musicTrack =
                                  '${track.title}${track.artist != null ? ' - ${track.artist}' : ''}');
                            }
                          },
                        ),
                        _MediaChip(
                            icon: LucideIcons.type,
                            label: 'Text',
                            color: const Color(0xFFF97316),
                            onTap: () => setState(() => _mediaFiles.clear())),
                      ],
                    ),
                  ),
                  if (_musicTrack != null) ...[
                    const SizedBox(height: 12),
                    _buildMusicBanner(c),
                  ],
                ],
              );

              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: preview),
                        const SizedBox(width: 32),
                        Expanded(child: controls),
                      ],
                    )
                  : Column(
                      children: [
                        preview,
                        const SizedBox(height: 24),
                        controls,
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }

  // REEL TAB - TikTok/Instagram Reels style (vertical video creator)
  Widget _buildReelTab(AlsamosColors c, Color primary, dynamic profile) {
    final selected = _mediaFiles.isEmpty ? null : _mediaFiles.first;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1020),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 860;
              final preview = Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: c.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 34,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: selected == null
                          ? _EmptyMediaStage(
                              title: 'Reel video tanlang',
                              subtitle:
                                  'Instagramdek 9:16 qisqa video. Keyin brend nomini shu oqimga bog\'laymiz.',
                              primary: primary,
                              onVideo: () => _pickMedia(video: true),
                            )
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                _LocalMediaFrame(
                                  file: selected,
                                  aspectRatio: 9 / 16,
                                  forceReel: true,
                                  onRemove: () => _removeMedia(0),
                                ),
                                Positioned(
                                  left: 14,
                                  right: 72,
                                  bottom: 18,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          UserAvatar(
                                            avatarUrl: profile?.avatarUrl,
                                            fallback: profile?.initial ?? 'U',
                                            size: 34,
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              '@${profile?.username ?? 'user'}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                color: Colors.white70,
                                              ),
                                            ),
                                            child: const Text(
                                              'Follow',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        _content.text.trim().isEmpty
                                            ? 'Reel tavsifi shu yerda ko\'rinadi'
                                            : _content.text.trim(),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          height: 1.25,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black54,
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_musicTrack != null) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(
                                              LucideIcons.music,
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                _musicTrack!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Positioned(
                                  right: 12,
                                  bottom: 24,
                                  child: Column(
                                    children: const [
                                      _ReelActionIcon(icon: LucideIcons.heart),
                                      _ReelActionIcon(
                                          icon: LucideIcons.messageCircle),
                                      _ReelActionIcon(icon: LucideIcons.send),
                                      _ReelActionIcon(
                                          icon: LucideIcons.repeat2),
                                      _ReelActionIcon(
                                          icon: LucideIcons.bookmark),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              );

              final controls = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildIdentityRow(c, primary, profile),
                  const SizedBox(height: 16),
                  _buildComposerTextField(
                    c,
                    hint: 'Reel tavsifini yozing...',
                    maxLength: 300,
                  ),
                  if (_musicTrack != null) _buildMusicBanner(c),
                  const SizedBox(height: 10),
                  _buildMetaInputs(c),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.border),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MediaChip(
                          icon: LucideIcons.upload,
                          label: selected == null
                              ? 'Video yuklash'
                              : 'Video almashtirish',
                          color: const Color(0xFF3B82F6),
                          onTap: () => _pickMedia(video: true),
                        ),
                        _MediaChip(
                          icon: LucideIcons.music,
                          label: 'Musiqa',
                          color: const Color(0xFFEC4899),
                          onTap: () async {
                            final track = await MusicPicker.show(context);
                            if (track != null) {
                              setState(() => _musicTrack =
                                  '${track.title}${track.artist != null ? ' - ${track.artist}' : ''}');
                            }
                          },
                        ),
                        _MediaChip(
                          icon: LucideIcons.captions,
                          label: 'Caption',
                          color: const Color(0xFFF97316),
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                ],
              );

              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: preview),
                        const SizedBox(width: 34),
                        Expanded(child: controls),
                      ],
                    )
                  : Column(
                      children: [
                        preview,
                        const SizedBox(height: 24),
                        controls,
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }

  // LIVE TAB - Professional live streaming interface
  Widget _buildLiveTab(AlsamosColors c, Color primary, dynamic profile) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 880;
              final preview = Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: c.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 32,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF111827),
                              Color(0xFF020617),
                              Color(0xFF1C0F06),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(painter: _LiveGridPainter()),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: 0.16),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: primary.withValues(alpha: 0.45),
                                  width: 2,
                                ),
                              ),
                              child: Icon(LucideIcons.radioTower,
                                  color: primary, size: 34),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Live preview',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _content.text.trim().isEmpty
                                  ? 'Mavzu kiritilganda shu yerda ko\'rinadi'
                                  : _content.text.trim(),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 16,
                        top: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.radio,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 6),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 16,
                        top: 16,
                        child: Row(
                          children: [
                            _LivePill(
                              icon: LucideIcons.users,
                              label: '0',
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            _LivePill(
                              icon: LucideIcons.messageCircle,
                              label: _liveChatEnabled ? 'Chat' : 'Off',
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );

              final controls = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildIdentityRow(c, primary, profile),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _content,
                    maxLength: 150,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Live efir mavzusini kiriting...',
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
                      counterStyle:
                          TextStyle(color: c.mutedForeground, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      children: [
                        _LiveSwitchTile(
                          icon: LucideIcons.messageCircle,
                          title: 'Jonli chat',
                          subtitle: 'Tomoshabinlar yozishi mumkin',
                          value: _liveChatEnabled,
                          onChanged: (v) =>
                              setState(() => _liveChatEnabled = v),
                          colors: c,
                        ),
                        Divider(height: 1, color: c.border),
                        _LiveSwitchTile(
                          icon: LucideIcons.heart,
                          title: 'Reaksiyalar',
                          subtitle: 'Like va real-time reaksiyalar',
                          value: _liveReactionsEnabled,
                          onChanged: (v) =>
                              setState(() => _liveReactionsEnabled = v),
                          colors: c,
                        ),
                        Divider(height: 1, color: c.border),
                        _LiveSwitchTile(
                          icon: LucideIcons.clapperboard,
                          title: 'Yozib olish',
                          subtitle: 'Live tugagach replay saqlanadi',
                          value: _liveRecordingEnabled,
                          onChanged: (v) =>
                              setState(() => _liveRecordingEnabled = v),
                          colors: c,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      children: [
                        _LiveFeatureItem(
                          icon: LucideIcons.shieldCheck,
                          title: 'Xavfsiz efir',
                          subtitle: 'Moderatorlar va report oqimi tayyor',
                          c: c,
                        ),
                        const SizedBox(height: 14),
                        _LiveFeatureItem(
                          icon: LucideIcons.radioTower,
                          title: 'Past kechikish',
                          subtitle: 'Tomoshabinlar bilan tez muloqot',
                          c: c,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const LiveStreamPage()),
                      ),
                      icon: const Icon(LucideIcons.radio, size: 22),
                      label: const Text(
                        'Efirni boshlash',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              );

              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: preview),
                        const SizedBox(width: 34),
                        Expanded(flex: 5, child: controls),
                      ],
                    )
                  : Column(
                      children: [
                        preview,
                        const SizedBox(height: 24),
                        controls,
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }

  // Helper methods and banners
  Widget _buildScheduleBanner(AlsamosColors c, Color primary) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(LucideIcons.calendar, size: 16, color: primary),
        const SizedBox(width: 8),
        Expanded(
            child: Text(
          'Rejalashtirilgan: ${_fmtSchedule(_scheduledAt!)}',
          style: TextStyle(
              fontSize: 13, color: primary, fontWeight: FontWeight.w600),
        )),
        GestureDetector(
          onTap: () => setState(() => _scheduledAt = null),
          child: Icon(LucideIcons.x, size: 16, color: primary),
        ),
      ]),
    );
  }

  Widget _buildPollBanner(AlsamosColors c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        const Icon(LucideIcons.barChart3, size: 16, color: Color(0xFF8B5CF6)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(
          'So\'rovnoma: ${_poll!['question'] ?? ''} (${(_poll!['options'] as List?)?.length ?? 0} variant)',
          style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF8B5CF6),
              fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        )),
        GestureDetector(
          onTap: () => setState(() => _poll = null),
          child: const Icon(LucideIcons.x, size: 16, color: Color(0xFF8B5CF6)),
        ),
      ]),
    );
  }

  Widget _buildMusicBanner(AlsamosColors c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEC4899).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFFEC4899).withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        const Icon(LucideIcons.music, size: 16, color: Color(0xFFEC4899)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(
          'Musiqa: $_musicTrack',
          style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFEC4899),
              fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        )),
        GestureDetector(
          onTap: () => setState(() => _musicTrack = null),
          child: const Icon(LucideIcons.x, size: 16, color: Color(0xFFEC4899)),
        ),
      ]),
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
                ListTile(
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

// Media chip button widget
class _MediaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MediaChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: c.foreground,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyMediaStage extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color primary;
  final VoidCallback? onImage;
  final VoidCallback? onVideo;
  final VoidCallback? onFile;

  const _EmptyMediaStage({
    required this.title,
    required this.subtitle,
    required this.primary,
    this.onImage,
    this.onVideo,
    this.onFile,
  });

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 420),
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF020617)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(color: primary.withValues(alpha: 0.35)),
              ),
              child: Icon(LucideIcons.uploadCloud, color: primary, size: 36),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                if (onImage != null)
                  _MediaChip(
                    icon: LucideIcons.image,
                    label: 'Rasm',
                    color: const Color(0xFF22C55E),
                    onTap: onImage!,
                  ),
                if (onVideo != null)
                  _MediaChip(
                    icon: LucideIcons.video,
                    label: 'Video',
                    color: const Color(0xFF3B82F6),
                    onTap: onVideo!,
                  ),
                if (onFile != null)
                  _MediaChip(
                    icon: LucideIcons.file,
                    label: 'Fayl',
                    color: const Color(0xFF8B5CF6),
                    onTap: onFile!,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Drag/drop keyin ulanadi. Hozir gallery va file picker tayyor.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.mutedForeground,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalMediaFrame extends StatefulWidget {
  final XFile file;
  final double? aspectRatio;
  final bool forceReel;
  final VoidCallback onRemove;

  const _LocalMediaFrame({
    required this.file,
    required this.aspectRatio,
    required this.forceReel,
    required this.onRemove,
  });

  @override
  State<_LocalMediaFrame> createState() => _LocalMediaFrameState();
}

class _LocalMediaFrameState extends State<_LocalMediaFrame> {
  double? _imageAspect;

  bool get _isVideo => RegExp(
        r'\.(mp4|mov|webm|m4v|avi|mkv|flv|wmv)$',
        caseSensitive: false,
      ).hasMatch(widget.file.path);

  bool get _isImage => RegExp(
        r'\.(jpg|jpeg|png|gif|webp|bmp|heic|heif)$',
        caseSensitive: false,
      ).hasMatch(widget.file.path);

  @override
  void initState() {
    super.initState();
    _resolveImageAspect();
  }

  @override
  void didUpdateWidget(covariant _LocalMediaFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _imageAspect = null;
      _resolveImageAspect();
    }
  }

  void _resolveImageAspect() {
    if (!_isImage || widget.aspectRatio != null) return;
    final provider = FileImage(File(widget.file.path));
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        final width = info.image.width;
        final height = info.image.height;
        if (height > 0 && mounted) {
          setState(() => _imageAspect = width / height);
        }
        stream.removeListener(listener);
      },
      onError: (_, __) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final rawRatio =
        widget.aspectRatio ?? _imageAspect ?? (_isVideo ? 16 / 9 : 1);
    final ratio =
        widget.forceReel ? 9 / 16 : rawRatio.clamp(0.52, 2.2).toDouble();
    final fit = widget.aspectRatio == null && !widget.forceReel
        ? BoxFit.contain
        : BoxFit.cover;

    return AspectRatio(
      aspectRatio: ratio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(color: Colors.black),
            child: _isVideo
                ? _LocalVideoPreview(path: widget.file.path, fit: fit)
                : _isImage
                    ? Image.file(File(widget.file.path), fit: fit)
                    : _UnsupportedLocalPreview(path: widget.file.path),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Material(
              color: Colors.black.withValues(alpha: 0.62),
              shape: const CircleBorder(),
              child: IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(LucideIcons.x, color: Colors.white, size: 18),
                tooltip: 'Olib tashlash',
              ),
            ),
          ),
          if (widget.aspectRatio == null && !widget.forceReel)
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isVideo ? LucideIcons.video : LucideIcons.maximize2,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Original',
                      style: TextStyle(
                        color: c.foreground.computeLuminance() > 0.5
                            ? Colors.white
                            : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LocalVideoPreview extends StatefulWidget {
  final String path;
  final BoxFit fit;

  const _LocalVideoPreview({required this.path, required this.fit});

  @override
  State<_LocalVideoPreview> createState() => _LocalVideoPreviewState();
}

class _LocalVideoPreviewState extends State<_LocalVideoPreview> {
  VideoPlayerController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant _LocalVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _controller?.dispose();
      _controller = null;
      _error = null;
      _init();
    }
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.file(File(widget.path));
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(LucideIcons.videoOff, color: Colors.white70, size: 42),
              SizedBox(height: 10),
              Text(
                'Video preview ochilmadi',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          controller.value.isPlaying ? controller.pause() : controller.play();
        });
      },
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          FittedBox(
            fit: widget.fit,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
          if (!controller.value.isPlaying)
            Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(LucideIcons.play, color: Colors.white, size: 28),
            ),
        ],
      ),
    );
  }
}

class _UnsupportedLocalPreview extends StatelessWidget {
  final String path;

  const _UnsupportedLocalPreview({required this.path});

  @override
  Widget build(BuildContext context) {
    final name = path.split(RegExp(r'[/\\]')).last;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.file, color: Colors.white70, size: 46),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaThumb extends StatelessWidget {
  final XFile file;
  final bool selected;
  final VoidCallback onTap;

  const _MediaThumb({
    required this.file,
    required this.selected,
    required this.onTap,
  });

  bool get _isVideo => RegExp(
        r'\.(mp4|mov|webm|m4v|avi|mkv|flv|wmv)$',
        caseSensitive: false,
      ).hasMatch(file.path);

  bool get _isImage => RegExp(
        r'\.(jpg|jpeg|png|gif|webp|bmp|heic|heif)$',
        caseSensitive: false,
      ).hasMatch(file.path);

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? primary : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isImage)
              Image.file(File(file.path), fit: BoxFit.cover)
            else
              const Center(
                child: Icon(LucideIcons.video, color: Colors.white70),
              ),
            if (_isVideo)
              const Center(
                child:
                    Icon(LucideIcons.playCircle, color: Colors.white, size: 26),
              ),
          ],
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

class _ReelActionIcon extends StatelessWidget {
  final IconData icon;

  const _ReelActionIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Icon(icon, color: Colors.white, size: 28),
    );
  }
}

class _LiveSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final AlsamosColors colors;

  const _LiveSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: Theme.of(context).colorScheme.primary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      secondary: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colors.muted,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: colors.mutedForeground, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: colors.mutedForeground, fontSize: 12),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _LivePill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    const gap = 42.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Live feature item widget
class _LiveFeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final AlsamosColors c;

  const _LiveFeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 22, color: c.mutedForeground),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(color: c.mutedForeground, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
