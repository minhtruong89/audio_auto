import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_auto/models/dsp_parameters.dart';
import 'package:audio_auto/models/studio_mode.dart';
import 'package:audio_auto/models/voice_profile.dart';
import 'package:audio_auto/services/audio_io_service.dart';
import 'package:audio_auto/services/dsp_engine_service.dart';
import 'package:audio_auto/services/music_key_analyzer_service.dart';
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

    test('YIN avoids octave-doubling and classifies Male phone-mic voice accurately', () {
      final analyzer = VoiceAnalyzerService();
      const int sr = 44100;
      const int n = sr * 2;
      final samples = Float64List(n);
      // Giả lập giọng Nam F0 = 118Hz qua micro điện thoại (tần số gốc F0 yếu hơn hài bậc 2 & 3)
      for (int i = 0; i < n; i++) {
        final t = i / sr;
        samples[i] = 0.14 * math.sin(2.0 * math.pi * 118.0 * t) +
            0.38 * math.sin(2.0 * math.pi * 236.0 * t) +
            0.28 * math.sin(2.0 * math.pi * 354.0 * t) +
            0.01; // DC offset nhẹ của mic
      }
      final pcm = PcmAudioData(
        sampleRate: sr,
        channels: 1,
        leftChannel: samples,
        rightChannel: samples,
      );

      final step = analyzer.analyzeAudioClip(pcm, stepIndex: 0);
      final profile = analyzer.buildProfileFrom4Steps([step, step, step, step]);
      expect(step.meanPitchHz, closeTo(118.0, 6.0));
      expect(profile.isMaleVoice, isTrue);

      // Giả lập giọng Nữ chuẩn F0 = 225Hz
      final femaleSamples = Float64List(n);
      for (int i = 0; i < n; i++) {
        final t = i / sr;
        femaleSamples[i] = 0.35 * math.sin(2.0 * math.pi * 225.0 * t) +
            0.25 * math.sin(2.0 * math.pi * 450.0 * t) +
            0.12 * math.sin(2.0 * math.pi * 675.0 * t);
      }
      final fPcm = PcmAudioData(
        sampleRate: sr,
        channels: 1,
        leftChannel: femaleSamples,
        rightChannel: femaleSamples,
      );
      final fStep = analyzer.analyzeAudioClip(fPcm, stepIndex: 0);
      final fProfile = analyzer.buildProfileFrom4Steps([fStep, fStep, fStep, fStep]);
      expect(fStep.meanPitchHz, closeTo(225.0, 6.0));
      expect(fProfile.isMaleVoice, isFalse);
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

      // Kiểm tra chế độ Tự Hát (preserveSongKey: true) giữ nguyên 0 bán cung + Music Mastering EQ
      final selfSingParams = DspParameters.fromVoiceProfile(
        profile,
        preserveSongKey: true,
      );
      final selfSingReport = dsp.processKaraokeTrack(rawKaraoke, selfSingParams);
      expect(selfSingReport.appliedSemitoneShift, equals(0.0));
      expect(selfSingReport.musicOnlyAudio.length, equals(rawKaraoke.length));
      expect(selfSingReport.detectedMusicKey, isNotNull);

      // Kiểm tra nhận diện Tông Nhạc bằng Chromagram (hợp âm C Major: C4-E4-G4)
      const int sr = 44100;
      const int n = sr * 2;
      final mBuf = Float64List(n);
      final vBuf = Float64List(n);
      for (int i = 0; i < n; i++) {
        final t = i / sr;
        mBuf[i] = 0.3 * math.sin(2 * math.pi * 261.63 * t) + // C4
            0.25 * math.sin(2 * math.pi * 329.63 * t) + // E4
            0.25 * math.sin(2 * math.pi * 392.00 * t); // G4
        vBuf[i] = 0.4 * math.sin(2 * math.pi * 261.63 * t); // C4 khớp tông
      }
      final keyResult = MusicKeyAnalyzerService().analyzeKeys(
        musicStem: PcmAudioData(
          sampleRate: sr,
          channels: 2,
          leftChannel: mBuf,
          rightChannel: mBuf,
        ),
        vocalStem: PcmAudioData(
          sampleRate: sr,
          channels: 2,
          leftChannel: vBuf,
          rightChannel: vBuf,
        ),
      );
      expect(keyResult.shortName, equals('C'));
      expect(keyResult.suggestedVocalShiftSemitones, equals(0));
      expect(keyResult.scalePitchClasses().contains(0), isTrue); // C nằm trong âm giai Đô trưởng

      // Kiểm tra mã hóa & giải mã WAV 16-bit
      final wavBytes = io.encodeWavBytes(rawKaraoke);
      final decoded = io.decodeWavBytes(wavBytes);
      expect(decoded.length, equals(rawKaraoke.length));
      expect(decoded.sampleRate, equals(rawKaraoke.sampleRate));
    });
  });
}
