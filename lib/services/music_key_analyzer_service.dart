import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_io_service.dart';
import 'voice_analyzer_service.dart';

/// Kết quả nhận diện Tông Nhạc (Musical Key) và mức lệch tông giữa Giọng hát & Nhạc nền
class DetectedMusicKey {
  final int rootPitchClass; // 0=C, 1=C#, ..., 11=B
  final bool isMinor;
  final String shortName; // VD: "Am", "C", "F#m"
  final String labelVi; // VD: "La thứ (Am)", "Đô trưởng (C)"
  final double confidence; // 0.0 -> 1.0
  final List<double> musicChroma; // Phổ 12 bán cung của Nhạc nền
  final int suggestedVocalShiftSemitones; // Độ lệch đề xuất [-4..+4] để khớp Giọng vào Nhạc

  const DetectedMusicKey({
    required this.rootPitchClass,
    required this.isMinor,
    required this.shortName,
    required this.labelVi,
    required this.confidence,
    required this.musicChroma,
    required this.suggestedVocalShiftSemitones,
  });

  /// Trả về tập hợp 7 bậc âm giai (Pitch Classes 0..11) hợp lệ của tông nhạc hiện tại
  /// (có tính đến trường hợp người dùng đã dịch Tone Nhạc bằng [transposeSemitones]).
  Set<int> scalePitchClasses({int transposeSemitones = 0}) {
    final int shiftedRoot = (rootPitchClass + transposeSemitones) % 12;
    final int safeRoot = shiftedRoot < 0 ? shiftedRoot + 12 : shiftedRoot;
    const majorIntervals = [0, 2, 4, 5, 7, 9, 11];
    const minorIntervals = [0, 2, 3, 5, 7, 8, 10];
    final intervals = isMinor ? minorIntervals : majorIntervals;
    return intervals.map((step) => (safeRoot + step) % 12).toSet();
  }
}

/// Bộ phân tích Tông Nhạc & Hợp Âm On-Device bằng **Chromagram 12-Bin + Krumhansl-Schmuckler Key Profiles**.
class MusicKeyAnalyzerService {
  static const List<String> _noteNamesEn = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  static const List<String> _noteNamesVi = [
    'Đô',
    'Đô#',
    'Rê',
    'Rê#',
    'Mi',
    'Pha',
    'Pha#',
    'Son',
    'Son#',
    'La',
    'La#',
    'Si',
  ];

  // Hệ số tương quan chuẩn Krumhansl-Schmuckler cho 24 giọng Trưởng / Thứ
  static const List<double> _majorProfile = [
    6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88,
  ];
  static const List<double> _minorProfile = [
    6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17,
  ];

  final VoiceAnalyzerService _pitchDetector = VoiceAnalyzerService();

  /// Phân tích đồng thời Chromagram của [musicStem] và biểu đồ cao độ của [vocalStem]
  /// để tìm ra Tông bài hát + phát hiện độ lệch bán cung nếu người hát bị lệch tông.
  DetectedMusicKey analyzeKeys({
    required PcmAudioData musicStem,
    required PcmAudioData vocalStem,
  }) {
    final List<double> musicChroma = _extractStftChromagram(musicStem);
    final List<double> vocalChroma = _extractVocalChromagram(vocalStem);

    // 1. Chấm điểm 24 giọng (12 Trưởng + 12 Thứ) bằng hệ số tương quan Pearson
    int bestRoot = 0;
    bool bestMinor = false;
    double bestCorr = -999.0;
    double secondCorr = -999.0;

    for (int root = 0; root < 12; root++) {
      final double majorCorr = _pearsonCircular(musicChroma, _majorProfile, root);
      if (majorCorr > bestCorr) {
        secondCorr = bestCorr;
        bestCorr = majorCorr;
        bestRoot = root;
        bestMinor = false;
      } else if (majorCorr > secondCorr) {
        secondCorr = majorCorr;
      }

      final double minorCorr = _pearsonCircular(musicChroma, _minorProfile, root);
      if (minorCorr > bestCorr) {
        secondCorr = bestCorr;
        bestCorr = minorCorr;
        bestRoot = root;
        bestMinor = true;
      } else if (minorCorr > secondCorr) {
        secondCorr = minorCorr;
      }
    }

    // 2. Tính độ lệch bán cung giữa Vocal Chroma và Âm giai 7 nốt của Music Key
    int suggestedShift = 0;
    final double vocalSum = vocalChroma.fold(0.0, (a, b) => a + b);
    if (vocalSum > 1e-4) {
      double bestScore = -1.0;
      double zeroScore = 0.0;
      final List<double> scaleMask = List<double>.filled(12, 0.0);
      const majorIntervals = [0, 2, 4, 5, 7, 9, 11];
      const minorIntervals = [0, 2, 3, 5, 7, 8, 10];
      for (final step in (bestMinor ? minorIntervals : majorIntervals)) {
        scaleMask[(bestRoot + step) % 12] = 1.0;
      }
      // Ưu tiên thêm các bậc trụ (I, III, V)
      scaleMask[bestRoot] = 1.6;
      scaleMask[(bestRoot + (bestMinor ? 3 : 4)) % 12] = 1.3;
      scaleMask[(bestRoot + 7) % 12] = 1.4;

      for (int shift = -4; shift <= 4; shift++) {
        double score = 0.0;
        for (int pc = 0; pc < 12; pc++) {
          final int targetPc = ((pc + shift) % 12 + 12) % 12;
          score += vocalChroma[pc] * scaleMask[targetPc];
        }
        // Ưu tiên giữ 0 nếu độ lệch quá nhỏ để không nhảy sai vào quãng 4/5
        final double adjustedScore =
            shift == 0 ? score + 0.06 : score - shift.abs() * 0.012;
        if (shift == 0) zeroScore = adjustedScore;
        if (adjustedScore > bestScore) {
          bestScore = adjustedScore;
          suggestedShift = shift;
        }
      }
      if (bestScore <= zeroScore + 0.03) {
        suggestedShift = 0;
      }
    }

    final String shortName =
        '${_noteNamesEn[bestRoot]}${bestMinor ? "m" : ""}';
    final String labelVi =
        '${_noteNamesVi[bestRoot]} ${bestMinor ? "thứ" : "trưởng"} ($shortName)';
    final double conf =
        (0.45 + (bestCorr - secondCorr).clamp(0.0, 0.55)).clamp(0.35, 0.99);

    return DetectedMusicKey(
      rootPitchClass: bestRoot,
      isMinor: bestMinor,
      shortName: shortName,
      labelVi: labelVi,
      confidence: conf,
      musicChroma: musicChroma,
      suggestedVocalShiftSemitones: suggestedShift,
    );
  }

  /// Trích xuất biểu đồ Chromagram 12 bán cung từ luồng Nhạc nền bằng FFT 4096 điểm
  List<double> _extractStftChromagram(PcmAudioData audio) {
    final List<double> chroma = List<double>.filled(12, 0.0);
    final int n = audio.length;
    final int sr = audio.sampleRate;
    const int fftSize = 4096;
    if (n < fftSize) return List<double>.filled(12, 1.0 / 12.0);

    final int numFrames = math.min(28, math.max(4, n ~/ fftSize));
    final int hop = math.max(1, (n - fftSize) ~/ math.max(1, numFrames - 1));
    final Float64List hann = Float64List(fftSize);
    for (int i = 0; i < fftSize; i++) {
      hann[i] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / fftSize));
    }

    final Float64List re = Float64List(fftSize);
    final Float64List im = Float64List(fftSize);
    final double binHz = sr / fftSize;
    final int minBin = math.max(1, (65.0 / binHz).floor());
    final int maxBin = math.min(fftSize ~/ 2, (1800.0 / binHz).ceil());

    for (int f = 0; f < numFrames; f++) {
      final int start = f * hop;
      if (start + fftSize > n) break;
      for (int i = 0; i < fftSize; i++) {
        final double m =
            0.5 * (audio.leftChannel[start + i] + audio.rightChannel[start + i]);
        re[i] = m * hann[i];
        im[i] = 0.0;
      }
      _fftRadix2(re, im);

      for (int b = minBin; b <= maxBin; b++) {
        final double mag = math.sqrt(re[b] * re[b] + im[b] * im[b]);
        if (mag < 1e-5) continue;
        final double freq = b * binHz;
        final double midi = 69.0 + 12.0 * (math.log(freq / 440.0) / math.ln2);
        final int pc = ((midi.round() % 12) + 12) % 12;
        chroma[pc] += mag;
      }
    }

    final double sum = chroma.fold(0.0, (a, b) => a + b);
    if (sum > 1e-9) {
      for (int i = 0; i < 12; i++) {
        chroma[i] /= sum;
      }
    }
    return chroma;
  }

  /// Trích xuất phân bố 12 nốt nhạc thực tế của Giọng hát (qua YIN F0)
  List<double> _extractVocalChromagram(PcmAudioData vocal) {
    final List<double> chroma = List<double>.filled(12, 0.0);
    final int n = vocal.length;
    final int sr = vocal.sampleRate;
    const int frameSize = 2048;
    const int hop = 1024;
    if (n < frameSize) return chroma;

    final Float64List mono = Float64List(frameSize);
    for (int start = 0; start + frameSize <= n; start += hop) {
      double energy = 0.0;
      for (int i = 0; i < frameSize; i++) {
        final double m =
            0.5 * (vocal.leftChannel[start + i] + vocal.rightChannel[start + i]);
        mono[i] = m;
        energy += m * m;
      }
      final double rms = math.sqrt(energy / frameSize);
      if (rms < 0.015) continue;
      final double f0 = _pitchDetector.detectPitchYin(
        mono,
        sr,
        minFreqHz: 75.0,
        maxFreqHz: 700.0,
      );
      if (f0 >= 75.0 && f0 <= 700.0) {
        final double midi = 69.0 + 12.0 * (math.log(f0 / 440.0) / math.ln2);
        final int pc = ((midi.round() % 12) + 12) % 12;
        chroma[pc] += rms;
      }
    }

    final double sum = chroma.fold(0.0, (a, b) => a + b);
    if (sum > 1e-9) {
      for (int i = 0; i < 12; i++) {
        chroma[i] /= sum;
      }
    }
    return chroma;
  }

  double _pearsonCircular(List<double> chroma, List<double> profile, int root) {
    double meanC = 0.0;
    double meanP = 0.0;
    for (int i = 0; i < 12; i++) {
      meanC += chroma[i];
      meanP += profile[i];
    }
    meanC /= 12.0;
    meanP /= 12.0;

    double num = 0.0;
    double denC = 1e-9;
    double denP = 1e-9;
    for (int i = 0; i < 12; i++) {
      final int pIdx = (i - root + 12) % 12;
      final double dc = chroma[i] - meanC;
      final double dp = profile[pIdx] - meanP;
      num += dc * dp;
      denC += dc * dc;
      denP += dp * dp;
    }
    return num / math.sqrt(denC * denP);
  }

  void _fftRadix2(Float64List re, Float64List im) {
    final int n = re.length;
    int j = 0;
    for (int i = 0; i < n; i++) {
      if (i < j) {
        final double tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final double ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
      int m = n >> 1;
      while (m >= 1 && j >= m) {
        j -= m;
        m >>= 1;
      }
      j += m;
    }

    for (int len = 2; len <= n; len <<= 1) {
      final int halfLen = len >> 1;
      final double angle = -2.0 * math.pi / len;
      final double wLenRe = math.cos(angle);
      final double wLenIm = math.sin(angle);

      for (int i = 0; i < n; i += len) {
        double wRe = 1.0;
        double wIm = 0.0;
        for (int k = 0; k < halfLen; k++) {
          final int evenIdx = i + k;
          final int oddIdx = i + k + halfLen;
          final double uRe = re[evenIdx];
          final double uIm = im[evenIdx];
          final double vRe = re[oddIdx] * wRe - im[oddIdx] * wIm;
          final double vIm = re[oddIdx] * wIm + im[oddIdx] * wRe;
          re[evenIdx] = uRe + vRe;
          im[evenIdx] = uIm + vIm;
          re[oddIdx] = uRe - vRe;
          im[oddIdx] = uIm - vIm;
          final double nextWRe = wRe * wLenRe - wIm * wLenIm;
          wIm = wRe * wLenIm + wIm * wLenRe;
          wRe = nextWRe;
        }
      }
    }
  }
}
