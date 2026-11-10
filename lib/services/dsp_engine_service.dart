import 'dart:math' as math;
import 'dart:typed_data';

import '../models/dsp_parameters.dart';
import 'audio_io_service.dart';
import 'vocal_separator_service.dart';
import 'voice_analyzer_service.dart';

/// Báo cáo kết quả sau khi chạy Pipeline làm đẹp Karaoke để hiển thị lên UI
class DspProcessingReport {
  final PcmAudioData outputAudio;
  final PcmAudioData vocalOnlyAudio;
  final PcmAudioData musicOnlyAudio;
  final int pitchCorrectedFrames;
  final double averageGainReductionDb;
  final double peakOutputDb;
  final int processingTimeMs;
  final double trackOriginalF0Hz;
  final double appliedSemitoneShift;
  final bool usedAiOnnxModel;

  const DspProcessingReport({
    required this.outputAudio,
    required this.vocalOnlyAudio,
    required this.musicOnlyAudio,
    required this.pitchCorrectedFrames,
    required this.averageGainReductionDb,
    required this.peakOutputDb,
    required this.processingTimeMs,
    this.trackOriginalF0Hz = 180.0,
    this.appliedSemitoneShift = 0.0,
    this.usedAiOnnxModel = false,
  });
}

/// Động cơ DSP On-Device xử lý Chuỗi 5 Hiệu ứng làm đẹp Giọng hát & Hòa trộn thông minh
class DspEngineService {
  final VocalSeparatorService _separator = VocalSeparatorService();
  final VoiceAnalyzerService _analyzer = VoiceAnalyzerService();

  bool get isAiOnnxReady => _separator.isAiOnnxReady;

  bool initAiOnnxModel(String modelFilePath, {int numThreads = 4}) {
    return _separator.initAiOnnxModel(modelFilePath, numThreads: numThreads);
  }

  /// Xử lý toàn bộ bản thu Karaoke theo thông số [params]
  DspProcessingReport processKaraokeTrack(
    PcmAudioData inputAudio,
    DspParameters params,
  ) {
    final sw = Stopwatch()..start();
    final int sr = inputAudio.sampleRate;
    final int n = inputAudio.length;

    // Bước 0: Tách luồng Vocal và luồng Nhạc nền (Stem Separation)
    late final PcmAudioData vocalStem;
    late final PcmAudioData musicStem;
    bool usedAiOnnx = false;
    if (params.enableStemSeparation) {
      final stems = _separator.separateVocalAndMusic(inputAudio);
      vocalStem = stems.vocalStem;
      musicStem = stems.instrumentalStem;
      usedAiOnnx = stems.usedAiOnnxModel;
    } else {
      vocalStem = inputAudio;
      musicStem = PcmAudioData(
        sampleRate: sr,
        channels: 2,
        leftChannel: Float64List(n),
        rightChannel: Float64List(n),
      );
    }

    return processSeparatedStems(
      vocalStem: vocalStem,
      musicStem: musicStem,
      params: params,
      usedAiOnnxModel: usedAiOnnx,
      externalStopwatch: sw,
    );
  }

  /// Xử lý chuỗi 5 hiệu ứng DSP & Chuyển giọng trực tiếp trên 2 luồng Vocal + Music đã tách sẵn
  /// (Có thể chạy trong Background Isolate hoặc dùng lại Stems đã cache mà không cần tách lại)
  DspProcessingReport processSeparatedStems({
    required PcmAudioData vocalStem,
    required PcmAudioData musicStem,
    required DspParameters params,
    bool usedAiOnnxModel = false,
    Stopwatch? externalStopwatch,
  }) {
    final sw = externalStopwatch ?? (Stopwatch()..start());
    final int sr = vocalStem.sampleRate;
    final int n = vocalStem.length;
    final double intensity = params.masterIntensity.clamp(0.0, 1.5);
    final bool usedAiOnnx = usedAiOnnxModel;

    Float64List vLeft = Float64List.fromList(vocalStem.leftChannel);
    Float64List vRight = Float64List.fromList(vocalStem.rightChannel);

    // Bước 1: Khử tạp âm nền (Smooth Noise Gate) & Giảm âm xì chói (Dynamic De-esser)
    if (params.enableNoiseGateAndDeEsser && intensity > 0.01) {
      _applyNoiseGateAndDeEsser(vLeft, vRight, sr, params, intensity);
    }

    // Bước 1.5: Áp Đặc Trưng Quãng Giọng & Âm Sắc của Giọng Đã Lưu lên bản thu (Voice Timbre & Pitch Adaptation)
    double trackF0Hz = 180.0;
    double appliedSemitones = 0.0;
    if (params.enableVoiceConversion && params.voiceConversionStrength > 0.05) {
      final convResult = _applyVoiceProfileConversion(
        vLeft,
        vRight,
        sr,
        params,
        intensity,
      );
      trackF0Hz = convResult.detectedTrackF0Hz;
      appliedSemitones = convResult.semitoneShift;
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
    final Float64List vocalSoloL = Float64List(n);
    final Float64List vocalSoloR = Float64List(n);
    double peakAbs = 1e-5;
    double vocalEnv = 0.0;

    for (int i = 0; i < n; i++) {
      final double vl = vLeft[i] * vocalGainLinear;
      final double vr = vRight[i] * vocalGainLinear;

      vocalSoloL[i] = _softClipLimiter(vl);
      vocalSoloR[i] = _softClipLimiter(vr);

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
      vocalOnlyAudio: PcmAudioData(
        sampleRate: sr,
        channels: 2,
        leftChannel: vocalSoloL,
        rightChannel: vocalSoloR,
      ),
      musicOnlyAudio: musicStem,
      pitchCorrectedFrames: correctedFrames,
      averageGainReductionDb: avgGainReductionDb,
      peakOutputDb: peakDb,
      processingTimeMs: sw.elapsedMilliseconds,
      trackOriginalF0Hz: trackF0Hz,
      appliedSemitoneShift: appliedSemitones,
      usedAiOnnxModel: usedAiOnnx,
    );
  }

  /// Đo tần số F0 trung vị của bản thu và dịch chuyển Quãng Giọng (Pitch Transpose) + Vòm Họng (Formant/Timbre)
  /// để biến luồng giọng trong file khớp với đặc trưng Giọng Đã Lưu của người dùng!
  _VoiceConversionResult _applyVoiceProfileConversion(
    Float64List left,
    Float64List right,
    int sr,
    DspParameters params,
    double intensity,
  ) {
    const int frameSize = 1024;
    const int hop = 1024;
    final List<double> pitches = [];

    // 1. Đo tần số cơ bản (F0) thực tế của giọng hát trong file đầu vào
    for (int start = 0; start + frameSize <= left.length; start += hop) {
      final mono = Float64List(frameSize);
      double sumSq = 0.0;
      for (int i = 0; i < frameSize; i++) {
        final m = 0.5 * (left[start + i] + right[start + i]);
        mono[i] = m;
        sumSq += m * m;
      }
      if (sumSq / frameSize > 2e-4) {
        final p = _analyzer.detectPitchYin(mono, sr);
        if (p >= 80.0 && p <= 750.0) {
          pitches.add(p);
        }
      }
    }

    double trackF0 = 185.0;
    if (pitches.isNotEmpty) {
      pitches.sort();
      trackF0 = pitches[pitches.length ~/ 2]; // Trung vị F0 của ca sĩ trong file
    }

    // Vì khi hát cao độ thường cao hơn khi nói khoảng 1.22 lần (~3.5 bán cung),
    // ta quy đổi F0 nói của Hồ sơ giọng sang F0 hát mục tiêu:
    final double targetSingingF0 =
        (params.targetProfileF0Hz * 1.22).clamp(95.0, 480.0);

    // Tính độ chênh bán cung giữa Giọng đã lưu và Giọng trong file
    final double rawSemitoneDiff =
        12.0 * (math.log(targetSingingF0 / trackF0) / math.ln2);
    final double convStrength =
        (params.voiceConversionStrength * intensity.clamp(0.5, 1.3))
            .clamp(0.0, 1.0);

    double semitoneShift = 0.0;
    if (rawSemitoneDiff.abs() >= 3.5) {
      // Khác giới tính hoặc khác quãng giọng lớn (VD: Áp giọng Nam vào diem_xua_nu.wav hoặc ngược lại)
      // Làm tròn về số nguyên bán cung (hoặc quãng 4 / quãng 5 / quãng 8) để không bị lệch tông với nhạc nền!
      final double scaled = (rawSemitoneDiff * 0.78 * convStrength).clamp(-12.0, 12.0);
      semitoneShift = scaled.roundToDouble();
    } else if (rawSemitoneDiff.abs() >= 1.2) {
      // Cùng giới tính (VD: Nam Trầm 110Hz vs Nam Cao 165Hz) -> Dịch nhẹ màu âm & độ trầm/thanh
      semitoneShift = (rawSemitoneDiff * 0.45 * convStrength).clamp(-3.0, 3.0);
    }

    // 2. Thực hiện Dịch Quãng Giọng (Pitch Shift) đồng bộ pha WSOLA + Nội suy Cubic
    // Loại bỏ hoàn toàn hiện tượng rung pha / tiếng kim loại của OLA thông thường
    if (semitoneShift.abs() >= 0.35) {
      final double pitchRatio =
          math.pow(2.0, semitoneShift / 12.0).toDouble().clamp(0.5, 2.0);
      _wsolaPitchShiftInPlace(left, right, sr, pitchRatio);
    }

    // 3. Áp dấu vân tay Vòm Họng (Vocal Tract Formant Fingerprint) theo F0 và Spectral Centroid của giọng đã lưu
    // Giúp phân biệt rõ ràng ngay cả giữa 2 giọng cùng là Nam (VD: Giọng Nam 1 ấm/dày vs Giọng Nam 2 thanh/sáng)
    final double chestGainDb =
        ((165.0 - params.targetProfileF0Hz) / 14.0).clamp(-3.5, 4.5) * convStrength;
    final double throatFormantFreq =
        (params.targetProfileF0Hz * 4.5).clamp(480.0, 1150.0);
    final double throatGainDb =
        ((params.targetProfileCentroidHz - 1800.0) / 240.0).clamp(-3.0, 3.5) * convStrength;
    final double brightnessDb =
        ((params.targetProfileCentroidHz - 1850.0) / 260.0).clamp(-3.5, 2.5) * convStrength;

    final chestL = _BiquadFilter.peaking(sr, 195.0, 0.9, chestGainDb);
    final chestR = _BiquadFilter.peaking(sr, 195.0, 0.9, chestGainDb);
    final throatL = _BiquadFilter.peaking(sr, throatFormantFreq, 1.4, throatGainDb);
    final throatR = _BiquadFilter.peaking(sr, throatFormantFreq, 1.4, throatGainDb);
    final brightL = _BiquadFilter.highShelf(sr, 3000.0, brightnessDb);
    final brightR = _BiquadFilter.highShelf(sr, 3000.0, brightnessDb);

    for (int i = 0; i < left.length; i++) {
      left[i] = brightL.process(throatL.process(chestL.process(left[i])));
      right[i] = brightR.process(throatR.process(chestR.process(right[i])));
    }

    return _VoiceConversionResult(
      detectedTrackF0Hz: trackF0,
      semitoneShift: semitoneShift,
    );
  }

  /// Bộ dịch cao độ chất lượng cao bằng **WSOLA (Waveform Similarity Overlap-Add) + Catmull-Rom Cubic Resampling**.
  /// Thay vì ghép hạt cố định gây triệt tiêu pha & rung tiếng (~21Hz tremolo), WSOLA tìm điểm khớp tương quan
  /// chéo cao nhất tại mỗi chu kỳ thanh quản để ghép sóng liền mạch tuyệt đối, giọng giữ nguyên độ trong và chắc.
  void _wsolaPitchShiftInPlace(
    Float64List left,
    Float64List right,
    int sr,
    double pitchRatio,
  ) {
    final int n = left.length;
    if (n < 2048 || (pitchRatio - 1.0).abs() < 0.005) return;

    final Float64List srcL = Float64List.fromList(left);
    final Float64List srcR = Float64List.fromList(right);

    const int winLen = 1024;
    const int hopOut = 512; // 50% Hann overlap -> tổng cửa sổ đúng bằng 1.0
    const int searchRadius = 220; // Quét ±5ms (bao phủ trọn vẹn chu kỳ F0 >= 100Hz)

    final int stretchedLen = (n * pitchRatio).round().clamp(winLen, n * 2 + winLen);
    final Float64List strL = Float64List(stretchedLen + winLen);
    final Float64List strR = Float64List(stretchedLen + winLen);
    final Float64List winNorm = Float64List(stretchedLen + winLen);

    final Float64List hann = Float64List(winLen);
    for (int i = 0; i < winLen; i++) {
      hann[i] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / winLen));
    }

    int prevInStart = 0;
    for (int outStart = 0; outStart < stretchedLen; outStart += hopOut) {
      final int nomInStart =
          (outStart / pitchRatio).round().clamp(0, math.max(0, n - winLen));

      int bestInStart = nomInStart;
      if (outStart > 0 && nomInStart > searchRadius && prevInStart + hopOut + winLen <= n) {
        final int refStart = prevInStart + hopOut;
        double refEnergy = 0.0;
        for (int k = 0; k < hopOut; k += 4) {
          final double r = 0.5 * (srcL[refStart + k] + srcR[refStart + k]);
          refEnergy += r * r;
        }

        if (refEnergy > 1e-6) {
          final int minSearch = math.max(0, nomInStart - searchRadius);
          final int maxSearch = math.min(n - winLen, nomInStart + searchRadius);

          // Tìm thô bước 4 mẫu
          double bestScore = -1e18;
          int coarseBest = nomInStart;
          for (int cand = minSearch; cand <= maxSearch; cand += 4) {
            double dot = 0.0;
            double candE = 1e-9;
            for (int k = 0; k < hopOut; k += 4) {
              final double r = 0.5 * (srcL[refStart + k] + srcR[refStart + k]);
              final double c = 0.5 * (srcL[cand + k] + srcR[cand + k]);
              dot += r * c;
              candE += c * c;
            }
            final double normScore = dot / math.sqrt(candE);
            if (normScore > bestScore) {
              bestScore = normScore;
              coarseBest = cand;
            }
          }

          // Tinh chỉnh chính xác từng mẫu quanh coarseBest ± 4
          bestScore = -1e18;
          final int fMin = math.max(minSearch, coarseBest - 4);
          final int fMax = math.min(maxSearch, coarseBest + 4);
          for (int cand = fMin; cand <= fMax; cand++) {
            double dot = 0.0;
            double candE = 1e-9;
            for (int k = 0; k < hopOut; k += 2) {
              final double r = 0.5 * (srcL[refStart + k] + srcR[refStart + k]);
              final double c = 0.5 * (srcL[cand + k] + srcR[cand + k]);
              dot += r * c;
              candE += c * c;
            }
            final double normScore = dot / math.sqrt(candE);
            if (normScore > bestScore) {
              bestScore = normScore;
              bestInStart = cand;
            }
          }
        }
      }

      for (int i = 0; i < winLen; i++) {
        final double w = hann[i];
        final int srcIdx = bestInStart + i;
        if (srcIdx < n) {
          strL[outStart + i] += srcL[srcIdx] * w;
          strR[outStart + i] += srcR[srcIdx] * w;
          winNorm[outStart + i] += w;
        }
      }
      prevInStart = bestInStart;
    }

    for (int i = 0; i < stretchedLen; i++) {
      final double wn = winNorm[i];
      if (wn > 1e-5) {
        strL[i] /= wn;
        strR[i] /= wn;
      }
    }

    // Bước 2: Nội suy Catmull-Rom Cubic 4-điểm để trả về đúng n mẫu (bảo toàn 100% thời lượng bài hát)
    final double maxPos = (stretchedLen - 3).toDouble();
    final antiAliasLpL = pitchRatio > 1.08
        ? _BiquadFilter.lowPass(sr, (8800.0 / pitchRatio).clamp(5200.0, 8800.0), 0.707)
        : null;
    final antiAliasLpR = pitchRatio > 1.08
        ? _BiquadFilter.lowPass(sr, (8800.0 / pitchRatio).clamp(5200.0, 8800.0), 0.707)
        : null;

    for (int i = 0; i < n; i++) {
      final double pos = (i * pitchRatio).clamp(1.0, maxPos);
      final int idx = pos.floor();
      final double t = pos - idx;

      double vL = _cubicInterp(strL[idx - 1], strL[idx], strL[idx + 1], strL[idx + 2], t);
      double vR = _cubicInterp(strR[idx - 1], strR[idx], strR[idx + 1], strR[idx + 2], t);

      if (antiAliasLpL != null && antiAliasLpR != null) {
        vL = antiAliasLpL.process(vL);
        vR = antiAliasLpR.process(vR);
      }

      left[i] = vL.clamp(-0.98, 0.98);
      right[i] = vR.clamp(-0.98, 0.98);
    }
  }

  double _cubicInterp(double y0, double y1, double y2, double y3, double t) {
    final double a0 = -0.5 * y0 + 1.5 * y1 - 1.5 * y2 + 0.5 * y3;
    final double a1 = y0 - 2.5 * y1 + 2.0 * y2 - 0.5 * y3;
    final double a2 = -0.5 * y0 + 0.5 * y2;
    final double a3 = y1;
    return ((a0 * t + a1) * t + a2) * t + a3;
  }

  void _applyNoiseGateAndDeEsser(
    Float64List left,
    Float64List right,
    int sr,
    DspParameters params,
    double intensity,
  ) {
    final double gateThreshLinear = _dbToLinear(params.noiseGateThresholdDb);
    final double deEssFreq = params.deEsserFrequencyHz.clamp(4500.0, 8000.0);
    final double deEssStrength =
        (params.deEsserAmount * intensity).clamp(0.20, 0.85);

    // Bộ lọc dò âm xì (Sibilance Detector Bandpass) ở tần số deEssFreq
    final sibDetectorL = _BiquadFilter.bandPass(sr, deEssFreq, 1.4);
    final sibDetectorR = _BiquadFilter.bandPass(sr, deEssFreq, 1.4);

    double gateEnv = 0.0;
    double gateGain = 0.0;

    for (int i = 0; i < left.length; i++) {
      final double absSample = 0.5 * (left[i].abs() + right[i].abs());
      if (absSample > gateEnv) {
        gateEnv = 0.985 * gateEnv + 0.015 * absSample;
      } else {
        gateEnv = 0.999 * gateEnv + 0.001 * absSample;
      }

      // Smooth Expander Noise Gate: khi ngừng hát thì dìm hẳn nhiễu nền xuống 0.05 để không còn tiếng xì xì
      final double targetGate = gateEnv < gateThreshLinear
          ? 0.05
          : ((gateEnv - gateThreshLinear) / (gateThreshLinear * 1.5 + 1e-4))
              .clamp(0.05, 1.0);
      gateGain = 0.995 * gateGain + 0.005 * targetGate;

      // Dynamic De-esser: Trích xuất thành phần âm xì chói và trừ bớt khi vượt ngưỡng
      final double sibL = sibDetectorL.process(left[i]);
      final double sibR = sibDetectorR.process(right[i]);
      final double sibEnv = 0.5 * (sibL.abs() + sibR.abs());

      double deEssCut = 0.12 * deEssStrength;
      if (sibEnv > 0.020) {
        deEssCut = deEssStrength * ((sibEnv - 0.015) / (sibEnv + 0.025));
      }

      left[i] = (left[i] - sibL * deEssCut) * gateGain;
      right[i] = (right[i] - sibR * deEssCut) * gateGain;
    }
  }

  /// Chỉnh cao độ (Auto-Tune) đồng bộ pha WSOLA không trộn chồng Dry/Wet:
  /// - Chỉ can thiệp khi cao độ thực tế bị lệch khỏi tâm nốt nhạc > 24 cents (bảo toàn luyến láy & rung tự nhiên).
  /// - Thay thế trực tiếp bằng khung sóng đồng bộ pha (Phase-Matched Overlap-Add) nên tuyệt đối không bị tiếng "rung pha / chorus".
  int _applyPitchCorrection(
    Float64List left,
    Float64List right,
    int sr,
    double strength,
    double retuneSpeed,
  ) {
    const int winLen = 1024;
    const int hopSize = 512;
    const int searchRadius = 160;
    final int n = left.length;
    if (n < winLen * 2) return 0;

    final Float64List outL = Float64List(n);
    final Float64List outR = Float64List(n);
    final Float64List winNorm = Float64List(n);
    final Float64List hann = Float64List(winLen);
    for (int i = 0; i < winLen; i++) {
      hann[i] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / winLen));
    }

    int correctedCount = 0;
    double smoothedRatio = 1.0;

    for (int start = 0; start + winLen <= n; start += hopSize) {
      final frameMono = Float64List(winLen);
      double energy = 0.0;
      for (int i = 0; i < winLen; i++) {
        final double m = 0.5 * (left[start + i] + right[start + i]);
        frameMono[i] = m;
        energy += m * m;
      }

      double targetRatio = 1.0;
      if (energy / winLen >= 1.5e-4) {
        final double detectedHz = _analyzer.detectPitchYin(frameMono, sr);
        if (detectedHz >= 85.0 && detectedHz <= 880.0) {
          final double midiNote =
              69.0 + 12.0 * (math.log(detectedHz / 440.0) / math.ln2);
          final double nearestMidi = midiNote.roundToDouble();
          final double centError = (midiNote - nearestMidi).abs() * 100.0;

          // Deadband 24 cents: giữ nguyên độ rung & luyến láy tự nhiên nếu hát đúng nốt
          if (centError > 24.0) {
            final double targetHz =
                440.0 * math.pow(2.0, (nearestMidi - 69.0) / 12.0);
            final double rawRatio = (targetHz / detectedHz).clamp(0.93, 1.07);
            targetRatio = 1.0 + (rawRatio - 1.0) * strength * 0.75;
          }
        }
      }

      smoothedRatio =
          (1.0 - retuneSpeed * 0.55) * smoothedRatio + (retuneSpeed * 0.55) * targetRatio;

      if ((smoothedRatio - 1.0).abs() <= 0.008) {
        // Không cần dịch cao độ -> giữ nguyên 100% tín hiệu gốc sạch sẽ
        for (int i = 0; i < winLen; i++) {
          final double w = hann[i];
          outL[start + i] += left[start + i] * w;
          outR[start + i] += right[start + i] * w;
          winNorm[start + i] += w;
        }
      } else {
        correctedCount++;
        // Khớp pha cạnh trái của khung với đoạn cuối đã ghi vào outL/outR (Phase-Aligned WSOLA)
        int alignedStart = start;
        if (start >= hopSize) {
          final int minCand = math.max(0, start - searchRadius);
          final int maxCand = math.min(n - winLen, start + searchRadius);
          double bestScore = -1e18;
          for (int cand = minCand; cand <= maxCand; cand += 3) {
            double dot = 0.0;
            double candE = 1e-9;
            for (int k = 0; k < 160; k += 2) {
              final double oVal =
                  winNorm[start + k] > 1e-4 ? outL[start + k] / winNorm[start + k] : left[start + k];
              final double cVal = left[cand + k];
              dot += oVal * cVal;
              candE += cVal * cVal;
            }
            final double score = dot / math.sqrt(candE);
            if (score > bestScore) {
              bestScore = score;
              alignedStart = cand;
            }
          }
        }

        for (int i = 0; i < winLen; i++) {
          final double w = hann[i];
          final double srcPos = (alignedStart + i * smoothedRatio).clamp(1.0, (n - 3).toDouble());
          final int idx = srcPos.floor();
          final double t = srcPos - idx;

          final double sL =
              _cubicInterp(left[idx - 1], left[idx], left[idx + 1], left[idx + 2], t);
          final double sR =
              _cubicInterp(right[idx - 1], right[idx], right[idx + 1], right[idx + 2], t);

          outL[start + i] += sL * w;
          outR[start + i] += sR * w;
          winNorm[start + i] += w;
        }
      }
    }

    for (int i = 0; i < n; i++) {
      final double wn = winNorm[i];
      if (wn > 1e-5) {
        left[i] = (outL[i] / wn).clamp(-0.98, 0.98);
        right[i] = (outR[i] / wn).clamp(-0.98, 0.98);
      }
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
    final double eqScale = (intensity * 1.15).clamp(0.0, 1.6);
    // Giới hạn mức tăng dải cao 10kHz (Air) tối đa +1.5dB và cắt mượt trên 9.5kHz để giữ giọng trong trẻo, không bị xì
    final double safeAirDb = (params.eqAir10kHzDb * eqScale).clamp(-4.0, 1.5);
    final List<_BiquadFilter> filtersL = [
      _BiquadFilter.lowShelf(sr, 115.0, params.eqSub100HzDb * eqScale),
      _BiquadFilter.peaking(sr, 280.0, 0.9, params.eqLowMid280HzDb * eqScale),
      _BiquadFilter.peaking(sr, 1200.0, 1.0, params.eqMid1200HzDb * eqScale),
      _BiquadFilter.peaking(
        sr,
        3200.0,
        0.9,
        (params.eqHighMid3500HzDb * eqScale).clamp(-4.0, 2.5),
      ),
      _BiquadFilter.highShelf(sr, 7500.0, safeAirDb),
      _BiquadFilter.lowPass(sr, 9500.0, 0.707),
    ];

    final List<_BiquadFilter> filtersR = [
      _BiquadFilter.lowShelf(sr, 115.0, params.eqSub100HzDb * eqScale),
      _BiquadFilter.peaking(sr, 280.0, 0.9, params.eqLowMid280HzDb * eqScale),
      _BiquadFilter.peaking(sr, 1200.0, 1.0, params.eqMid1200HzDb * eqScale),
      _BiquadFilter.peaking(
        sr,
        3200.0,
        0.9,
        (params.eqHighMid3500HzDb * eqScale).clamp(-4.0, 2.5),
      ),
      _BiquadFilter.highShelf(sr, 7500.0, safeAirDb),
      _BiquadFilter.lowPass(sr, 9500.0, 0.707),
    ];

    for (int i = 0; i < left.length; i++) {
      double sL = left[i];
      double sR = right[i];
      for (int b = 0; b < filtersL.length; b++) {
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
      _CombFilter((1310 * scale).round(), (0.64 + 0.16 * roomSize).clamp(0.55, 0.80), damping),
      _CombFilter((1385 * scale).round(), (0.63 + 0.16 * roomSize).clamp(0.54, 0.79), damping),
      _CombFilter((1245 * scale).round(), (0.62 + 0.16 * roomSize).clamp(0.53, 0.78), damping),
      _CombFilter((1180 * scale).round(), (0.60 + 0.16 * roomSize).clamp(0.52, 0.76), damping),
    ];
    final List<_CombFilter> combsR = [
      _CombFilter(((1310 + 29) * scale).round(), (0.64 + 0.16 * roomSize).clamp(0.55, 0.80), damping),
      _CombFilter(((1385 + 29) * scale).round(), (0.63 + 0.16 * roomSize).clamp(0.54, 0.79), damping),
      _CombFilter(((1245 + 29) * scale).round(), (0.62 + 0.16 * roomSize).clamp(0.53, 0.78), damping),
      _CombFilter(((1180 + 29) * scale).round(), (0.60 + 0.16 * roomSize).clamp(0.52, 0.76), damping),
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

      // 2. Tính Stereo Reverb (cân chỉnh độ vang vừa phải, trong trẻo không bị ù/nhòe)
      final double revInL = reverbHpL.process(dryL) * 0.30;
      final double revInR = reverbHpR.process(dryR) * 0.30;
      double revOutL = 0.0;
      double revOutR = 0.0;
      for (int c = 0; c < 4; c++) {
        revOutL += combsL[c].process(revInL);
        revOutR += combsR[c].process(revInR);
      }
      revOutL = apL2.process(apL1.process(revOutL));
      revOutR = apR2.process(apR1.process(revOutR));

      left[i] = dryL * (1.0 - wetReverb * 0.15) +
          delOutL * wetDelay * 0.90 +
          revOutL * wetReverb * 0.95;
      right[i] = dryR * (1.0 - wetReverb * 0.15) +
          delOutR * wetDelay * 0.90 +
          revOutR * wetReverb * 0.95;
    }
  }

  double _dbToLinear(double db) => math.pow(10.0, db / 20.0).toDouble();

  double _warmHarmonicExciter(double x) {
    // Giữ độ trong trẻo tuyệt đối cho giọng hát (loại bỏ méo hài bậc 2 gây cảm giác rè nhẹ)
    return x;
  }

  double _softClipLimiter(double x) {
    const double ceiling = 0.96;
    if (x.abs() <= 0.75) return x;
    final double sign = x >= 0 ? 1.0 : -1.0;
    final double excess = x.abs() - 0.75;
    return sign * (0.75 + (ceiling - 0.75) * (1.0 - math.exp(-excess * 4.5)));
  }
}

class _VoiceConversionResult {
  final double detectedTrackF0Hz;
  final double semitoneShift;

  const _VoiceConversionResult({
    required this.detectedTrackF0Hz,
    required this.semitoneShift,
  });
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

  factory _BiquadFilter.lowPass(int sampleRate, double freq, double q) {
    final double w0 = 2.0 * math.pi * freq / sampleRate;
    final double cosW = math.cos(w0);
    final double alpha = math.sin(w0) / (2.0 * q);
    final double a0 = 1.0 + alpha;
    final double b1 = 1.0 - cosW;
    final double b0 = b1 / 2.0;
    return _BiquadFilter(
      b0 / a0,
      b1 / a0,
      b0 / a0,
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
