import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'speech_audio_config.dart';

class AudioMeasurement {
  const AudioMeasurement({
    required this.sampleRate,
    required this.channels,
    required this.duration,
    required this.peakDbfs,
    required this.rmsDbfs,
    required this.integratedLufs,
    required this.noiseFloorDbfs,
    required this.clippedSamples,
    required this.hasSpeech,
  });

  final int sampleRate;
  final int channels;
  final Duration duration;
  final double peakDbfs;
  final double rmsDbfs;
  final double integratedLufs;
  final double noiseFloorDbfs;
  final int clippedSamples;
  final bool hasSpeech;
}

class WavProcessingResult {
  const WavProcessingResult({
    required this.path,
    required this.before,
    required this.after,
    required this.appliedGainDb,
    required this.normalized,
  });

  final String path;
  final AudioMeasurement before;
  final AudioMeasurement after;
  final double appliedGainDb;
  final bool normalized;
}

class WavSpeechProcessor {
  const WavSpeechProcessor();

  Future<WavProcessingResult> normalizeFile(String path) async {
    final wav = _readWav(await File(path).readAsBytes());
    final before = measureSamples(
      wav.samples,
      sampleRate: wav.sampleRate,
      channels: wav.channels,
    );
    if (!before.hasSpeech) {
      return WavProcessingResult(
        path: path,
        before: before,
        after: before,
        appliedGainDb: 0,
        normalized: false,
      );
    }

    final gainDb = _gainFor(before);
    final processed = _limit(
      _applyGain(
        _compress(_highPass(wav.samples, wav.sampleRate)),
        gainDb,
      ),
    );
    final after = measureSamples(
      processed,
      sampleRate: wav.sampleRate,
      channels: wav.channels,
    );
    await File(path).writeAsBytes(
      _writeWav(processed, sampleRate: wav.sampleRate, channels: wav.channels),
      flush: true,
    );
    return WavProcessingResult(
      path: path,
      before: before,
      after: after,
      appliedGainDb: gainDb,
      normalized: true,
    );
  }

  static AudioMeasurement measureSamples(
    List<double> samples, {
    required int sampleRate,
    required int channels,
  }) {
    if (samples.isEmpty) {
      return AudioMeasurement(
        sampleRate: sampleRate,
        channels: channels,
        duration: Duration.zero,
        peakDbfs: double.negativeInfinity,
        rmsDbfs: double.negativeInfinity,
        integratedLufs: double.negativeInfinity,
        noiseFloorDbfs: double.negativeInfinity,
        clippedSamples: 0,
        hasSpeech: false,
      );
    }

    var peak = 0.0;
    var sumSquares = 0.0;
    var clipped = 0;
    final window = math.max(1, sampleRate ~/ 10);
    final windowRms = <double>[];
    var acc = 0.0;
    var count = 0;

    for (final sample in samples) {
      final abs = sample.abs();
      peak = math.max(peak, abs);
      sumSquares += sample * sample;
      if (abs >= 0.999) clipped++;
      acc += sample * sample;
      count++;
      if (count == window) {
        windowRms.add(math.sqrt(acc / count));
        acc = 0;
        count = 0;
      }
    }
    if (count > 0) windowRms.add(math.sqrt(acc / count));

    final rms = math.sqrt(sumSquares / samples.length);
    final sorted = [...windowRms]..sort();
    final noise = sorted.isEmpty
        ? 0.0
        : sorted[(sorted.length * 0.1).floor().clamp(0, sorted.length - 1)];
    final rmsDb = _db(rms);
    final lufs = rmsDb - 0.691;
    return AudioMeasurement(
      sampleRate: sampleRate,
      channels: channels,
      duration: Duration(
        microseconds:
            (samples.length * 1000000 / math.max(1, sampleRate * channels))
                .round(),
      ),
      peakDbfs: _db(peak),
      rmsDbfs: rmsDb,
      integratedLufs: lufs,
      noiseFloorDbfs: _db(noise),
      clippedSamples: clipped,
      hasSpeech:
          rmsDb >= SpeechAudioConfig.speechGateRmsDbfs && peak >= _fromDb(-42),
    );
  }

  static double _gainFor(AudioMeasurement m) {
    const target = SpeechAudioConfig.targetLufs;
    final needed = target - m.integratedLufs;
    return needed.clamp(0.0, SpeechAudioConfig.maxNormalizationGainDb);
  }

  static List<double> _highPass(List<double> input, int sampleRate) {
    const rc = 1 / (2 * math.pi * SpeechAudioConfig.highPassHz);
    final dt = 1 / sampleRate;
    final alpha = rc / (rc + dt);
    var lastY = 0.0;
    var lastX = 0.0;
    return [
      for (final x in input)
        () {
          final y = alpha * (lastY + x - lastX);
          lastY = y;
          lastX = x;
          return y;
        }(),
    ];
  }

  static List<double> _compress(List<double> input) {
    const threshold = -24.0;
    const ratio = 3.0;
    return [
      for (final x in input)
        () {
          final abs = x.abs();
          if (abs <= 0) return 0.0;
          final db = _db(abs);
          if (db <= threshold) return x;
          final compressedDb = threshold + (db - threshold) / ratio;
          final gain = _fromDb(compressedDb - db);
          return x * gain;
        }(),
    ];
  }

  static List<double> _applyGain(List<double> input, double gainDb) {
    final gain = _fromDb(gainDb);
    return [for (final x in input) x * gain];
  }

  static List<double> _limit(List<double> input) {
    final ceiling = _fromDb(SpeechAudioConfig.truePeakCeilingDbfs);
    return [
      for (final x in input)
        x > ceiling
            ? ceiling
            : x < -ceiling
                ? -ceiling
                : x,
    ];
  }

  static _WavData _readWav(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (_fourCc(bytes, 0) != 'RIFF' || _fourCc(bytes, 8) != 'WAVE') {
      throw const FormatException('Unsupported WAV header');
    }
    var offset = 12;
    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    int? dataOffset;
    int? dataSize;
    while (offset + 8 <= bytes.length) {
      final id = _fourCc(bytes, offset);
      final size = data.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (id == 'fmt ') {
        final format = data.getUint16(body, Endian.little);
        if (format != 1) throw const FormatException('Only PCM WAV supported');
        channels = data.getUint16(body + 2, Endian.little);
        sampleRate = data.getUint32(body + 4, Endian.little);
        bitsPerSample = data.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        dataOffset = body;
        dataSize = size;
      }
      offset = body + size + (size.isOdd ? 1 : 0);
    }
    if (channels == null ||
        sampleRate == null ||
        bitsPerSample != 16 ||
        dataOffset == null ||
        dataSize == null) {
      throw const FormatException('Unsupported WAV format');
    }
    final samples = <double>[];
    for (var i = dataOffset; i + 1 < dataOffset + dataSize; i += 2) {
      samples.add(data.getInt16(i, Endian.little) / 32768.0);
    }
    return _WavData(samples, sampleRate, channels);
  }

  static Uint8List _writeWav(
    List<double> samples, {
    required int sampleRate,
    required int channels,
  }) {
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = samples.length * 2;
    final out = Uint8List(44 + dataSize);
    final data = ByteData.sublistView(out);
    _writeAscii(out, 0, 'RIFF');
    data.setUint32(4, 36 + dataSize, Endian.little);
    _writeAscii(out, 8, 'WAVE');
    _writeAscii(out, 12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, byteRate, Endian.little);
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    _writeAscii(out, 36, 'data');
    data.setUint32(40, dataSize, Endian.little);
    var offset = 44;
    for (final sample in samples) {
      data.setInt16(
        offset,
        (sample.clamp(-1.0, 0.999969482421875) * 32768).round(),
        Endian.little,
      );
      offset += 2;
    }
    return out;
  }

  static String _fourCc(Uint8List bytes, int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));

  static void _writeAscii(Uint8List bytes, int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  static double _db(double value) =>
      value <= 0 ? double.negativeInfinity : 20 * math.log(value) / math.ln10;

  static double _fromDb(double db) => math.pow(10, db / 20).toDouble();
}

class _WavData {
  const _WavData(this.samples, this.sampleRate, this.channels);

  final List<double> samples;
  final int sampleRate;
  final int channels;
}
