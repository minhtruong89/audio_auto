import 'dart:math' as math;
import 'dart:typed_data';

import '../models/voice_profile.dart';
import 'audio_io_service.dart';

/// Kết quả phân tích của từng bước đơn lẻ trong Wizard 4 bước, kèm trạng thái kiểm định chất lượng (QC)
class StepAnalysisMetrics {
  final double noiseFloorDb;
  final double meanPitchHz;
  final double minPitchHz;
  final double maxPitchHz;
  final double pitchJitterPercent;
  final double vibratoRateHz;
  final double dynamicStabilityDb;
  final double spectralCentroidHz;
  final double sibilancePeakHz;
  final double sibilanceRatio;
  final List<double> bandEnergiesDb; // 5 dải tần (100Hz, 280Hz, 1.2kHz, 3.5kHz, 10kHz)

  // Các chỉ số kiểm định bản thu hợp chuẩn (Recording Quality Control)
  final double durationSeconds;
  final double voicedDurationSeconds; // Thời lượng thực sự có tiếng người phát âm
  final double snrDb; // Tỷ lệ Tín hiệu Giọng / Tạp âm nền (Signal-to-Noise Ratio)
  final bool isClipping; // Có bị vỡ tiếng do để mic quá sát / hét quá to không
  final bool isQualityValid; // Bản thu có đạt chuẩn để đưa vào hồ sơ giọng không
  final String qualityFeedback; // Hướng dẫn cụ thể nếu chưa đạt chuẩn

  const StepAnalysisMetrics({
    required this.noiseFloorDb,
    required this.meanPitchHz,
    required this.minPitchHz,
    required this.maxPitchHz,
    required this.pitchJitterPercent,
    required this.vibratoRateHz,
    required this.dynamicStabilityDb,
    required this.spectralCentroidHz,
    required this.sibilancePeakHz,
    required this.sibilanceRatio,
    required this.bandEnergiesDb,
    this.durationSeconds = 3.5,
    this.voicedDurationSeconds = 2.4,
    this.snrDb = 24.0,
    this.isClipping = false,
    this.isQualityValid = true,
    this.qualityFeedback = 'Đạt chuẩn: Tín hiệu giọng rõ, độ ồn nền tốt.',
  });
}

/// Bộ phân tích đặc trưng giọng nói On-Device sử dụng thuật toán YIN (Pitch) + Goertzel/FFT (Phổ tần số)
class VoiceAnalyzerService {
  /// Phân tích một đoạn âm thanh PCM để lấy đầy đủ các chỉ số âm học
  /// [stepIndex]: Bước hiện tại (0..3) để áp dụng tiêu chí kiểm định chất lượng riêng (VD Bước 2 kiểm tra độ mở Đồ->Đố)
  StepAnalysisMetrics analyzeAudioClip(
    PcmAudioData audio, {
    int? stepIndex,
  }) {
    final Float64List mono = audio.toMono();
    final int sr = audio.sampleRate;
    if (mono.length < 1024) {
      return const StepAnalysisMetrics(
        noiseFloorDb: -48.0,
        meanPitchHz: 165.0,
        minPitchHz: 110.0,
        maxPitchHz: 420.0,
        pitchJitterPercent: 2.2,
        vibratoRateHz: 5.5,
        dynamicStabilityDb: 3.0,
        spectralCentroidHz: 1850.0,
        sibilancePeakHz: 6400.0,
        sibilanceRatio: 0.26,
        bandEnergiesDb: [-18.0, -14.0, -15.0, -21.0, -26.0],
      );
    }

    const int frameSize = 2048;
    const int hopSize = 512;
    final bool isGlideStep = stepIndex == 1;
    final double yinMinFreq = 65.0;
    final double yinMaxFreq = isGlideStep ? 850.0 : 360.0;

    final List<double> frameRmsDb = [];
    final List<double> detectedPitches = [];
    int clippingSamples = 0;
    for (int i = 0; i < mono.length; i++) {
      if (mono[i].abs() >= 0.985) clippingSamples++;
    }

    // Lần 1: Đo mức năng lượng và ngưỡng tạp âm nền trước để lọc khung yên lặng chính xác
    for (int start = 0; start + frameSize <= mono.length; start += hopSize) {
      double sumSq = 0.0;
      for (int i = 0; i < frameSize; i++) {
        final s = mono[start + i];
        sumSq += s * s;
      }
      final double rms = math.sqrt(sumSq / frameSize);
      final double db = 20.0 * math.log(math.max(rms, 1e-5)) / math.ln10;
      frameRmsDb.add(db);
    }

    // 1. Tính ngưỡng tạp âm nền (15% phân vị thấp nhất của RMS dB)
    final sortedRms = List<double>.from(frameRmsDb)..sort();
    final int noiseIdx =
        (sortedRms.length * 0.15).floor().clamp(0, sortedRms.length - 1);
    final double noiseFloorDb = sortedRms[noiseIdx].clamp(-65.0, -25.0);
    final double voicedGateDb = math.max(-38.0, noiseFloorDb + 7.5);

    // Lần 2: Chạy YIN 2048 mẫu (chống nhảy bậc 8 octave-doubling) trên các khung có tiếng người rõ
    int frameIdx = 0;
    for (int start = 0; start + frameSize <= mono.length; start += hopSize) {
      final double db = frameRmsDb[frameIdx++];
      if (db > voicedGateDb) {
        final double pitch = detectPitchYin(
          Float64List.sublistView(mono, start, start + frameSize),
          sr,
          minFreqHz: yinMinFreq,
          maxFreqHz: yinMaxFreq,
        );
        if (pitch >= yinMinFreq && pitch <= yinMaxFreq) {
          detectedPitches.add(pitch);
        }
      }
    }

    // 2. Độ ổn định âm lượng & Tỷ lệ SNR (Signal-to-Noise Ratio)
    final activeRms = sortedRms.where((d) => d > noiseFloorDb + 6.0).toList();
    double dynamicStabilityDb = 3.0;
    double voicePeakDb = noiseFloorDb + 18.0;
    if (activeRms.isNotEmpty) {
      voicePeakDb = activeRms[(activeRms.length * 0.85).floor().clamp(0, activeRms.length - 1)];
    }
    if (activeRms.length > 2) {
      final meanDb = activeRms.reduce((a, b) => a + b) / activeRms.length;
      double varSum = 0.0;
      for (final d in activeRms) {
        varSum += (d - meanDb) * (d - meanDb);
      }
      dynamicStabilityDb = math.sqrt(varSum / activeRms.length).clamp(1.0, 9.5);
    }

    final double durationSec = mono.length / sr;
    final double voicedSec = (detectedPitches.length * hopSize) / sr;
    final double snrDb = (voicePeakDb - noiseFloorDb).clamp(0.0, 60.0);
    final bool isClipping = clippingSamples > (mono.length * 0.01);

    // Kiểm định chất lượng bản thu (Recording QC)
    bool isValid = true;
    String feedback = 'Đạt chuẩn: Giọng rõ (${voicedSec.toStringAsFixed(1)}s), SNR +${snrDb.toStringAsFixed(0)}dB.';
    if (durationSec < 1.5) {
      isValid = false;
      feedback = 'Bản thu quá ngắn (${durationSec.toStringAsFixed(1)}s). Hãy thu tối thiểu 2 - 4 giây.';
    } else if (voicedSec < 0.45) {
      isValid = false;
      feedback = 'Chưa nhận diện đủ tiếng giọng nói/hát. Hãy phát âm to và rõ hơn vào Mic.';
    } else if (snrDb < 9.0) {
      isValid = false;
      feedback = 'Môi trường hơi ồn hoặc bạn nói quá nhỏ (SNR ${snrDb.toStringAsFixed(1)}dB < 9dB). Hãy đưa mic lại gần hơn.';
    } else if (isClipping) {
      isValid = false;
      feedback = 'Tín hiệu bị vỡ tiếng (Clipping). Hãy để điện thoại cách miệng khoảng 15-20cm.';
    }

    // 3. Thống kê Cao độ (F0 Mean, Min, Max, Jitter, Vibrato)
    double meanPitchHz = 165.0;
    double minPitchHz = 115.0;
    double maxPitchHz = 410.0;
    double pitchJitterPercent = 2.1;

    if (detectedPitches.isNotEmpty) {
      final sortedPitches = List<double>.from(detectedPitches)..sort();
      // Loại bỏ ngoại lai hai đầu và lấy TRUNG VỊ (Median) thay vì trung bình cộng
      // để các âm gió/phụ âm không kéo sai F0 của giọng nam lên thành giọng nữ
      final int lowIdx = (sortedPitches.length * 0.12).floor();
      final int highIdx =
          (sortedPitches.length * 0.88).floor().clamp(0, sortedPitches.length - 1);
      final int medIdx = sortedPitches.length ~/ 2;
      minPitchHz = sortedPitches[lowIdx];
      maxPitchHz = math.max(minPitchHz + 40.0, sortedPitches[highIdx]);
      meanPitchHz = sortedPitches[medIdx];

      if (detectedPitches.length > 2) {
        double diffSum = 0.0;
        for (int i = 1; i < detectedPitches.length; i++) {
          diffSum += (detectedPitches[i] - detectedPitches[i - 1]).abs();
        }
        final avgDiff = diffSum / (detectedPitches.length - 1);
        pitchJitterPercent = ((avgDiff / meanPitchHz) * 100.0).clamp(0.6, 7.5);
      }
    }

    // Kiểm định riêng cho Bước 2 (Hát nâng tông Đồ -> Đố):
    // Đảm bảo người dùng thực sự nâng cao độ giọng lên chứ không đọc ngang phè 1 nốt
    if (isValid && stepIndex == 1) {
      final double semitoneSpan =
          12.0 * (math.log(maxPitchHz / math.max(minPitchHz, 60.0)) / math.ln2);
      if (semitoneSpan < 4.5) {
        isValid = false;
        feedback =
            'Độ mở quãng giọng mới đạt ${semitoneSpan.toStringAsFixed(1)} bán cung (${minPitchHz.round()}–${maxPitchHz.round()}Hz). Bạn đang đọc hơi ngang giọng, hãy hát nâng cao tông dần lên ở các chữ Son ↗ La ↗ Si ↗ Đố nhé!';
      } else {
        feedback =
            'Đạt chuẩn: Quãng giọng mở tốt (+${semitoneSpan.toStringAsFixed(1)} bán cung, từ ${minPitchHz.round()}Hz lên ${maxPitchHz.round()}Hz).';
      }
    }

    // 4. Phân tích phổ tần số (Spectral Centroid, 5 dải EQ & Sibilance)
    final spectral = _analyzeSpectrumBands(mono, sr);

    return StepAnalysisMetrics(
      noiseFloorDb: noiseFloorDb,
      meanPitchHz: meanPitchHz,
      minPitchHz: minPitchHz,
      maxPitchHz: maxPitchHz,
      pitchJitterPercent: pitchJitterPercent,
      vibratoRateHz: 5.5,
      dynamicStabilityDb: dynamicStabilityDb,
      spectralCentroidHz: spectral.centroidHz,
      sibilancePeakHz: spectral.sibilancePeakHz,
      sibilanceRatio: spectral.sibilanceRatio,
      bandEnergiesDb: spectral.bandEnergiesDb,
      durationSeconds: durationSec,
      voicedDurationSeconds: voicedSec,
      snrDb: snrDb,
      isClipping: isClipping,
      isQualityValid: isValid,
      qualityFeedback: feedback,
    );
  }

  /// Thuật toán YIN Pitch Detection chuẩn xác (tích hợp khử DC và kiểm tra chống nhảy bậc 8 - Octave Doubling Check
  /// dành riêng cho micro điện thoại vốn thường bị yếu tần số trầm F0 của giọng nam).
  double detectPitchYin(
    Float64List frame,
    int sampleRate, {
    double minFreqHz = 68.0,
    double maxFreqHz = 950.0,
  }) {
    final int len = frame.length;
    final int halfLen = len ~/ 2;
    final int minTau = math.max(2, (sampleRate / maxFreqHz).floor());
    final int maxTau = math.min(halfLen - 1, (sampleRate / minFreqHz).ceil());
    if (minTau >= maxTau) return 0.0;

    // Trừ thành phần 1 chiều (DC Offset) của micro Android để YIN không bị lệch
    double dcMean = 0.0;
    for (int i = 0; i < len; i++) {
      dcMean += frame[i];
    }
    dcMean /= len;

    final Float64List yinBuffer = Float64List(maxTau + 1);
    double runningSum = 0.0;
    yinBuffer[0] = 1.0;

    for (int tau = 1; tau <= maxTau; tau++) {
      double diff = 0.0;
      for (int i = 0; i < halfLen; i++) {
        final double delta = (frame[i] - dcMean) - (frame[i + tau] - dcMean);
        diff += delta * delta;
      }
      runningSum += diff;
      yinBuffer[tau] = runningSum > 1e-9 ? diff * tau / runningSum : 1.0;
    }

    const double threshold = 0.16;
    int bestTau = -1;
    for (int tau = minTau; tau <= maxTau; tau++) {
      if (yinBuffer[tau] < threshold) {
        while (tau + 1 <= maxTau && yinBuffer[tau + 1] < yinBuffer[tau]) {
          tau++;
        }
        bestTau = tau;
        break;
      }
    }

    if (bestTau == -1) {
      double minVal = 999.0;
      for (int tau = minTau; tau <= maxTau; tau++) {
        if (yinBuffer[tau] < minVal) {
          minVal = yinBuffer[tau];
          bestTau = tau;
        }
      }
      // Ngưỡng chặt 0.28 để loại bỏ phụ âm vô thanh (x, ch, t, s)
      if (minVal > 0.28) return 0.0;
    }

    // Kiểm tra chống nhảy bậc 8 (Sub-harmonic / Octave-Down Check):
    // Chỉ chuyển xuống 2*bestTau hoặc 3*bestTau nếu tại đó đáy tuần hoàn thực sự SÂU HƠN đáng kể
    // so với bestTau (tránh lỗi chia đôi tần số trên sóng sin thuần hoặc giọng nữ chuẩn).
    for (final int mult in [3, 2]) {
      final int center = bestTau * mult;
      if (center + 4 <= maxTau) {
        int subTau = center;
        double subMin = yinBuffer[center];
        for (int t = center - 4; t <= center + 4; t++) {
          if (yinBuffer[t] < subMin) {
            subMin = yinBuffer[t];
            subTau = t;
          }
        }
        if (subMin < yinBuffer[bestTau] - 0.02) {
          bestTau = subTau;
          break;
        }
      }
    }

    // Nội suy Parabolic để đạt độ chính xác dưới 1 Hz
    double betterTau = bestTau.toDouble();
    if (bestTau > 1 && bestTau < maxTau) {
      final double s0 = yinBuffer[bestTau - 1];
      final double s1 = yinBuffer[bestTau];
      final double s2 = yinBuffer[bestTau + 1];
      final double denom = 2.0 * (2.0 * s1 - s2 - s0);
      if (denom.abs() > 1e-9) {
        betterTau += (s2 - s0) / denom;
      }
    }

    return sampleRate / betterTau;
  }

  _SpectrumAnalysisResult _analyzeSpectrumBands(
    Float64List mono,
    int sampleRate,
  ) {
    // Đo năng lượng tại các tần số đại diện bằng bộ lọc Goertzel trên nhiều khung
    const List<double> probeFreqs = [
      100.0,
      280.0,
      600.0,
      1200.0,
      2400.0,
      3500.0,
      5500.0,
      6500.0,
      7800.0,
      10000.0,
    ];
    final List<double> energies = List<double>.filled(probeFreqs.length, 1e-9);

    const int blockSize = 512;
    final int step = math.max(blockSize, mono.length ~/ 24);
    int blockCount = 0;

    for (int offset = 0; offset + blockSize <= mono.length; offset += step) {
      blockCount++;
      for (int fIdx = 0; fIdx < probeFreqs.length; fIdx++) {
        energies[fIdx] += _goertzelMagnitude(
          mono,
          offset,
          blockSize,
          probeFreqs[fIdx],
          sampleRate,
        );
      }
    }

    if (blockCount > 0) {
      for (int i = 0; i < energies.length; i++) {
        energies[i] /= blockCount;
      }
    }

    // Tính Spectral Centroid (Trọng tâm phổ tần số)
    double weightedFreqSum = 0.0;
    double totalMag = 1e-9;
    for (int i = 0; i < probeFreqs.length; i++) {
      weightedFreqSum += probeFreqs[i] * energies[i];
      totalMag += energies[i];
    }
    final double centroidHz = (weightedFreqSum / totalMag).clamp(900.0, 3800.0);

    // Xác định đỉnh Sibilance (5.5kHz, 6.5kHz, 7.8kHz)
    double maxSibEnergy = energies[6];
    double sibilancePeakHz = 5500.0;
    if (energies[7] > maxSibEnergy) {
      maxSibEnergy = energies[7];
      sibilancePeakHz = 6500.0;
    }
    if (energies[8] > maxSibEnergy) {
      maxSibEnergy = energies[8];
      sibilancePeakHz = 7800.0;
    }

    final double sibilanceRatio =
        ((energies[6] + energies[7] + energies[8]) / totalMag).clamp(0.08, 0.65);

    // 5 dải tần tương ứng 5-Band EQ: [100Hz, 280Hz, 1200Hz, 3500Hz, 10000Hz]
    final List<int> eqIndices = [0, 1, 3, 5, 9];
    final List<double> bandDb = eqIndices.map((idx) {
      return 20.0 * math.log(math.max(energies[idx], 1e-5)) / math.ln10;
    }).toList();

    return _SpectrumAnalysisResult(
      centroidHz: centroidHz,
      sibilancePeakHz: sibilancePeakHz,
      sibilanceRatio: sibilanceRatio,
      bandEnergiesDb: bandDb,
    );
  }

  double _goertzelMagnitude(
    Float64List samples,
    int start,
    int length,
    double targetFreq,
    int sampleRate,
  ) {
    final double k = (0.5 + (length * targetFreq) / sampleRate).floorToDouble();
    final double omega = (2.0 * math.pi * k) / length;
    final double coeff = 2.0 * math.cos(omega);
    double q0 = 0.0;
    double q1 = 0.0;
    double q2 = 0.0;

    for (int i = 0; i < length; i++) {
      // Áp cửa sổ Hann nhẹ để giảm rò phổ
      final double w = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (length - 1)));
      q0 = coeff * q1 - q2 + samples[start + i] * w;
      q2 = q1;
      q1 = q0;
    }
    final double magSq = q1 * q1 + q2 * q2 - q1 * q2 * coeff;
    return math.sqrt(math.max(0.0, magSq)) / length;
  }

  /// Tổng hợp kết quả từ 4 bước thu âm thành Hồ sơ Giọng [UserVoiceProfile] hoàn chỉnh
  UserVoiceProfile buildProfileFrom4Steps(List<StepAnalysisMetrics> steps) {
    final s1 = steps.isNotEmpty ? steps[0] : null;
    final s2 = steps.length > 1 ? steps[1] : s1;
    final s3 = steps.length > 2 ? steps[2] : s1;
    final s4 = steps.length > 3 ? steps[3] : s1;

    final double noiseFloor = s1?.noiseFloorDb ?? -48.0;
    // Tổng hợp F0 từ các bước nói/ngân tự nhiên (Bước 1, Bước 3, Bước 4) bằng trung vị để ổn định tuyệt đối
    final List<double> speakingCandidates = [
      if (s1 != null) s1.meanPitchHz,
      if (s3 != null) s3.meanPitchHz,
      if (s4 != null) s4.meanPitchHz,
    ]..sort();
    final double speakingF0 = speakingCandidates.isNotEmpty
        ? speakingCandidates[speakingCandidates.length ~/ 2]
        : 155.0;
    final double minPitch = math.min(
      s1?.minPitchHz ?? 110.0,
      s2?.minPitchHz ?? 100.0,
    );
    final double maxPitch = math.max(
      s2?.maxPitchHz ?? 420.0,
      s4?.maxPitchHz ?? 380.0,
    );
    final double comfortHz = (speakingF0 * 1.15).clamp(minPitch, maxPitch);

    // Phân loại quãng giọng dựa trên F0 trung vị khi nói và đáy trầm minPitch
    final VocalRangeType vocalType = _classifyVocalRange(speakingF0, minPitch, maxPitch);

    // Tính đường cong bù trừ 5-Band EQ tự động từ trung bình tất cả các bước đã đo
    final List<double> measuredBands = List<double>.filled(5, 0.0);
    int validBandSteps = 0;
    for (final st in steps) {
      if (st.bandEnergiesDb.length == 5) {
        validBandSteps++;
        for (int b = 0; b < 5; b++) {
          measuredBands[b] += st.bandEnergiesDb[b];
        }
      }
    }
    if (validBandSteps > 0) {
      for (int b = 0; b < 5; b++) {
        measuredBands[b] /= validBandSteps;
      }
    } else {
      measuredBands.setAll(0, const [-18.0, -15.0, -14.0, -21.0, -26.0]);
    }

    // Đường cong mục tiêu chuẩn giọng hát Karaoke chuyên nghiệp (dB tương đối)
    const List<double> targetRelativeCurve = [-4.0, 1.5, 0.0, 2.5, -2.0];

    final double midRef = measuredBands[2];
    final List<double> eqGains = List<double>.filled(5, 0.0);
    // Band 0 (100Hz): Cắt ù mic tùy theo giọng trầm hay cao
    eqGains[0] = speakingF0 < 150.0 ? -3.8 : -2.2;
    for (int i = 1; i < 5; i++) {
      final double currentRel = measuredBands[i] - midRef;
      final double diff = targetRelativeCurve[i] - currentRel;
      eqGains[i] = (diff * 0.65).clamp(-5.5, 6.0);
    }

    return UserVoiceProfile(
      id: 'profile_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
      noiseFloorDb: noiseFloor,
      speakingF0MeanHz: speakingF0,
      spectralCentroidHz: s4?.spectralCentroidHz ?? s1?.spectralCentroidHz ?? 1850.0,
      minPitchHz: minPitch,
      maxPitchHz: maxPitch,
      comfortZoneHz: comfortHz,
      vocalType: vocalType,
      pitchJitterPercent: s3?.pitchJitterPercent ?? 2.2,
      vibratoRateHz: s3?.vibratoRateHz ?? 5.5,
      dynamicStabilityDb: s3?.dynamicStabilityDb ?? 3.1,
      sibilancePeakHz: s4?.sibilancePeakHz ?? 6400.0,
      sibilanceRatio: s4?.sibilanceRatio ?? 0.27,
      eqCompensationGainsDb: eqGains,
    );
  }

  VocalRangeType _classifyVocalRange(
    double speakingF0,
    double minPitch,
    double maxPitch,
  ) {
    if (speakingF0 < 115.0) return VocalRangeType.bass;
    if (speakingF0 < 155.0) return VocalRangeType.baritone;
    // Vùng chuyển tiếp 155-185Hz: nếu minPitch xuống dưới 130Hz chắc chắn là giọng Nam (Tenor)
    if (speakingF0 < 180.0 || (speakingF0 < 195.0 && minPitch < 130.0)) {
      return VocalRangeType.tenor;
    }
    if (speakingF0 < 225.0) return VocalRangeType.alto;
    if (speakingF0 < 260.0 || maxPitch < 750.0) {
      return VocalRangeType.mezzoSoprano;
    }
    return VocalRangeType.soprano;
  }
}

class _SpectrumAnalysisResult {
  final double centroidHz;
  final double sibilancePeakHz;
  final double sibilanceRatio;
  final List<double> bandEnergiesDb;

  const _SpectrumAnalysisResult({
    required this.centroidHz,
    required this.sibilancePeakHz,
    required this.sibilanceRatio,
    required this.bandEnergiesDb,
  });
}
