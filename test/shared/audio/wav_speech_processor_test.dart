import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:alsamos_flutter/shared/audio/speech_audio_config.dart';
import 'package:alsamos_flutter/shared/audio/wav_speech_processor.dart';
import 'package:test/test.dart';

const sampleRate = SpeechAudioConfig.sampleRate;

void main() {
  const processor = WavSpeechProcessor();

  test('measures a known sine wave', () {
    final samples = _sine(amplitude: 0.5, seconds: 1);
    final m = WavSpeechProcessor.measureSamples(
      samples,
      sampleRate: sampleRate,
      channels: 1,
    );

    expect(m.peakDbfs, closeTo(-6.02, 0.2));
    expect(m.rmsDbfs, closeTo(-9.03, 0.3));
    expect(m.clippedSamples, 0);
    expect(m.hasSpeech, isTrue);
  });

  test('raises quiet speech-like input without clipping', () async {
    final file = await _tempWav(_sine(amplitude: 0.035, seconds: 1));
    final result = await processor.normalizeFile(file.path);

    expect(result.normalized, isTrue);
    expect(result.appliedGainDb, greaterThan(0));
    expect(result.appliedGainDb,
        lessThanOrEqualTo(SpeechAudioConfig.maxNormalizationGainDb));
    expect(
        result.after.integratedLufs, greaterThan(result.before.integratedLufs));
    expect(result.after.peakDbfs,
        lessThanOrEqualTo(SpeechAudioConfig.truePeakCeilingDbfs + 0.2));
    expect(result.after.clippedSamples, 0);
  });

  test('does not boost already loud input', () async {
    final file = await _tempWav(_sine(amplitude: 0.75, seconds: 1));
    final result = await processor.normalizeFile(file.path);

    expect(result.normalized, isTrue);
    expect(result.appliedGainDb, 0);
    expect(result.after.clippedSamples, 0);
    expect(result.after.peakDbfs,
        lessThanOrEqualTo(SpeechAudioConfig.truePeakCeilingDbfs + 0.2));
  });

  test('does not normalize silence', () async {
    final file = await _tempWav(List<double>.filled(sampleRate, 0));
    final result = await processor.normalizeFile(file.path);

    expect(result.normalized, isFalse);
    expect(result.appliedGainDb, 0);
    expect(result.after.hasSpeech, isFalse);
  });

  test('does not raise very low noise to the target', () async {
    final noise = List<double>.generate(sampleRate, (i) {
      final pseudo = math.sin(i * 12.9898) * 43758.5453;
      return (pseudo - pseudo.floor()) * 0.001 - 0.0005;
    });
    final file = await _tempWav(noise);
    final result = await processor.normalizeFile(file.path);

    expect(result.normalized, isFalse);
    expect(result.after.integratedLufs, result.before.integratedLufs);
  });

  test('respects the maximum normalization gain cap', () async {
    final file = await _tempWav(_sine(amplitude: 0.0035, seconds: 1));
    final result = await processor.normalizeFile(file.path);

    if (result.normalized) {
      expect(result.appliedGainDb, SpeechAudioConfig.maxNormalizationGainDb);
    } else {
      expect(result.appliedGainDb, 0);
    }
  });
}

List<double> _sine({
  required double amplitude,
  required int seconds,
  double frequency = 440,
}) {
  return List<double>.generate(sampleRate * seconds, (i) {
    return math.sin(2 * math.pi * frequency * i / sampleRate) * amplitude;
  });
}

Future<File> _tempWav(List<double> samples) async {
  final file = File(
    '${Directory.systemTemp.path}/alsamos_audio_${DateTime.now().microsecondsSinceEpoch}.wav',
  );
  await file.writeAsBytes(_writeWav(samples), flush: true);
  addTearDown(() {
    if (file.existsSync()) file.deleteSync();
  });
  return file;
}

Uint8List _writeWav(List<double> samples) {
  const channels = 1;
  const bitsPerSample = 16;
  const byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  const blockAlign = channels * bitsPerSample ~/ 8;
  final dataSize = samples.length * 2;
  final out = Uint8List(44 + dataSize);
  final data = ByteData.sublistView(out);
  _ascii(out, 0, 'RIFF');
  data.setUint32(4, 36 + dataSize, Endian.little);
  _ascii(out, 8, 'WAVE');
  _ascii(out, 12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, byteRate, Endian.little);
  data.setUint16(32, blockAlign, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  _ascii(out, 36, 'data');
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

void _ascii(Uint8List bytes, int offset, String value) {
  for (var i = 0; i < value.length; i++) {
    bytes[offset + i] = value.codeUnitAt(i);
  }
}
