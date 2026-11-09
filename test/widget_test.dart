import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_auto/models/dsp_parameters.dart';
import 'package:audio_auto/models/studio_mode.dart';
import 'package:audio_auto/models/voice_profile.dart';
import 'package:audio_auto/services/audio_io_service.dart';
import 'package:audio_auto/services/dsp_engine_service.dart';
import 'package:audio_auto/services/vocal_separator_service.dart';
import 'package:audio_auto/services/voice_analyzer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceAnalyzerService & YIN Pitch Detection Tests', () {
    test('YIN detects 220Hz (A3) sine wave accurately', () {
      final analyzer = VoiceAnalyzerService();
      const int sr = 44100;
      const double targetFreq = 220.0;
      final frame = Float64List(1024);
      for (int i = 0; i < frame.length; i++) {
        frame[i] = 0.6 * math.sin(2.0 * math.pi * targetFreq * i / sr);
      }

      final detected = analyzer.detectPitchYin(frame, sr);
      expect(detected, closeTo(targetFreq, 2.5));
    });

    test('4-Step Voice Profiling builds valid UserVoiceProfile & EQ curve', () {
      final io = AudioIoService();
      final analyzer = VoiceAnalyzerService();
      final demoAudio = io.generateDemoKaraokeMix(durationSeconds: 3.0);

      final stepMetrics = analyzer.analyzeAudioClip(demoAudio);
      final profile = analyzer.buildProfileFrom4Steps([
        stepMetrics,
        stepMetrics,
        stepMetrics,
        stepMetrics,
      ]);

      expect(profile.eqCompensationGainsDb.length, equals(5));
      expect(profile.minPitchHz, lessThanOrEqualTo(profile.maxPitchHz));
      expect(profile.warmthScore, inInclusiveRange(0.2, 1.0));
      expect(profile.brightnessScore, inInclusiveRange(0.2, 1.0));
    });
  });

  group('VocalSeparatorService & DspEngineService Tests', () {
    test('Stem separation & 5-Stage DSP chain run cleanly without NaN or clipping', () {
      final io = AudioIoService();
      final separator = VocalSeparatorService();
      final dsp = DspEngineService();

      final rawKaraoke = io.generateDemoKaraokeMix(durationSeconds: 2.5);
      final stems = separator.separateVocalAndMusic(rawKaraoke);
      expect(stems.vocalStem.length, equals(rawKaraoke.length));
      expect(stems.instrumentalStem.length, equals(rawKaraoke.length));

      final profile = UserVoiceProfile.defaultDemo();
      for (final preset in KaraokePresetStyle.values) {
        final params = DspParameters.fromPreset(preset, profile);
        final report = dsp.processKaraokeTrack(rawKaraoke, params);

        expect(report.outputAudio.length, equals(rawKaraoke.length));
        for (int i = 0; i < report.outputAudio.length; i += 64) {
          final l = report.outputAudio.leftChannel[i];
          final r = report.outputAudio.rightChannel[i];
          expect(l.isNaN, isFalse);
          expect(r.isNaN, isFalse);
          expect(l.abs(), lessThanOrEqualTo(1.0));
          expect(r.abs(), lessThanOrEqualTo(1.0));
        }
      }

      // Kiểm tra mã hóa & giải mã WAV 16-bit
      final wavBytes = io.encodeWavBytes(rawKaraoke);
      final decoded = io.decodeWavBytes(wavBytes);
      expect(decoded.length, equals(rawKaraoke.length));
      expect(decoded.sampleRate, equals(rawKaraoke.sampleRate));
    });
  });
}
