import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'audio_io_service.dart';
import 'vocal_separator_service.dart';

// ============================================================================
// C-API FFI Structs cho SherpaOnnxOfflineSourceSeparation
// ============================================================================

final class SherpaOnnxOfflineSourceSeparationSpleeterModelConfig
    extends Struct {
  external Pointer<Utf8> vocals;
  external Pointer<Utf8> accompaniment;
}

final class SherpaOnnxOfflineSourceSeparationUvrModelConfig extends Struct {
  external Pointer<Utf8> model;
}

final class SherpaOnnxOfflineSourceSeparationModelConfig extends Struct {
  external SherpaOnnxOfflineSourceSeparationSpleeterModelConfig spleeter;
  external SherpaOnnxOfflineSourceSeparationUvrModelConfig uvr;

  @Int32()
  external int numThreads;

  @Int32()
  external int debug;

  external Pointer<Utf8> provider;
}

final class SherpaOnnxOfflineSourceSeparationConfig extends Struct {
  external SherpaOnnxOfflineSourceSeparationModelConfig model;
}

final class SherpaOnnxOfflineSourceSeparation extends Opaque {}

final class SherpaOnnxSourceSeparationStem extends Struct {
  external Pointer<Pointer<Float>> samples;

  @Int32()
  external int numChannels;

  @Int32()
  external int n;
}

final class SherpaOnnxSourceSeparationOutput extends Struct {
  external Pointer<SherpaOnnxSourceSeparationStem> stems;

  @Int32()
  external int numStems;

  @Int32()
  external int sampleRate;
}

// Typedefs C-API
typedef _CreateOfflineSourceSeparationNative =
    Pointer<SherpaOnnxOfflineSourceSeparation> Function(
      Pointer<SherpaOnnxOfflineSourceSeparationConfig> config,
    );
typedef _CreateOfflineSourceSeparationDart =
    Pointer<SherpaOnnxOfflineSourceSeparation> Function(
      Pointer<SherpaOnnxOfflineSourceSeparationConfig> config,
    );

typedef _DestroyOfflineSourceSeparationNative =
    Void Function(Pointer<SherpaOnnxOfflineSourceSeparation> ss);
typedef _DestroyOfflineSourceSeparationDart =
    void Function(Pointer<SherpaOnnxOfflineSourceSeparation> ss);

typedef _ProcessOfflineSourceSeparationNative =
    Pointer<SherpaOnnxSourceSeparationOutput> Function(
      Pointer<SherpaOnnxOfflineSourceSeparation> ss,
      Pointer<Pointer<Float>> samples,
      Int32 numChannels,
      Int32 numSamples,
      Int32 sampleRate,
    );
typedef _ProcessOfflineSourceSeparationDart =
    Pointer<SherpaOnnxSourceSeparationOutput> Function(
      Pointer<SherpaOnnxOfflineSourceSeparation> ss,
      Pointer<Pointer<Float>> samples,
      int numChannels,
      int numSamples,
      int sampleRate,
    );

typedef _DestroySourceSeparationOutputNative =
    Void Function(Pointer<SherpaOnnxSourceSeparationOutput> p);
typedef _DestroySourceSeparationOutputDart =
    void Function(Pointer<SherpaOnnxSourceSeparationOutput> p);

/// Dịch vụ Tách Giọng & Nhạc Nền bằng Mạng Nơ-ron Học Sâu Mã Nguồn Mở
/// (UVR-MDX-NET ONNX chạy trực tiếp On-Device thông qua C++ Sherpa-ONNX / ONNX Runtime).
class OnnxUvrSeparatorService {
  DynamicLibrary? _dylib;
  Pointer<SherpaOnnxOfflineSourceSeparation>? _engine;
  String? _loadedModelPath;

  late final _CreateOfflineSourceSeparationDart _createEngine;
  late final _DestroyOfflineSourceSeparationDart _destroyEngine;
  late final _ProcessOfflineSourceSeparationDart _processAudio;
  late final _DestroySourceSeparationOutputDart _destroyOutput;

  bool get isInitialized =>
      _engine != null && _engine != nullptr && _dylib != null;

  /// Nạp thư viện động C++ `libsherpa-onnx-c-api.so` (Android) / `sherpa-onnx-c-api.dll` (Windows)
  DynamicLibrary _openDynamicLibrary() {
    if (_dylib != null) return _dylib!;
    if (Platform.isAndroid || Platform.isLinux) {
      _dylib = DynamicLibrary.open('libsherpa-onnx-c-api.so');
      return _dylib!;
    }
    if (Platform.isIOS || Platform.isMacOS) {
      _dylib = DynamicLibrary.process();
      return _dylib!;
    }
    if (Platform.isWindows) {
      try {
        _dylib = DynamicLibrary.open('sherpa-onnx-c-api.dll');
        return _dylib!;
      } catch (_) {
        // Hỗ trợ chạy flutter test trực tiếp trên Windows từ Pub Cache
        final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
        final cacheDir =
            '$localAppData\\Pub\\Cache\\hosted\\pub.dev\\sherpa_onnx_windows-2.0.1\\windows\\x64';
        if (Directory(cacheDir).existsSync()) {
          DynamicLibrary.open('$cacheDir\\onnxruntime.dll');
          _dylib = DynamicLibrary.open('$cacheDir\\sherpa-onnx-c-api.dll');
          return _dylib!;
        }
        rethrow;
      }
    }
    throw UnsupportedError('Hệ điều hành chưa hỗ trợ ONNX FFI');
  }

  /// Khởi tạo phiên chạy mô hình UVR-MDX-NET `.onnx` từ đường dẫn file trên thiết bị
  bool initModel(String modelFilePath, {int numThreads = 4}) {
    if (isInitialized && _loadedModelPath == modelFilePath) {
      return true;
    }
    dispose();

    if (!File(modelFilePath).existsSync()) {
      return false;
    }

    final lib = _openDynamicLibrary();
    _createEngine = lib
        .lookup<NativeFunction<_CreateOfflineSourceSeparationNative>>(
          'SherpaOnnxCreateOfflineSourceSeparation',
        )
        .asFunction<_CreateOfflineSourceSeparationDart>();
    _destroyEngine = lib
        .lookup<NativeFunction<_DestroyOfflineSourceSeparationNative>>(
          'SherpaOnnxDestroyOfflineSourceSeparation',
        )
        .asFunction<_DestroyOfflineSourceSeparationDart>();
    _processAudio = lib
        .lookup<NativeFunction<_ProcessOfflineSourceSeparationNative>>(
          'SherpaOnnxOfflineSourceSeparationProcess',
        )
        .asFunction<_ProcessOfflineSourceSeparationDart>();
    _destroyOutput = lib
        .lookup<NativeFunction<_DestroySourceSeparationOutputNative>>(
          'SherpaOnnxDestroySourceSeparationOutput',
        )
        .asFunction<_DestroySourceSeparationOutputDart>();

    final configPtr = calloc<SherpaOnnxOfflineSourceSeparationConfig>();
    final emptyStr = ''.toNativeUtf8();
    final uvrModelStr = modelFilePath.toNativeUtf8();
    final providerStr = 'cpu'.toNativeUtf8();

    try {
      configPtr.ref.model.spleeter.vocals = emptyStr;
      configPtr.ref.model.spleeter.accompaniment = emptyStr;
      configPtr.ref.model.uvr.model = uvrModelStr;
      configPtr.ref.model.numThreads = numThreads;
      configPtr.ref.model.debug = 0;
      configPtr.ref.model.provider = providerStr;

      final handle = _createEngine(configPtr);
      if (handle == nullptr) {
        return false;
      }
      _engine = handle;
      _loadedModelPath = modelFilePath;
      return true;
    } finally {
      calloc.free(emptyStr);
      calloc.free(uvrModelStr);
      calloc.free(providerStr);
      calloc.free(configPtr);
    }
  }

  /// Chạy mạng nơ-ron UVR-MDX-NET để tách riêng Vocal (Giọng hát) và Instrumental (Nhạc nền).
  /// Lưu ý: Trong mô hình `UVR_MDXNET_9482.onnx` (và họ `UVR_MDXNET_*` / `UVR-MDX-NET-Inst_*`),
  /// mạng nơ-ron dự đoán trực tiếp kênh **Instrumental (Nhạc nền)** ở `stems[0]`,
  /// còn **Vocal (Giọng hát)** sạch nằm ở `stems[1]` (hoặc ngược lại đối với bản Voc_FT).
  SeparatedStems separate(PcmAudioData input) {
    if (!isInitialized) {
      throw StateError('Chưa khởi tạo mô hình ONNX UVR-MDX-NET');
    }

    final int n = input.length;
    final int sr = input.sampleRate;

    final Pointer<Float> ch0Ptr = calloc<Float>(n);
    final Pointer<Float> ch1Ptr = calloc<Float>(n);
    final Pointer<Pointer<Float>> channelsPtr = calloc<Pointer<Float>>(2);

    try {
      final Float32List ch0View = ch0Ptr.asTypedList(n);
      final Float32List ch1View = ch1Ptr.asTypedList(n);
      for (int i = 0; i < n; i++) {
        ch0View[i] = input.leftChannel[i];
        ch1View[i] = input.rightChannel[i];
      }
      channelsPtr[0] = ch0Ptr;
      channelsPtr[1] = ch1Ptr;

      final outPtr = _processAudio(_engine!, channelsPtr, 2, n, sr);
      if (outPtr == nullptr) {
        throw StateError('ONNX Runtime trả về null khi tách âm thanh');
      }

      try {
        final outRef = outPtr.ref;
        final int outSr = outRef.sampleRate;
        final stem0 = outRef.stems[0];
        final stem1 = outRef.stems[1];

        final PcmAudioData pcmStem0 = _copyStemToPcm(stem0, outSr);
        final PcmAudioData pcmStem1 = _copyStemToPcm(stem1, outSr);

        // Với model UVR_MDXNET_9482 (Vocals primary output):
        // stem0 là Vocal (Giọng hát chính), stem1 là Instrumental (Nhạc nền).
        // Nếu là dòng model đặt tên có "_inst" thì stem0 là Instrumental, stem1 là Vocal.
        final bool isInstPrimary =
            (_loadedModelPath ?? '').toLowerCase().contains('inst');

        final rawVocal = isInstPrimary ? pcmStem1 : pcmStem0;
        final rawInst = isInstPrimary ? pcmStem0 : pcmStem1;

        return _postProcessCleanStems(
          input: input,
          rawVocal: rawVocal,
          rawInst: rawInst,
        );
      } finally {
        _destroyOutput(outPtr);
      }
    } finally {
      calloc.free(channelsPtr);
      calloc.free(ch0Ptr);
      calloc.free(ch1Ptr);
    }
  }

  /// Hậu xử lý STFT Wiener Soft-Masking (Không làm lệch pha, không bị tiếng vang/rè):
  /// 1. Trên kênh Nhạc nền (Instrumental): Trong bản thu điện thoại/loa ngoài, giọng hát thu gần mic thường lớn hơn
  ///    chuẩn phòng thu nên phép trừ mặc định của model vẫn để sót ~12-20% bóng giọng (vocal ghosting).
  ///    Ta chạy STFT 1024-điểm (75% Overlap-Add) tính mặt nạ Wiener mềm theo từng bin tần số: tại những điểm
  ///    tần số-thời gian mà năng lượng Vocal chiếm ưu thế trong dải 120Hz - 5.2kHz, ta dìm thêm phần rò rỉ trên kênh Nhạc,
  ///    nhưng vẫn giữ nguyên 100% tiếng Bass và nhạc cụ.
  /// 2. Trên kênh Giọng hát (Vocal): Lọc bỏ tạp âm nhạc nền lọt nhẹ bằng Wiener mask nhẹ, cắt nhiễu siêu cao > 9.5kHz
  ///    (giữ nguyên độ trong tự nhiên của giọng mà không bị xì gắt) và đóng mượt Noise Gate khi nghỉ lấy hơi.
  SeparatedStems _postProcessCleanStems({
    required PcmAudioData input,
    required PcmAudioData rawVocal,
    required PcmAudioData rawInst,
  }) {
    final int sr = rawVocal.sampleRate;
    final int n = math.min(rawVocal.length, rawInst.length);

    final Float64List vL = Float64List.fromList(rawVocal.leftChannel);
    final Float64List vR = Float64List.fromList(rawVocal.rightChannel);
    final Float64List mL = Float64List.fromList(rawInst.leftChannel);
    final Float64List mR = Float64List.fromList(rawInst.rightChannel);

    // 1. Áp dụng STFT Wiener Soft-Masking cho kênh Left và kênh Right để rút sạch bóng Vocal khỏi Music
    if (n >= 2048) {
      _applyStftWienerCleanup(vL, mL, sr);
      _applyStftWienerCleanup(vR, mR, sr);
    }

    // 2. Làm sạch tiếng xì siêu cao tần (> 9.5kHz) & ù (< 85Hz) và đóng cổng mượt khi ngừng hát
    final vocalLpL = _SimpleBiquad.lowPass(sr, 9500.0, 0.707);
    final vocalLpR = _SimpleBiquad.lowPass(sr, 9500.0, 0.707);
    final vocalHpL = _SimpleBiquad.highPass(sr, 85.0, 0.707);
    final vocalHpR = _SimpleBiquad.highPass(sr, 85.0, 0.707);

    double vocalEnv = 0.0;
    double gateGain = 0.0;

    for (int i = 0; i < n; i++) {
      double vl = vL[i];
      double vr = vR[i];

      final double vAbs = 0.5 * (vl.abs() + vr.abs());
      if (vAbs > vocalEnv) {
        vocalEnv = 0.985 * vocalEnv + 0.015 * vAbs;
      } else {
        vocalEnv = 0.9992 * vocalEnv + 0.0008 * vAbs;
      }

      final double targetGate = vocalEnv < 0.008
          ? 0.0
          : ((vocalEnv - 0.008) / 0.020).clamp(0.0, 1.0);
      gateGain = 0.995 * gateGain + 0.005 * targetGate;

      vl = vocalLpL.process(vocalHpL.process(vl)) * gateGain;
      vr = vocalLpR.process(vocalHpR.process(vr)) * gateGain;
      vL[i] = vl.clamp(-0.98, 0.98);
      vR[i] = vr.clamp(-0.98, 0.98);

      mL[i] = mL[i].clamp(-0.98, 0.98);
      mR[i] = mR[i].clamp(-0.98, 0.98);
    }

    return SeparatedStems(
      vocalStem: PcmAudioData(
        sampleRate: sr,
        channels: 2,
        leftChannel: vL,
        rightChannel: vR,
      ),
      instrumentalStem: PcmAudioData(
        sampleRate: sr,
        channels: 2,
        leftChannel: mL,
        rightChannel: mR,
      ),
      usedAiOnnxModel: true,
    );
  }

  /// Làm sạch song song 2 luồng Vocal và Music bằng STFT Wiener Soft-Masking (1024-pt FFT, hop 256)
  void _applyStftWienerCleanup(Float64List vBuf, Float64List mBuf, int sr) {
    final int n = vBuf.length;
    const int fftSize = 1024;
    const int hopSize = 256;
    const int numBins = fftSize ~/ 2 + 1;
    final double binFreq = sr / fftSize;

    final Float64List window = Float64List(fftSize);
    for (int i = 0; i < fftSize; i++) {
      window[i] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / fftSize));
    }

    final Float64List vOut = Float64List(n);
    final Float64List mOut = Float64List(n);
    final Float64List winNorm = Float64List(n);

    final Float64List vRe = Float64List(fftSize);
    final Float64List vIm = Float64List(fftSize);
    final Float64List mRe = Float64List(fftSize);
    final Float64List mIm = Float64List(fftSize);
    final Float64List prevMusicMask = Float64List(numBins)..fillRange(0, numBins, 1.0);
    final Float64List prevVocalMask = Float64List(numBins)..fillRange(0, numBins, 1.0);

    for (int start = 0; start + fftSize <= n; start += hopSize) {
      for (int i = 0; i < fftSize; i++) {
        final double w = window[i];
        vRe[i] = vBuf[start + i] * w;
        vIm[i] = 0.0;
        mRe[i] = mBuf[start + i] * w;
        mIm[i] = 0.0;
      }

      _fftRadix2(vRe, vIm, false);
      _fftRadix2(mRe, mIm, false);

      for (int b = 0; b < numBins; b++) {
        final double freq = b * binFreq;
        final double vPow = vRe[b] * vRe[b] + vIm[b] * vIm[b];
        final double mPow = mRe[b] * mRe[b] + mIm[b] * mIm[b];

        // 1. Mặt nạ dìm phần giọng hát rò rỉ trong kênh Nhạc nền (tập trung dải giọng 120Hz - 5200Hz)
        double targetMusicMask = 1.0;
        if (freq >= 120.0 && freq <= 5500.0 && vPow > 1e-7) {
          final double suppressionFactor =
              (freq >= 240.0 && freq <= 3800.0) ? 3.2 : 1.8;
          targetMusicMask =
              (mPow / (mPow + suppressionFactor * vPow + 1e-8)).clamp(0.06, 1.0);
        }

        // 2. Mặt nạ lọc nhẹ tạp âm nhạc nền rò rỉ vào kênh Giọng hát (không cắt gắt để giữ giọng trong tự nhiên)
        double targetVocalMask = 1.0;
        if (freq < 90.0 || freq > 10500.0) {
          targetVocalMask = 0.08;
        } else if (mPow > 1e-7) {
          targetVocalMask =
              (vPow / (vPow + 0.28 * mPow + 1e-8)).clamp(0.12, 1.0);
        }

        // Làm mượt mặt nạ theo thời gian để không có tiếng lạo xạo (Zero musical noise)
        final double smoothM =
            0.45 * prevMusicMask[b] + 0.55 * targetMusicMask;
        final double smoothV =
            0.45 * prevVocalMask[b] + 0.55 * targetVocalMask;
        prevMusicMask[b] = smoothM;
        prevVocalMask[b] = smoothV;

        vRe[b] *= smoothV;
        vIm[b] *= smoothV;
        mRe[b] *= smoothM;
        mIm[b] *= smoothM;

        if (b > 0 && b < numBins - 1) {
          vRe[fftSize - b] = vRe[b];
          vIm[fftSize - b] = -vIm[b];
          mRe[fftSize - b] = mRe[b];
          mIm[fftSize - b] = -mIm[b];
        }
      }

      _fftRadix2(vRe, vIm, true);
      _fftRadix2(mRe, mIm, true);

      for (int i = 0; i < fftSize; i++) {
        final double w = window[i];
        vOut[start + i] += vRe[i] * w;
        mOut[start + i] += mRe[i] * w;
        winNorm[start + i] += w * w;
      }
    }

    for (int i = 0; i < n; i++) {
      final double norm = winNorm[i];
      if (norm > 1e-5) {
        vBuf[i] = vOut[i] / norm;
        mBuf[i] = mOut[i] / norm;
      }
    }
  }

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
      final double angle = (inverse ? 2.0 : -2.0) * math.pi / len;
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

  PcmAudioData _copyStemToPcm(SherpaOnnxSourceSeparationStem stem, int sr) {
    final int count = stem.n;
    final int ch = stem.numChannels;
    final Float64List left = Float64List(count);
    final Float64List right = Float64List(count);

    if (count > 0 && ch > 0 && stem.samples != nullptr) {
      final Float32List s0 = stem.samples[0].asTypedList(count);
      final Float32List s1 =
          ch > 1 ? stem.samples[1].asTypedList(count) : s0;
      for (int i = 0; i < count; i++) {
        left[i] = s0[i].clamp(-0.99, 0.99);
        right[i] = s1[i].clamp(-0.99, 0.99);
      }
    }

    return PcmAudioData(
      sampleRate: sr,
      channels: 2,
      leftChannel: left,
      rightChannel: right,
    );
  }

  void dispose() {
    if (_engine != null && _engine != nullptr) {
      _destroyEngine(_engine!);
      _engine = null;
    }
  }
}

class _SimpleBiquad {
  final double b0, b1, b2, a1, a2;
  double _x1 = 0.0, _x2 = 0.0, _y1 = 0.0, _y2 = 0.0;

  _SimpleBiquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory _SimpleBiquad.lowPass(int sr, double freq, double q) {
    final double w0 = 2.0 * math.pi * freq / sr;
    final double cosW = math.cos(w0);
    final double alpha = math.sin(w0) / (2.0 * q);
    final double a0 = 1.0 + alpha;
    final double b1 = 1.0 - cosW;
    final double b0 = b1 / 2.0;
    return _SimpleBiquad(
      b0 / a0,
      b1 / a0,
      b0 / a0,
      (-2.0 * cosW) / a0,
      (1.0 - alpha) / a0,
    );
  }

  factory _SimpleBiquad.highPass(int sr, double freq, double q) {
    final double w0 = 2.0 * math.pi * freq / sr;
    final double cosW = math.cos(w0);
    final double alpha = math.sin(w0) / (2.0 * q);
    final double a0 = 1.0 + alpha;
    final double b1 = -(1.0 + cosW);
    final double b0 = (1.0 + cosW) / 2.0;
    return _SimpleBiquad(
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
