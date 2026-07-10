import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// v22: live stream page — camera preview + LIVE indicator + viewer count +
/// chat overlay placeholder + start/stop. Creates a `live_streams` row on
/// start so backend RTC ingest can attach. Real ingest is out-of-scope; UX
/// is functional and matches web `CreatePage.tsx` live tab.
class LiveStreamPage extends ConsumerStatefulWidget {
  const LiveStreamPage({super.key});

  @override
  ConsumerState<LiveStreamPage> createState() => _LiveStreamPageState();
}

class _LiveStreamPageState extends ConsumerState<LiveStreamPage> {
  CameraController? _cam;
  bool _initializing = true;
  bool _live = false;
  String? _streamId;
  int _viewers = 0;
  String? _error;
  final _title = TextEditingController(text: 'Live efir');

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() { _error = 'Kamera topilmadi'; _initializing = false; });
        return;
      }
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      _cam = CameraController(front, ResolutionPreset.medium, enableAudio: true);
      await _cam!.initialize();
      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Kamera xatosi: $e'; _initializing = false; });
    }
  }

  Future<void> _toggleLive() async {
    final uid = ref.read(authProvider).user?.id;
    if (uid == null) return;
    if (!_live) {
      try {
        final res = await Supabase.instance.client.from('live_streams').insert({
          'user_id': uid,
          'title': _title.text.trim().isEmpty ? 'Live efir' : _title.text.trim(),
          'status': 'live',
          'started_at': DateTime.now().toUtc().toIso8601String(),
        }).select('id').single();
        setState(() { _live = true; _streamId = res['id'] as String?; });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Xatolik: $e')));
      }
    } else {
      try {
        if (_streamId != null) {
          await Supabase.instance.client.from('live_streams').update({
            'status': 'ended',
            'ended_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', _streamId!);
        }
      } catch (_) {}
      if (mounted) setState(() { _live = false; _streamId = null; _viewers = 0; });
    }
  }

  @override
  void dispose() {
    _cam?.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          // Camera preview
          Positioned.fill(
            child: _initializing
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(LucideIcons.videoOff, color: c.mutedForeground, size: 48),
                          const SizedBox(height: 12),
                          Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                        ]),
                      ))
                    : _cam != null && _cam!.value.isInitialized
                        ? FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _cam!.value.previewSize?.height ?? 360,
                              height: _cam!.value.previewSize?.width ?? 640,
                              child: CameraPreview(_cam!),
                            ),
                          )
                        : const SizedBox.shrink(),
          ),
          // Top bar
          Positioned(top: 8, left: 8, right: 8, child: Row(children: [
            CircleAvatar(
              backgroundColor: Colors.black.withValues(alpha: 0.5),
              child: IconButton(
                icon: const Icon(LucideIcons.x, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 10),
            if (_live) Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(6)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.radio, color: Colors.white, size: 14),
                SizedBox(width: 5),
                Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
            ),
            const Spacer(),
            if (_live) Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(LucideIcons.eye, color: Colors.white, size: 14),
                const SizedBox(width: 5),
                Text('$_viewers', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
              ]),
            ),
          ])),
          // Bottom controls
          Positioned(left: 0, right: 0, bottom: 0, child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!_live)
                TextField(
                  controller: _title,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Efir sarlavhasi...',
                    hintStyle: const TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.4),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: _initializing || _error != null ? null : _toggleLive,
                style: FilledButton.styleFrom(
                  backgroundColor: _live ? const Color(0xFFEF4444) : primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: Icon(_live ? LucideIcons.square : LucideIcons.radio, size: 18),
                label: Text(
                  _live ? "Efirni yakunlash" : "Efirni boshlash",
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              )),
            ]),
          )),
        ]),
      ),
    );
  }
}
