import 'dart:math' as math;
import 'dart:typed_data';

import '../models/dsp_parameters.dart';
import 'audio_io_service.dart';
import 'vocal_separator_service.dart';
import 'voice_analyzer_service.dart';

/// Báo cáo kết quả sau khi chạy Pipeline làm đẹp Karaoke để hiển thị lên UI
class DspProcessingReport {
  final PcmAudioData outputAudio;
  final int pitchCorrectedFrames;
  final double averageGainReductionDb;
  final double peakOutputDb;
  final int processingTimeMs;

  const DspProcessingReport({
    required this.outputAudio,
    required this.pitchCorrectedFrames,
    required this.averageGainReductionDb,
    required this.peakOutputDb,
    required this.processingTimeMs,
  });
}

/// Động cơ DSP On-Device xử lý Chuỗi 5 Hiệu ứng làm đẹp Giọng hát & Hòa trộn thông minh
class DspEngineService {
  final VocalSeparatorService _separator = VocalSeparatorService();
  final VoiceAnalyzerService _analyzer = VoiceAnalyzerService();

  /// Xử lý toàn bộ bản thu Karaoke theo thông số [params]
  DspProcessingReport processKaraokeTrack(
    PcmAudioData inputAudio,
    DspParameters params,
  ) {
    final sw = Stopwatch()..start();
    final int sr = inputAudio.sampleRate;
    final int n = inputAudio.length;
    final double intensity = params.masterIntensity.clamp(0.0, 1.5);

    // Bước 0: Tách luồng Vocal và luồng Nhạc nền (Stem Separation)
    late final PcmAudioData vocalStem;
    late final PcmAudioData musicStem;
    if (params.enableStemSeparation) {
      final stems = _separator.separateVocalAndMusic(inputAudio);
      vocalStem = stems.vocalStem;
      musicStem = stems.instrumentalStem;
    } else {
      vocalStem = inputAudio;
      musicStem = PcmAudioData(
        sampleRate: sr,
        channels: 2,
        leftChannel: Float64List(n),
        rightChannel: Float64List(n),
      );
    }

    Float64List vLeft = Float64List.fromList(vocalStem.leftChannel);
    Float64List vRight = Float64List.fromList(vocalStem.rightChannel);

    // Bước 1: Khử tạp âm nền (Smooth Noise Gate) & Giảm âm xì chói (Dynamic De-esser)
    if (params.enableNoiseGateAndDeEsser && intensity > 0.01) {
      _applyNoiseGateAndDeEsser(vLeft, vRight, sr, params, intensity);
    }

    // Bước 2: Pitch Correction / Auto-Tune (Kéo các khung bị phô về đúng cao độ nốt nhạc)
    int correctedFrames = 0;
    if (params.enablePitchCorrection &&
        params.pitchCorrectionStrength * intensity > 0.05) {
      correctedFrames = _applyPitchCorrection(
        vLeft,
        vRight,
        sr,
        (params.pitchCorrectionStrength * intensity).clamp(0.0, 1.0),
        params.retuneSpeed.clamp(0.1, 1.0),
      );
    }

    // Bước 3: Adaptive 5-Band Parametric EQ (Bù trừ đặc trưng giọng + tạo độ sáng phòng thu)
    if (params.enableEq && intensity > 0.01) {
      _apply5BandEq(vLeft, vRight, sr, params, intensity);
    }

    // Bước 4: Dynamic Vocal Compressor + Warm Tube Saturation nhẹ
    double avgGainReductionDb = 0.0;
    if (params.enableCompressor && intensity > 0.01) {
      avgGainReductionDb = _applyVocalCompressor(
        vLeft,
        vRight,
        sr,
        params,
        intensity,
      );
    }

    // Bước 5: Không gian Stereo Reverb & Echo Delay hòa quyện
    if (params.enableReverbDelay && intensity > 0.01) {
      _applyStereoReverbAndDelay(vLeft, vRight, sr, params, intensity);
    }

    // Bước 6: Hòa trộn thông minh (Smart Stem Re-Mix + Sidechain Ducking nhẹ + Brickwall Limiter)
    final double vocalGainLinear = _dbToLinear(params.vocalGainDb * intensity);
    final double musicGainLinear = params.enableStemSeparation
        ? _dbToLinear(params.musicGainDb)
        : 0.0;
    final double width = params.stereoWidth.clamp(0.5, 1.6);

    final Float64List outL = Float64List(n);
    final Float64List outR = Float64List(n);
    double peakAbs = 1e-5;
    double vocalEnv = 0.0;

    for (int i = 0; i < n; i++) {
      final double vl = vLeft[i] * vocalGainLinear;
      final double vr = vRight[i] * vocalGainLinear;

      // Đo bao hình giọng hát để tự động dìm nhẹ nhạc nền 1.5dB khi người dùng lên giọng (Smart Ducking)
      final double vAbs = 0.5 * (vl.abs() + vr.abs());
      vocalEnv = 0.999 * vocalEnv + 0.001 * vAbs;
      final double duckFactor = (1.0 - vocalEnv * 0.25).clamp(0.78, 1.0);

      final double ml = musicStem.leftChannel[i] * musicGainLinear * duckFactor;
      final double mr =
          musicStem.rightChannel[i] * musicGainLinear * duckFactor;

      double mixL = vl + ml;
      double mixR = vr + mr;

      // Mở rộng không gian Stereo (Mid-Side Widener)
      final double mid = 0.5 * (mixL + mixR);
      final double side = 0.5 * (mixL - mixR) * width;
      mixL = mid + side;
      mixR = mid - side;

      // Soft-Knee Mastering Limiter (-0.5 dBFS ceiling) chống vỡ tiếng tuyệt đối
      outL[i] = _softClipLimiter(mixL);
      outR[i] = _softClipLimiter(mixR);

      final double maxSample = math.max(outL[i].abs(), outR[i].abs());
      if (maxSample > peakAbs) peakAbs = maxSample;
    }

    sw.stop();
    final double peakDb = 20.0 * math.log(peakAbs) / math.ln10;

    return DspProcessingReport(
      outputAudio: PcmAudioData(
        sampleRate: sr,
        channels: 2,
        leftChannel: outL,
        rightChannel: outR,
      ),
      pitchCorrectedFrames: correctedFrames,
      averageGainReductionDb: avgGainReductionDb,
      peakOutputDb: peakDb,
      processingTimeMs: sw.elapsedMilliseconds,
    );
  }

  void _applyNoiseGateAndDeEsser(
    Float64List left,
    Float64List right,
    int sr,
    DspParameters params,
    double intensity,
  ) {
    final double gateThreshLinear = _dbToLinear(params.noiseGateThresholdDb);
    final double deEssFreq = params.deEsserFrequencyHz.clamp(4500.0, 8500.0);
    final double deEssStrength =
        (params.deEsserAmount * intensity).clamp(0.0, 0.9);

    // Bộ lọc dò âm xì (Sibilance Detector Bandpass) ở tần số deEssFreq
    final sibDetectorL = _BiquadFilter.bandPass(sr, deEssFreq, 2.0);
    final sibDetectorR = _BiquadFilter.bandPass(sr, deEssFreq, 2.0);

    double gateEnv = 0.0;
    double gateGain = 1.0;

    for (int i = 0; i < left.length; i++) {
      final double absSample = 0.5 * (left[i].abs() + right[i].abs());
      gateEnv = 0.995 * gateEnv + 0.005 * absSample;

      // Smooth Noise Gate (giảm tạp âm phòng khi ngừng hát nhưng không cắt cụt hơi thở)
      final double targetGate = gateEnv < gateThreshLinear ? 0.35 : 1.0;
      gateGain = 0.997 * gateGain + 0.003 * targetGate;

      // Dynamic De-esser: Trích xuất thành phần âm xì chói và trừ bớt khi vượt ngưỡng
      final double sibL = sibDetectorL.process(left[i]);
      final double sibR = sibDetectorR.process(right[i]);
      final double sibEnv = 0.5 * (sibL.abs() + sibR.abs());

      double deEssCut = 0.0;
      if (sibEnv > 0.035) {
        deEssCut = deEssStrength * ((sibEnv - 0.035) / (sibEnv + 0.05));
      }

      left[i] = (left[i] - sibL * deEssCut) * gateGain;
      right[i] = (right[i] - sibR * deEssCut) * gateGain;
    }
  }

  int _applyPitchCorrection(
    Float64List left,
    Float64List right,
    int sr,
    double strength,
    double retuneSpeed,
  ) {
    const int frameSize = 1024;
    const int hopSize = 512;
    if (left.length < frameSize * 2) return 0;

    final Float64List outL = Float64List.fromList(left);
    final Float64List outR = Float64List.fromList(right);
    int correctedCount = 0;
    double smoothedRatio = 1.0;

    for (int start = 0; start + frameSize <= left.length; start += hopSize) {
      final frameMono = Float64List(frameSize);
      double energy = 0.0;
      for (int i = 0; i < frameSize; i++) {
        final double m = 0.5 * (left[start + i] + right[start + i]);
        frameMono[i] = m;
        energy += m * m;
      }

      if (energy / frameSize < 1e-4) {
        smoothedRatio = 0.9 * smoothedRatio + 0.1 * 1.0;
        continue;
      }

      final double detectedHz = _analyzer.detectPitchYin(frameMono, sr);
      if (detectedHz >= 85.0 && detectedHz <= 950.0) {
        // Tìm nốt nhạc chuẩn gần nhất theo thang 12 bán cung (A4 = 440Hz)
        final double midiNote =
            69.0 + 12.0 * (math.log(detectedHz / 440.0) / math.ln2);
        final double nearestMidi = midiNote.roundToDouble();
        final double targetHz =
            440.0 * math.pow(2.0, (nearestMidi - 69.0) / 12.0);

        final double rawRatio = (targetHz / detectedHz).clamp(0.92, 1.08);
        // Áp dụng tốc độ kéo nốt (Retune Speed) và mức độ Pitch Correction
        final double targetRatio = 1.0 + (rawRatio - 1.0) * strength;
        smoothedRatio =
            (1.0 - retuneSpeed) * smoothedRatio + retuneSpeed * targetRatio;

        if ((smoothedRatio - 1.0).abs() > 0.003) {
          correctedCount++;
          // Nội suy dịch cao độ mượt với cửa sổ Hann (Overlap-Add Pitch Shifting)
          for (int i = 0; i < frameSize; i++) {
            final double win =
                0.5 * (1.0 - math.cos(2.0 * math.pi * i / (frameSize - 1)));
            final double srcPos = start + i * smoothedRatio;
            final int idx0 = srcPos.floor().clamp(0, left.length - 2);
            final double frac = srcPos - idx0;

            final double resampledL =
                left[idx0] * (1.0 - frac) + left[idx0 + 1] * frac;
            final double resampledR =
                right[idx0] * (1.0 - frac) + right[idx0 + 1] * frac;

            // Hòa trộn mượt vào vùng cửa sổ để giữ độ tự nhiên của âm sắc (Formant preservation)
            final double blend = win * 0.65 * strength;
            outL[start + i] =
                outL[start + i] * (1.0 - blend) + resampledL * blend;
            outR[start + i] =
                outR[start + i] * (1.0 - blend) + resampledR * blend;
          }
        }
      }
    }

    for (int i = 0; i < left.length; i++) {
      left[i] = outL[i];
      right[i] = outR[i];
    }
    return correctedCount;
  }

  void _apply5BandEq(
    Float64List left,
    Float64List right,
    int sr,
    DspParameters params,
    double intensity,
  ) {
    final List<_BiquadFilter> filtersL = [
      _BiquadFilter.lowShelf(sr, 105.0, params.eqSub100HzDb * intensity),
      _BiquadFilter.peaking(sr, 280.0, 1.1, params.eqLowMid280HzDb * intensity),
      _BiquadFilter.peaking(sr, 1200.0, 1.2, params.eqMid1200HzDb * intensity),
      _BiquadFilter.peaking(
        sr,
        3500.0,
        1.1,
        params.eqHighMid3500HzDb * intensity,
      ),
      _BiquadFilter.highShelf(sr, 9500.0, params.eqAir10kHzDb * intensity),
    ];

    final List<_BiquadFilter> filtersR = [
      _BiquadFilter.lowShelf(sr, 105.0, params.eqSub100HzDb * intensity),
      _BiquadFilter.peaking(sr, 280.0, 1.1, params.eqLowMid280HzDb * intensity),
      _BiquadFilter.peaking(sr, 1200.0, 1.2, params.eqMid1200HzDb * intensity),
      _BiquadFilter.peaking(
        sr,
        3500.0,
        1.1,
        params.eqHighMid3500HzDb * intensity,
      ),
      _BiquadFilter.highShelf(sr, 9500.0, params.eqAir10kHzDb * intensity),
    ];

    for (int i = 0; i < left.length; i++) {
      double sL = left[i];
      double sR = right[i];
      for (int b = 0; b < 5; b++) {
        sL = filtersL[b].process(sL);
        sR = filtersR[b].process(sR);
      }
      left[i] = sL;
      right[i] = sR;
    }
  }

  double _applyVocalCompressor(
    Float64List left,
    Float64List right,
    int sr,
    DspParameters params,
    double intensity,
  ) {
    final double thresholdDb = params.compThresholdDb;
    final double ratio = 1.0 + (params.compRatio - 1.0) * intensity.clamp(0.2, 1.3);
    final double makeupLinear =
        _dbToLinear(params.compMakeupGainDb * intensity.clamp(0.0, 1.2));

    // Hằng số thời gian Attack (8ms) & Release (110ms) chuẩn giọng hát
    final double attackCoeff = math.exp(-1.0 / (0.008 * sr));
    final double releaseCoeff = math.exp(-1.0 / (0.110 * sr));

    double envLinear = 1e-5;
    double totalReductionDb = 0.0;
    int activeSamples = 0;

    for (int i = 0; i < left.length; i++) {
      final double inputAbs = math.max(left[i].abs(), right[i].abs());
      if (inputAbs > envLinear) {
        envLinear = attackCoeff * envLinear + (1.0 - attackCoeff) * inputAbs;
      } else {
        envLinear = releaseCoeff * envLinear + (1.0 - releaseCoeff) * inputAbs;
      }

      final double envDb = 20.0 * math.log(math.max(envLinear, 1e-5)) / math.ln10;
      double gainReductionDb = 0.0;
      if (envDb > thresholdDb) {
        gainReductionDb = (envDb - thresholdDb) * (1.0 - 1.0 / ratio);
        totalReductionDb += gainReductionDb;
        activeSamples++;
      }

      final double totalGain = _dbToLinear(-gainReductionDb) * makeupLinear;
      // Thêm chút Harmonic Warmth (Analog Tube Saturation nhẹ) giúp giọng dày hơn
      left[i] = _warmHarmonicExciter(left[i] * totalGain);
      right[i] = _warmHarmonicExciter(right[i] * totalGain);
    }

    return activeSamples > 0 ? totalReductionDb / activeSamples : 0.0;
  }

  void _applyStereoReverbAndDelay(
    Float64List left,
    Float64List right,
    int sr,
    DspParameters params,
    double intensity,
  ) {
    final double wetReverb =
        (params.reverbWetMix * intensity).clamp(0.0, 0.65);
    final double wetDelay = (params.delayMix * intensity).clamp(0.0, 0.45);
    final double roomSize = params.reverbRoomSize.clamp(0.2, 0.95);
    final double damping = params.reverbDamping.clamp(0.1, 0.85);

    // Bộ Echo Delay Stereo (chênh nhẹ 12ms giữa L và R để tạo hiệu ứng Haas Stereo rộng)
    final int delaySamplesL =
        ((params.delayTimeMs / 1000.0) * sr).round().clamp(200, sr);
    final int delaySamplesR =
        (((params.delayTimeMs + 12.0) / 1000.0) * sr).round().clamp(200, sr);
    final Float64List delayBufL = Float64List(delaySamplesL);
    final Float64List delayBufR = Float64List(delaySamplesR);
    final double delayFb = params.delayFeedback.clamp(0.0, 0.6);
    int dIdxL = 0;
    int dIdxR = 0;

    // 4 đường Comb Filter song song + 2 đường All-pass Filter (Cấu trúc Schroeder/Freeverb)
    final double scale = sr / 44100.0;
    final List<_CombFilter> combsL = [
      _CombFilter((1116 * scale).round(), 0.72 * roomSize, damping),
      _CombFilter((1188 * scale).round(), 0.70 * roomSize, damping),
      _CombFilter((1277 * scale).round(), 0.68 * roomSize, damping),
      _CombFilter((1356 * scale).round(), 0.66 * roomSize, damping),
    ];
    final List<_CombFilter> combsR = [
      _CombFilter(((1116 + 23) * scale).round(), 0.72 * roomSize, damping),
      _CombFilter(((1188 + 23) * scale).round(), 0.70 * roomSize, damping),
      _CombFilter(((1277 + 23) * scale).round(), 0.68 * roomSize, damping),
      _CombFilter(((1356 + 23) * scale).round(), 0.66 * roomSize, damping),
    ];

    final _AllPassFilter apL1 = _AllPassFilter((556 * scale).round(), 0.5);
    final _AllPassFilter apL2 = _AllPassFilter((441 * scale).round(), 0.5);
    final _AllPassFilter apR1 = _AllPassFilter(((556 + 23) * scale).round(), 0.5);
    final _AllPassFilter apR2 = _AllPassFilter(((441 + 23) * scale).round(), 0.5);

    // Lọc bỏ tần số quá trầm trong đuôi Reverb để tránh làm đục bản thu Karaoke
    final reverbHpL = _BiquadFilter.lowShelf(sr, 220.0, -6.0);
    final reverbHpR = _BiquadFilter.lowShelf(sr, 220.0, -6.0);

    for (int i = 0; i < left.length; i++) {
      final double dryL = left[i];
      final double dryR = right[i];

      // 1. Tính Stereo Echo Delay
      final double delOutL = delayBufL[dIdxL];
      final double delOutR = delayBufR[dIdxR];
      delayBufL[dIdxL] = dryL + delOutL * delayFb;
      delayBufR[dIdxR] = dryR + delOutR * delayFb;
      dIdxL = (dIdxL + 1) % delaySamplesL;
      dIdxR = (dIdxR + 1) % delaySamplesR;

      // 2. Tính Stereo Reverb
      final double revInL = reverbHpL.process(dryL) * 0.25;
      final double revInR = reverbHpR.process(dryR) * 0.25;
      double revOutL = 0.0;
      double revOutR = 0.0;
      for (int c = 0; c < 4; c++) {
        revOutL += combsL[c].process(revInL);
        revOutR += combsR[c].process(revInR);
      }
      revOutL = apL2.process(apL1.process(revOutL));
      revOutR = apR2.process(apR1.process(revOutR));

      left[i] = dryL * (1.0 - wetReverb * 0.25) +
          delOutL * wetDelay +
          revOutL * wetReverb;
      right[i] = dryR * (1.0 - wetReverb * 0.25) +
          delOutR * wetDelay +
          revOutR * wetReverb;
    }
  }

  double _dbToLinear(double db) => math.pow(10.0, db / 20.0).toDouble();

  double _warmHarmonicExciter(double x) {
    // Hàm saturator bất đối xứng nhẹ tạo hài bậc 2 ấm áp như Preamp đèn
    if (x.abs() < 0.1) return x;
    return (x + 0.08 * x * x * (x >= 0 ? 1.0 : -1.0)) / 1.06;
  }

  double _softClipLimiter(double x) {
    const double ceiling = 0.96;
    if (x.abs() <= 0.75) return x;
    final double sign = x >= 0 ? 1.0 : -1.0;
    final double excess = x.abs() - 0.75;
    return sign * (0.75 + (ceiling - 0.75) * (1.0 - math.exp(-excess * 4.5)));
  }
}

class _CombFilter {
  final Float64List _buffer;
  final double _feedback;
  final double _damp1;
  final double _damp2;
  int _idx = 0;
  double _filterStore = 0.0;

  _CombFilter(int size, this._feedback, double damping)
      : _buffer = Float64List(math.max(16, size)),
        _damp1 = damping,
        _damp2 = 1.0 - damping;

  double process(double input) {
    final double output = _buffer[_idx];
    _filterStore = output * _damp2 + _filterStore * _damp1;
    _buffer[_idx] = input + _filterStore * _feedback;
    _idx = (_idx + 1) % _buffer.length;
    return output;
  }
}

class _AllPassFilter {
  final Float64List _buffer;
  final double _feedback;
  int _idx = 0;

  _AllPassFilter(int size, this._feedback)
      : _buffer = Float64List(math.max(16, size));

  double process(double input) {
    final double bufOut = _buffer[_idx];
    final double output = -input + bufOut;
    _buffer[_idx] = input + bufOut * _feedback;
    _idx = (_idx + 1) % _buffer.length;
    return output;
  }
}

class _BiquadFilter {
  final double b0, b1, b2, a1, a2;
  double _x1 = 0.0, _x2 = 0.0, _y1 = 0.0, _y2 = 0.0;

  _BiquadFilter(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory _BiquadFilter.peaking(
    int sampleRate,
    double freq,
    double q,
    double gainDb,
  ) {
    final double a = math.pow(10.0, gainDb / 40.0).toDouble();
    final double w0 = 2.0 * math.pi * freq / sampleRate;
    final double cosW = math.cos(w0);
    final double alpha = math.sin(w0) / (2.0 * q);
    final double a0 = 1.0 + alpha / a;
    return _BiquadFilter(
      (1.0 + alpha * a) / a0,
      (-2.0 * cosW) / a0,
      (1.0 - alpha * a) / a0,
      (-2.0 * cosW) / a0,
      (1.0 - alpha / a) / a0,
    );
  }

  factory _BiquadFilter.lowShelf(int sampleRate, double freq, double gainDb) {
    final double a = math.pow(10.0, gainDb / 40.0).toDouble();
    final double w0 = 2.0 * math.pi * freq / sampleRate;
    final double cosW = math.cos(w0);
    final double sinW = math.sin(w0);
    final double sqrtA2Alpha = 2.0 * math.sqrt(a) * (sinW / 2.0);
    final double a0 = (a + 1.0) + (a - 1.0) * cosW + sqrtA2Alpha;
    return _BiquadFilter(
      (a * ((a + 1.0) - (a - 1.0) * cosW + sqrtA2Alpha)) / a0,
      (2.0 * a * ((a - 1.0) - (a + 1.0) * cosW)) / a0,
      (a * ((a + 1.0) - (a - 1.0) * cosW - sqrtA2Alpha)) / a0,
      (-2.0 * ((a - 1.0) + (a + 1.0) * cosW)) / a0,
      ((a + 1.0) + (a - 1.0) * cosW - sqrtA2Alpha) / a0,
    );
  }

  factory _BiquadFilter.highShelf(int sampleRate, double freq, double gainDb) {
    final double a = math.pow(10.0, gainDb / 40.0).toDouble();
    final double w0 = 2.0 * math.pi * freq / sampleRate;
    final double cosW = math.cos(w0);
    final double sinW = math.sin(w0);
    final double sqrtA2Alpha = 2.0 * math.sqrt(a) * (sinW / 2.0);
    final double a0 = (a + 1.0) - (a - 1.0) * cosW + sqrtA2Alpha;
    return _BiquadFilter(
      (a * ((a + 1.0) + (a - 1.0) * cosW + sqrtA2Alpha)) / a0,
      (-2.0 * a * ((a - 1.0) + (a + 1.0) * cosW)) / a0,
      (a * ((a + 1.0) + (a - 1.0) * cosW - sqrtA2Alpha)) / a0,
      (2.0 * ((a - 1.0) - (a + 1.0) * cosW)) / a0,
      ((a + 1.0) - (a - 1.0) * cosW - sqrtA2Alpha) / a0,
    );
  }

  factory _BiquadFilter.bandPass(int sampleRate, double freq, double q) {
    final double w0 = 2.0 * math.pi * freq / sampleRate;
    final double cosW = math.cos(w0);
    final double alpha = math.sin(w0) / (2.0 * q);
    final double a0 = 1.0 + alpha;
    return _BiquadFilter(
      alpha / a0,
      0.0,
      -alpha / a0,
      (-2.0 * cosW) / a0,
      (1.0 - alpha) / a0,
    );
  }

  double process(double x) {
    final double y = b0 * x + b1 * _x1 + b2 * _x2 - a1 * _y1 - a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }
}
