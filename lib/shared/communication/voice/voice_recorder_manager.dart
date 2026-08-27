import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../audio/speech_audio_config.dart';
import '../../audio/wav_speech_processor.dart';

final voiceRecorderManagerProvider =
    StateNotifierProvider<VoiceRecorderManager, VoiceRecorderState>(
        (ref) => VoiceRecorderManager());

enum RecordingStatus { idle, recording, paused }

class VoiceRecorderState {
  final RecordingStatus status;
  final Duration elapsed;
  final double amplitude;
  final List<double> waveformSamples;

  const VoiceRecorderState({
    this.status = RecordingStatus.idle,
    this.elapsed = Duration.zero,
    this.amplitude = 0.0,
    this.waveformSamples = const [],
  });

  bool get isRecording => status == RecordingStatus.recording;
  bool get isPaused => status == RecordingStatus.paused;
  bool get isIdle => status == RecordingStatus.idle;

  VoiceRecorderState copyWith({
    RecordingStatus? status,
    Duration? elapsed,
    double? amplitude,
    List<double>? waveformSamples,
  }) =>
      VoiceRecorderState(
        status: status ?? this.status,
        elapsed: elapsed ?? this.elapsed,
        amplitude: amplitude ?? this.amplitude,
        waveformSamples: waveformSamples ?? this.waveformSamples,
      );
}

class VoiceRecordingResult {
  final String path;
  final Duration duration;
  final List<double> waveform;
  final String mimeType;
  final WavProcessingResult? processing;

  const VoiceRecordingResult({
    required this.path,
    required this.duration,
    required this.waveform,
    required this.mimeType,
    this.processing,
  });
}

class VoiceRecorderManager extends StateNotifier<VoiceRecorderState> {
  VoiceRecorderManager() : super(const VoiceRecorderState());

  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  Timer? _amplitudeTimer;
  DateTime? _startedAt;
  Duration _pausedDuration = Duration.zero;

  Future<bool> hasPermission() async {
    if (kIsWeb) return await _recorder.hasPermission();
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  Future<bool> start({String? outputPath}) async {
    if (!await hasPermission()) return false;

    final path = outputPath ?? await _defaultPath();

    try {
      await _recorder.start(
        SpeechAudioConfig.voiceRecordConfig,
        path: path,
      );
    } catch (e) {
      debugPrint('[VoiceRecorderManager] start error: $e');
      return false;
    }

    _startedAt = DateTime.now();
    _pausedDuration = Duration.zero;
    state = const VoiceRecorderState(status: RecordingStatus.recording);

    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final elapsed = now.difference(_startedAt!) - _pausedDuration;
      state = state.copyWith(elapsed: elapsed);
    });

    _amplitudeTimer =
        Timer.periodic(const Duration(milliseconds: 80), (_) async {
      if (!mounted) return;
      try {
        final amp = await _recorder.getAmplitude();
        final normalized = ((amp.current + 60) / 60).clamp(0.0, 1.0);
        final samples = List<double>.from(state.waveformSamples);
        samples.add(normalized);
        if (samples.length > 200) samples.removeAt(0);
        state = state.copyWith(amplitude: normalized, waveformSamples: samples);
      } catch (_) {}
    });

    return true;
  }

  Future<void> pause() async {
    if (!state.isRecording) return;
    await _recorder.pause();
    _timer?.cancel();
    state = state.copyWith(status: RecordingStatus.paused);
  }

  Future<void> resume() async {
    if (!state.isPaused) return;
    await _recorder.resume();
    _startedAt = DateTime.now();
    _pausedDuration = Duration.zero;
    final prevElapsed = state.elapsed;

    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final elapsed =
          prevElapsed + now.difference(_startedAt!) - _pausedDuration;
      state = state.copyWith(elapsed: elapsed);
    });

    state = state.copyWith(status: RecordingStatus.recording);
  }

  Future<VoiceRecordingResult?> stop() async {
    _timer?.cancel();
    _amplitudeTimer?.cancel();

    final duration = state.elapsed;
    final waveform = List<double>.from(state.waveformSamples);

    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      debugPrint('[VoiceRecorderManager] stop error: $e');
    }

    state = const VoiceRecorderState();

    if (path == null || path.isEmpty) return null;

    WavProcessingResult? processing;
    try {
      processing = await const WavSpeechProcessor().normalizeFile(path);
    } catch (e) {
      debugPrint('[VoiceRecorderManager] normalization skipped: $e');
    }

    return VoiceRecordingResult(
      path: path,
      duration: duration,
      waveform: waveform,
      mimeType: 'audio/wav',
      processing: processing,
    );
  }

  Future<void> cancel() async {
    _timer?.cancel();
    _amplitudeTimer?.cancel();

    try {
      final path = await _recorder.stop();
      if (path != null && path.isNotEmpty && !kIsWeb) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}

    state = const VoiceRecorderState();
  }

  Future<String> _defaultPath() async {
    if (kIsWeb) return '';
    final dir = Directory.systemTemp;
    final ts = DateTime.now().microsecondsSinceEpoch;
    return '${dir.path}/voice_$ts.wav';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amplitudeTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}
