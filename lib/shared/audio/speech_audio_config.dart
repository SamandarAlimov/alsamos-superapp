import 'package:record/record.dart';

class SpeechAudioConfig {
  static const sampleRate = 48000;
  static const channels = 1;
  static const wavBitRate = 768000;
  static const targetLufs = -16.0;
  static const truePeakCeilingDbfs = -1.0;
  static const maxNormalizationGainDb = 18.0;
  static const speechGateRmsDbfs = -52.0;
  static const highPassHz = 85.0;

  static const voiceRecordConfig = RecordConfig(
    encoder: AudioEncoder.wav,
    bitRate: wavBitRate,
    sampleRate: sampleRate,
    numChannels: channels,
    autoGain: true,
    echoCancel: true,
    noiseSuppress: true,
  );

  static const legacyAacRecordConfig = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 128000,
    sampleRate: 44100,
    numChannels: channels,
    autoGain: true,
    echoCancel: true,
    noiseSuppress: true,
  );
}
