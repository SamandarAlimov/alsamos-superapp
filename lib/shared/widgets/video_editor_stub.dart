import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/app_colors.dart';

/// v45: VideoEditor with real `video_player` preview (was stub in v44).
/// UI scaffold ported from web `VideoEditor.tsx` (596L).
/// Trim slider + filter chip row + simple text overlay input.
/// Backend wiring (ffmpeg/native compose) deferred.
class VideoEditorPage extends StatefulWidget {
  final String videoPath;
  final Duration duration;
  final Future<void> Function(VideoEditorResult result)? onExport;
  const VideoEditorPage({
    super.key,
    required this.videoPath,
    required this.duration,
    this.onExport,
  });

  @override
  State<VideoEditorPage> createState() => _VideoEditorPageState();
}

class VideoEditorResult {
  final Duration trimStart;
  final Duration trimEnd;
  final String filter;
  final String? overlayText;
  const VideoEditorResult({
    required this.trimStart,
    required this.trimEnd,
    required this.filter,
    this.overlayText,
  });
}

class _VideoEditorPageState extends State<VideoEditorPage>
    with SingleTickerProviderStateMixin {
  late RangeValues _trim;
  String _filter = 'none';
  final _overlay = TextEditingController();
  late TabController _tabs;
  bool _busy = false;

  // v45: real video preview
  VideoPlayerController? _player;
  bool _playerReady = false;
  bool _playing = false;

  static const _filters = <(String, String, IconData, ColorFilter?)>[
    ('none', 'Original', LucideIcons.image, null),
    ('warm', 'Issiq', LucideIcons.sun,
        ColorFilter.matrix([1.1, 0, 0, 0, 12, 0, 1.0, 0, 0, 6, 0, 0, 0.9, 0, 0, 0, 0, 0, 1, 0])),
    ('cool', 'Sovuq', LucideIcons.snowflake,
        ColorFilter.matrix([0.9, 0, 0, 0, 0, 0, 1.0, 0, 0, 6, 0, 0, 1.15, 0, 14, 0, 0, 0, 1, 0])),
    ('bw', 'B&W', LucideIcons.contrast,
        ColorFilter.matrix([0.33, 0.33, 0.33, 0, 0, 0.33, 0.33, 0.33, 0, 0, 0.33, 0.33, 0.33, 0, 0, 0, 0, 0, 1, 0])),
    ('vintage', 'Vintage', LucideIcons.camera,
        ColorFilter.matrix([0.9, 0.5, 0.1, 0, 0, 0.3, 0.8, 0.1, 0, 0, 0.2, 0.3, 0.5, 0, 0, 0, 0, 0, 1, 0])),
    ('dramatic', 'Drama', LucideIcons.zap,
        ColorFilter.matrix([1.3, 0, 0, 0, -20, 0, 1.3, 0, 0, -20, 0, 0, 1.3, 0, -20, 0, 0, 0, 1, 0])),
  ];

  ColorFilter? get _activeFilter =>
      _filters.firstWhere((f) => f.$1 == _filter, orElse: () => _filters.first).$4;

  @override
  void initState() {
    super.initState();
    final totalMs = widget.duration.inMilliseconds.toDouble();
    _trim = RangeValues(0, totalMs);
    _tabs = TabController(length: 3, vsync: this);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final isUrl = widget.videoPath.startsWith('http://') ||
        widget.videoPath.startsWith('https://');
    final ctrl = isUrl
        ? VideoPlayerController.networkUrl(Uri.parse(widget.videoPath))
        : VideoPlayerController.file(File(widget.videoPath));
    try {
      await ctrl.initialize();
      await ctrl.setLooping(true);
      ctrl.addListener(_onPlayerTick);
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _player = ctrl;
        _playerReady = true;
      });
    } catch (_) {
      // leave _playerReady=false; fallback placeholder will show
      if (mounted) setState(() => _playerReady = false);
    }
  }

  void _onPlayerTick() {
    if (!mounted || _player == null) return;
    final v = _player!.value;
    if (v.isPlaying != _playing) setState(() => _playing = v.isPlaying);
    // Auto-loop trim window
    final ms = v.position.inMilliseconds;
    if (ms >= _trim.end.toInt() && v.isPlaying) {
      _player!.seekTo(Duration(milliseconds: _trim.start.toInt()));
    }
  }

  @override
  void dispose() {
    _overlay.dispose();
    _tabs.dispose();
    _player?.removeListener(_onPlayerTick);
    _player?.dispose();
    super.dispose();
  }

  String _fmtMs(double ms) {
    final d = Duration(milliseconds: ms.toInt());
    final mm = d.inMinutes.toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  void _togglePlay() async {
    final p = _player;
    if (p == null) return;
    if (p.value.isPlaying) {
      await p.pause();
    } else {
      // seek into trim window if needed
      if (p.value.position.inMilliseconds < _trim.start.toInt() ||
          p.value.position.inMilliseconds >= _trim.end.toInt()) {
        await p.seekTo(Duration(milliseconds: _trim.start.toInt()));
      }
      await p.play();
    }
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = VideoEditorResult(
      trimStart: Duration(milliseconds: _trim.start.toInt()),
      trimEnd: Duration(milliseconds: _trim.end.toInt()),
      filter: _filter,
      overlayText: _overlay.text.trim().isEmpty ? null : _overlay.text.trim(),
    );
    await widget.onExport?.call(result);
    if (!mounted) return;
    Navigator.pop(context, result);
  }

  Widget _videoPreview() {
    final p = _player;
    if (!_playerReady || p == null || !p.value.isInitialized) {
      return Container(
        color: Colors.grey[900],
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white24, strokeWidth: 2),
              SizedBox(height: 8),
              Text('Yuklanmoqda…',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      );
    }
    final inner = AspectRatio(
      aspectRatio: p.value.aspectRatio,
      child: VideoPlayer(p),
    );
    final filtered = _activeFilter == null
        ? inner
        : ColorFiltered(colorFilter: _activeFilter!, child: inner);
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(child: filtered),
          if (!_playing)
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.play,
                  color: Colors.white, size: 26),
            ),
          if (_overlay.text.trim().isNotEmpty)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 16),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _overlay.text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final totalMs = widget.duration.inMilliseconds.toDouble();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Video tahrirlash'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _export,
            child: Text(
              _busy ? '...' : 'Eksport',
              style: const TextStyle(
                  color: AppColors.alsamosOrange,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(12),
            height: 220,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _videoPreview(),
            ),
          ),
          TabBar(
            controller: _tabs,
            labelColor: AppColors.alsamosOrange,
            unselectedLabelColor: Colors.white70,
            indicatorColor: AppColors.alsamosOrange,
            tabs: const [
              Tab(icon: Icon(LucideIcons.scissors), text: 'Kesish'),
              Tab(icon: Icon(LucideIcons.image), text: 'Filtr'),
              Tab(icon: Icon(LucideIcons.type), text: 'Matn'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Boshlanish: ${_fmtMs(_trim.start)} — Tugash: ${_fmtMs(_trim.end)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      RangeSlider(
                        values: _trim,
                        min: 0,
                        max: totalMs,
                        activeColor: AppColors.alsamosOrange,
                        inactiveColor: Colors.white24,
                        labels: RangeLabels(
                            _fmtMs(_trim.start), _fmtMs(_trim.end)),
                        onChanged: (v) {
                          setState(() => _trim = v);
                          // jump player to new start when dragging
                          _player?.seekTo(
                              Duration(milliseconds: v.start.toInt()));
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Davomiyligi: ${_fmtMs(_trim.end - _trim.start)}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: GridView.builder(
                    itemCount: _filters.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.0,
                    ),
                    itemBuilder: (_, i) {
                      final f = _filters[i];
                      final selected = _filter == f.$1;
                      return InkWell(
                        onTap: () => setState(() => _filter = f.$1),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.alsamosOrange.withValues(alpha: 0.2)
                                : Colors.white12,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? AppColors.alsamosOrange
                                  : Colors.transparent,
                              width: 1.4,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(f.$3,
                                  color: selected
                                      ? AppColors.alsamosOrange
                                      : Colors.white70),
                              const SizedBox(height: 8),
                              Text(f.$2,
                                  style: TextStyle(
                                      color: selected
                                          ? AppColors.alsamosOrange
                                          : Colors.white,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _overlay,
                        maxLength: 60,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Matn qo\'shing…',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white12,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: c.muted.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.info,
                                color: Colors.white60, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Matn videoning ustida ko\'rsatiladi.',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
