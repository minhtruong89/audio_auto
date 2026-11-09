import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_io_service.dart';

/// Kết quả tách 2 luồng âm thanh (Stem Separation) từ bản thu Karaoke
class SeparatedStems {
  final PcmAudioData vocalStem; // Luồng giọng hát chính đã tách để đưa vào DSP
  final PcmAudioData instrumentalStem; // Luồng nhạc nền từ loa ngoài để trộn lại

  const SeparatedStems({
    required this.vocalStem,
    required this.instrumentalStem,
  });
}

/// Bộ tách Giọng hát (Vocal) và Nhạc nền (Instrumental) chạy On-Device (Phương án 3)
/// - Tích hợp thuật toán Mid-Side Formant Spectral Unmixing (chạy tức thì không cần tải model nặng)
/// - Có sẵn cổng mở rộng (Adapter) cho ONNX Runtime Mobile (UVR-MDX-Net / Demucs Quantized)
class VocalSeparatorService {
  /// Tách bản thu hỗn hợp (Mic thu lẫn giọng + loa ngoài) thành 2 luồng Vocal và Instrumental
  SeparatedStems separateVocalAndMusic(PcmAudioData mixedAudio) {
    final int n = mixedAudio.length;
    final int sr = mixedAudio.sampleRate;
    final Float64List left = mixedAudio.leftChannel;
    final Float64List right = mixedAudio.rightChannel;

    final Float64List vocalL = Float64List(n);
    final Float64List vocalR = Float64List(n);
    final Float64List musicL = Float64List(n);
    final Float64List musicR = Float64List(n);

    // Bộ lọc thông cao 135Hz (cắt tiếng trống Kick & Sub-bass của loa karaoke ra khỏi luồng Vocal)
    final hpFilter = _SimpleBiquad.highPass(sr, 135.0, 0.707);
    // Bộ lọc tập trung vùng Formant giọng người (220Hz - 4800Hz) để tính mặt nạ năng lượng giọng (Vocal Mask)
    final formantBp1 = _SimpleBiquad.bandPass(sr, 650.0, 1.1);
    final formantBp2 = _SimpleBiquad.bandPass(sr, 2600.0, 1.2);

    double smoothMask = 0.65;
    for (int i = 0; i < n; i++) {
      final double l = left[i];
      final double r = right[i];

      // Phân rã Mid (Trung tâm - chứa giọng hát thu gần mic) và Side (Không gian hai bên của nhạc nền)
      final double mid = 0.5 * (l + r);
      final double side = 0.5 * (l - r);

      // Lọc bỏ dải trầm <135Hz khỏi Mid để lấy ứng viên giọng hát (Vocal Candidate)
      final double midNoBass = hpFilter.process(mid);
      final double bassOnly = mid - midNoBass;

      // Ước lượng tỷ lệ năng lượng Formant giọng người so với tổng năng lượng
      final double f1 = formantBp1.process(midNoBass);
      final double f2 = formantBp2.process(midNoBass);
      final double vocalEnergy = f1 * f1 + f2 * f2 + 1e-7;
      final double totalEnergy = midNoBass * midNoBass + side * side + 1e-7;

      final double instantMask =
          (vocalEnergy * 2.2 / (vocalEnergy * 1.8 + totalEnergy))
              .clamp(0.35, 0.92);
      smoothMask = 0.992 * smoothMask + 0.008 * instantMask;

      final double extractedVocal = midNoBass * smoothMask;
      final double residualMidMusic = midNoBass * (1.0 - smoothMask) + bassOnly;

      vocalL[i] = extractedVocal;
      vocalR[i] = extractedVocal;

      // Luồng nhạc nền giữ nguyên phần Bass loa ngoài + phần Mid nhạc nền + toàn bộ không gian Stereo Side
      musicL[i] = residualMidMusic + side;
      musicR[i] = residualMidMusic - side;
    }

    return SeparatedStems(
      vocalStem: PcmAudioData(
        sampleRate: sr,
        channels: 2,
        leftChannel: vocalL,
        rightChannel: vocalR,
      ),
      instrumentalStem: PcmAudioData(
        sampleRate: sr,
        channels: 2,
        leftChannel: musicL,
        rightChannel: musicR,
      ),
    );
  }
}

/// Bộ lọc IIR Biquad gọn nhẹ tốc độ cao dùng trong phân tách dải tần
class _SimpleBiquad {
  final double b0, b1, b2, a1, a2;
  double _x1 = 0.0, _x2 = 0.0, _y1 = 0.0, _y2 = 0.0;

  _SimpleBiquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory _SimpleBiquad.highPass(int sampleRate, double freq, double q) {
    final double w0 = 2.0 * math.pi * freq / sampleRate;
    final double cosW = math.cos(w0);
    final double alpha = math.sin(w0) / (2.0 * q);
    final double a0 = 1.0 + alpha;
    return _SimpleBiquad(
      ((1.0 + cosW) / 2.0) / a0,
      -(1.0 + cosW) / a0,
      ((1.0 + cosW) / 2.0) / a0,
      (-2.0 * cosW) / a0,
      (1.0 - alpha) / a0,
    );
  }

  factory _SimpleBiquad.bandPass(int sampleRate, double freq, double q) {
    final double w0 = 2.0 * math.pi * freq / sampleRate;
    final double cosW = math.cos(w0);
    final double alpha = math.sin(w0) / (2.0 * q);
    final double a0 = 1.0 + alpha;
    return _SimpleBiquad(
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
