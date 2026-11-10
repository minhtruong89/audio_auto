import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_io_service.dart';
import 'onnx_uvr_separator_service.dart';
import 'voice_analyzer_service.dart';

/// Kết quả tách 2 luồng âm thanh (Stem Separation) từ bản thu Karaoke
class SeparatedStems {
  final PcmAudioData vocalStem; // Luồng giọng hát chính đã tách để đưa vào DSP
  final PcmAudioData instrumentalStem; // Luồng nhạc nền từ loa ngoài để trộn lại
  final bool usedAiOnnxModel; // Đánh dấu đã dùng mạng nơ-ron UVR-MDX-NET ONNX hay chưa

  const SeparatedStems({
    required this.vocalStem,
    required this.instrumentalStem,
    this.usedAiOnnxModel = false,
  });
}

/// Bộ tách Giọng hát (Vocal) và Nhạc nền (Instrumental) chạy On-Device:
/// - **Ưu tiên Cách B1 (Deep Learning AI ONNX)**: Chạy mô hình mạng nơ-ron mã nguồn mở
///   `UVR_MDXNET_9482.onnx` (Ultimate Vocal Remover MDX-Net) trực tiếp trên thiết bị qua C++ ONNX Runtime (`sherpa_onnx`).
///   Có bộ nhớ đệm (Cache) theo bản thu để khi người dùng đổi Preset / đổi Hồ sơ giọng thì không phải chờ tách lại.
/// - **Fallback an toàn (Hướng A - STFT Harmonic Comb)**: Dùng trong môi trường unit test không nạp model hoặc khi máy thiếu RAM.
class VocalSeparatorService {
  final VoiceAnalyzerService _pitchDetector = VoiceAnalyzerService();
  final OnnxUvrSeparatorService _onnxUvr = OnnxUvrSeparatorService();

  // Bộ nhớ đệm kết quả tách gần nhất để đổi Giọng lưu / Preset tức thì trong 50ms
  int? _cachedAudioLength;
  double? _cachedAudioSignature;
  SeparatedStems? _cachedStems;

  bool get isAiOnnxReady => _onnxUvr.isInitialized;

  void dispose() {
    _onnxUvr.dispose();
  }

  /// Khởi tạo mô hình AI `UVR_MDXNET_9482.onnx` từ đường dẫn file nội bộ trên thiết bị
  bool initAiOnnxModel(String modelFilePath, {int numThreads = 4}) {
    final ok = _onnxUvr.initModel(modelFilePath, numThreads: numThreads);
    if (ok) {
      // Xóa cache cũ nếu trước đó từng chạy bằng DSP fallback
      if (_cachedStems != null && !_cachedStems!.usedAiOnnxModel) {
        _cachedStems = null;
      }
    }
    return ok;
  }

  double _computeQuickSignature(PcmAudioData audio) {
    final int n = audio.length;
    if (n == 0) return 0.0;
    final int step = math.max(1, n ~/ 128);
    double acc = 0.0;
    for (int i = 0; i < n; i += step) {
      acc += audio.leftChannel[i] * (i + 1) - audio.rightChannel[i] * 0.5;
    }
    return acc;
  }

  /// Tách bản thu hỗn hợp (Mic thu lẫn giọng + loa ngoài, kể cả Mono lẫn Stereo) thành 2 luồng Vocal và Instrumental
  SeparatedStems separateVocalAndMusic(PcmAudioData mixedAudio) {
    final int n = mixedAudio.length;
    final int sr = mixedAudio.sampleRate;
    final Float64List left = mixedAudio.leftChannel;
    final Float64List right = mixedAudio.rightChannel;

    if (n < 2048) {
      return SeparatedStems(
        vocalStem: mixedAudio,
        instrumentalStem: PcmAudioData(
          sampleRate: sr,
          channels: 2,
          leftChannel: Float64List(n),
          rightChannel: Float64List(n),
        ),
      );
    }

    // 1. Kiểm tra bộ nhớ đệm (nếu cùng 1 file âm thanh đầu vào thì trả về ngay lập tức)
    final double sig = _computeQuickSignature(mixedAudio);
    if (_cachedStems != null &&
        _cachedAudioLength == n &&
        _cachedAudioSignature == sig &&
        (_cachedStems!.usedAiOnnxModel || !_onnxUvr.isInitialized)) {
      return _cachedStems!;
    }

    // 2. Nếu mô hình AI UVR-MDX-NET ONNX đã sẵn sàng -> Chạy tách bằng mạng nơ-ron học sâu (Cách B1)
    if (_onnxUvr.isInitialized) {
      try {
        final aiStems = _onnxUvr.separate(mixedAudio);
        final result = SeparatedStems(
          vocalStem: aiStems.vocalStem,
          instrumentalStem: aiStems.instrumentalStem,
          usedAiOnnxModel: true,
        );
        _cachedAudioLength = n;
        _cachedAudioSignature = sig;
        _cachedStems = result;
        return result;
      } catch (_) {
        // Nếu có lỗi bộ nhớ trên thiết bị yếu thì tự động lùi về STFT bên dưới
      }
    }

    const int fftSize = 1024;
    const int hopSize = 256; // 75% overlap-add chuẩn COLA
    const int numBins = fftSize ~/ 2 + 1;
    final double binFreqStep = sr / fftSize;

    // Tạo cửa sổ Hann
    final Float64List window = Float64List(fftSize);
    for (int i = 0; i < fftSize; i++) {
      window[i] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / fftSize));
    }

    // Trích xuất kênh Mid (Trung tâm) và Side (Không gian hai bên)
    final Float64List midInput = Float64List(n);
    final Float64List sideInput = Float64List(n);
    for (int i = 0; i < n; i++) {
      midInput[i] = 0.5 * (left[i] + right[i]);
      sideInput[i] = 0.5 * (left[i] - right[i]);
    }

    final Float64List vocalMidOut = Float64List(n);
    final Float64List winNorm = Float64List(n);

    // Bộ nhớ đệm ước lượng phổ nền nhạc cụ (Stationary Instrumental Spectral Floor)
    final Float64List musicFloorMag = Float64List(numBins);
    final Float64List prevVocalMask = Float64List(numBins);
    for (int b = 0; b < numBins; b++) {
      prevVocalMask[b] = 0.2;
    }

    final Float64List re = Float64List(fftSize);
    final Float64List im = Float64List(fftSize);
    final Float64List frameMono = Float64List(fftSize);
    final Float64List mag = Float64List(numBins);
    final Float64List sideRe = Float64List(fftSize);
    final Float64List sideIm = Float64List(fftSize);

    bool isFirstFrame = true;
    double trackedF0 = 0.0;

    for (int start = 0; start + fftSize <= n; start += hopSize) {
      double frameEnergy = 0.0;
      for (int i = 0; i < fftSize; i++) {
        final double m = midInput[start + i];
        frameMono[i] = m;
        frameEnergy += m * m;
        re[i] = m * window[i];
        im[i] = 0.0;
        sideRe[i] = sideInput[start + i] * window[i];
        sideIm[i] = 0.0;
      }

      // 1. Dò tần số cơ bản (F0) của giọng hát trong khung hiện tại bằng YIN
      double f0 = 0.0;
      if (frameEnergy / fftSize > 1.2e-4) {
        f0 = _pitchDetector.detectPitchYin(frameMono, sr);
        if (f0 >= 85.0 && f0 <= 900.0) {
          trackedF0 = trackedF0 == 0.0 ? f0 : (0.75 * trackedF0 + 0.25 * f0);
        } else {
          f0 = 0.0;
        }
      } else {
        trackedF0 *= 0.85;
        if (trackedF0 < 75.0) trackedF0 = 0.0;
      }

      // 2. Chạy FFT 1024 điểm cho kênh Mid và kênh Side
      _fftRadix2(re, im, false);
      _fftRadix2(sideRe, sideIm, false);

      for (int b = 0; b < numBins; b++) {
        final double mMag = math.sqrt(re[b] * re[b] + im[b] * im[b]) + 1e-9;
        final double sMag =
            math.sqrt(sideRe[b] * sideRe[b] + sideIm[b] * sideIm[b]);
        mag[b] = mMag;

        if (isFirstFrame) {
          musicFloorMag[b] = mMag * 0.65;
        } else {
          // Khi không có giọng hát (f0 == 0), cập nhật nhanh nền nhạc cụ;
          // Khi có giọng hát, chỉ cập nhật cực chậm theo phân vị thấp để không nuốt giọng hát
          if (f0 == 0.0) {
            musicFloorMag[b] = 0.88 * musicFloorMag[b] + 0.12 * mMag;
          } else if (mMag < musicFloorMag[b]) {
            musicFloorMag[b] = 0.90 * musicFloorMag[b] + 0.10 * mMag;
          } else {
            musicFloorMag[b] = 0.996 * musicFloorMag[b] + 0.004 * mMag;
          }
        }

        final double freq = b * binFreqStep;

        // 3. Tính mặt nạ tần số Giọng Hát (Vocal Spectral Mask) cho từng bin b:
        double binMask = 0.0;

        if (freq < 115.0 || freq > 11500.0) {
          // Triệt tiêu hoàn toàn tiếng trống Bass/Sub (<115Hz) và nhiễu siêu cao (>11.5kHz) khỏi luồng Vocal
          binMask = 0.0;
        } else {
          // a) Mặt nạ Khử nền nhạc cụ (Spectral Subtraction / Wiener Gain)
          final double musicEst = musicFloorMag[b] + sMag * 0.85;
          final double postSnr = math.max(0.0, mMag - musicEst * 0.92) / mMag;
          final double wienerMask = (postSnr * postSnr).clamp(0.0, 1.0);

          // b) Mặt nạ Răng lược Hài âm Giọng hát (Harmonic Comb Masking tại k * F0)
          double harmonicMask = 0.12; // Khi không có F0 thì dìm mạnh nhạc nền xuống
          final double activeF0 = f0 > 0.0 ? f0 : trackedF0;

          if (activeF0 >= 85.0) {
            if (freq <= 4600.0) {
              // Khoảng cách từ tần số bin hiện tại tới bội số hài âm gần nhất (k * F0)
              final double harmonicOrder = (freq / activeF0).roundToDouble();
              if (harmonicOrder >= 1.0 && harmonicOrder <= 28.0) {
                final double nearestHarmonicHz = harmonicOrder * activeF0;
                final double distHz = (freq - nearestHarmonicHz).abs();
                final double bandwidthHz = math.max(26.0, activeF0 * 0.24);
                final double combWeight = math.exp(
                  -(distHz * distHz) / (2.0 * bandwidthHz * bandwidthHz),
                );
                harmonicMask = (0.15 + 0.85 * combWeight).clamp(0.15, 1.0);
              }
            } else {
              // Vùng Sibilance / Air (4.6kHz - 10kHz): cho phép phụ âm gió/xì của giọng đi qua vừa phải
              harmonicMask = f0 > 0.0 ? 0.55 : 0.20;
            }
          }

          // c) Trọng số vùng Formant giọng người (ưu tiên 220Hz - 3800Hz)
          double formantWeight = 1.0;
          if (freq < 180.0) {
            formantWeight = ((freq - 115.0) / 65.0).clamp(0.1, 1.0);
          }

          binMask =
              (wienerMask * 0.55 + harmonicMask * 0.45) * formantWeight;
        }

        // Làm mượt mặt nạ theo thời gian (Temporal Smoothing) để không bị tiếng "lạo xạo / musical noise"
        final double smoothed =
            (0.60 * prevVocalMask[b] + 0.40 * binMask).clamp(0.0, 1.0);
        prevVocalMask[b] = smoothed;

        re[b] *= smoothed;
        im[b] *= smoothed;
        if (b > 0 && b < numBins - 1) {
          re[fftSize - b] = re[b];
          im[fftSize - b] = -im[b];
        }
      }
      isFirstFrame = false;

      // 4. Biến đổi IFFT ngược về miền thời gian & Cộng chồng cửa sổ (Overlap-Add)
      _fftRadix2(re, im, true);
      for (int i = 0; i < fftSize; i++) {
        final double w = window[i];
        vocalMidOut[start + i] += re[i] * w;
        winNorm[start + i] += w * w;
      }
    }

    // 5. Chuẩn hóa biên độ Overlap-Add và tách triệt để Nhạc nền = Gốc - Vocal
    final Float64List vocalL = Float64List(n);
    final Float64List vocalR = Float64List(n);
    final Float64List musicL = Float64List(n);
    final Float64List musicR = Float64List(n);

    for (int i = 0; i < n; i++) {
      final double norm = winNorm[i] > 1e-5 ? vocalMidOut[i] / winNorm[i] : 0.0;
      final double vSample = norm.clamp(-0.98, 0.98);
      vocalL[i] = vSample;
      vocalR[i] = vSample;

      // Nhạc nền giữ trọn vẹn phần năng lượng đã tách khỏi Vocal + toàn bộ kênh Stereo Side
      musicL[i] = (left[i] - vSample).clamp(-0.98, 0.98);
      musicR[i] = (right[i] - vSample).clamp(-0.98, 0.98);
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

  /// Thuật toán FFT / IFFT Cooley-Tukey Radix-2 In-place tốc độ cao
  void _fftRadix2(Float64List re, Float64List im, bool inverse) {
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
      final double angle =
          (inverse ? 2.0 : -2.0) * math.pi / len;
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

    if (inverse) {
      for (int i = 0; i < n; i++) {
        re[i] /= n;
        im[i] /= n;
      }
    }
  }
}
