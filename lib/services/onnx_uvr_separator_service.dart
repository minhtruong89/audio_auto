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

  /// Hậu xử lý khử nhiễu xì/rè trên kênh Vocal và triệt tiêu lượng Vocal rò rỉ nhỏ trên kênh Nhạc nền:
  /// 1. Trên kênh Nhạc nền (Instrumental): Trong bản thu điện thoại/loa ngoài, âm lượng giọng hát thường lớn hơn
  ///    so với bản thu phòng thu nên `input - vocals` vẫn còn sót ~12-18% biên độ giọng hát ở dải trung (250Hz-3800Hz).
  ///    Ta tính tương quan năng lượng tức thời giữa `Vocal` và `Instrumental` để triệt tiêu tiếp phần giọng còn vương lại
  ///    (Adaptive Residual Vocal Cancellation + Mid-Band Vocal Ducking).
  /// 2. Trên kênh Giọng hát (Vocal): Cắt sạch nhiễu tần số cao > 7.8kHz (nguyên nhân gây tiếng "xì xì" do cắt cụt bin `dim_f` của MDX-Net)
  ///    và áp bộ cổng mở mượt (Smooth Vocal Expander Gate) để tắt hẳn tiếng xì nền khi ca sĩ nghỉ lấy hơi.
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

    // 1. Tính hệ số tương quan chiếu (Least-Squares Residual Projection alpha) trên vùng giọng hát (300Hz-3400Hz)
    // để xem trong kênh Music còn dính bao nhiêu % biên độ của kênh Vocal
    double dotVM = 0.0;
    double dotVV = 1e-9;
    for (int i = 0; i < n; i += 2) {
      final double vMid = 0.5 * (vL[i] + vR[i]);
      final double mMid = 0.5 * (mL[i] + mR[i]);
      if (vMid.abs() > 0.025) {
        dotVM += vMid * mMid;
        dotVV += vMid * vMid;
      }
    }
    // Hệ số rò rỉ giọng còn sót trong nhạc nền (thường từ 0.08 -> 0.28 trên file quay bằng điện thoại)
    final double residualAlpha = (dotVM / dotVV).clamp(0.0, 0.35) + 0.14;

    // Bộ lọc dải tần giọng hát (Vocal Presence Band 280Hz - 3600Hz) để chỉ rút thêm giọng khỏi nhạc nền ở dải trung
    // mà giữ nguyên 100% tiếng Bass và tiếng Treble của nhạc cụ!
    final vocalBandFilterL = _SimpleBiquad.bandPass(sr, 1150.0, 0.65);
    final vocalBandFilterR = _SimpleBiquad.bandPass(sr, 1150.0, 0.65);

    // Bộ lọc khử tiếng xì gắt (Anti-Hiss Low-Pass 7600Hz + High-Pass 95Hz) cho kênh Vocal
    final vocalLpL = _SimpleBiquad.lowPass(sr, 7600.0, 0.707);
    final vocalLpR = _SimpleBiquad.lowPass(sr, 7600.0, 0.707);
    final vocalHpL = _SimpleBiquad.highPass(sr, 95.0, 0.707);
    final vocalHpR = _SimpleBiquad.highPass(sr, 95.0, 0.707);

    // Bộ lọc làm ấm nhẹ dải cao của kênh Music khi bị trừ giọng
    final musicPresenceDipL = _SimpleBiquad.peaking(sr, 1650.0, 0.9, -3.5);
    final musicPresenceDipR = _SimpleBiquad.peaking(sr, 1650.0, 0.9, -3.5);

    double vocalEnv = 0.0;
    double gateGain = 0.0;

    for (int i = 0; i < n; i++) {
      double vl = vL[i];
      double vr = vR[i];

      // Đo bao hình năng lượng giọng hát (Envelope Follower)
      final double vAbs = 0.5 * (vl.abs() + vr.abs());
      if (vAbs > vocalEnv) {
        vocalEnv = 0.985 * vocalEnv + 0.015 * vAbs;
      } else {
        vocalEnv = 0.9992 * vocalEnv + 0.0008 * vAbs;
      }

      // A. Làm sạch kênh Vocal:
      // - Khi ca sĩ không hát (vocalEnv < 0.012), đóng mượt cổng âm thanh xuống 0 để triệt tiêu hoàn toàn tiếng xì nền
      final double targetGate = vocalEnv < 0.010
          ? 0.0
          : ((vocalEnv - 0.010) / 0.022).clamp(0.0, 1.0);
      gateGain = 0.995 * gateGain + 0.005 * targetGate;

      // - Lọc sạch nhiễu cao tần (>7.6kHz) và ù trầm (<95Hz) gây rè/xì
      vl = vocalLpL.process(vocalHpL.process(vl)) * gateGain;
      vr = vocalLpR.process(vocalHpR.process(vr)) * gateGain;
      vL[i] = vl.clamp(-0.98, 0.98);
      vR[i] = vr.clamp(-0.98, 0.98);

      // B. Triệt tiêu tiếng giọng hát nhỏ còn lẫn trong kênh Nhạc nền (Music Solo):
      // - Trừ phần giọng rò rỉ trong dải tần trung (280Hz - 3600Hz)
      final double vMidBandL = vocalBandFilterL.process(vl);
      final double vMidBandR = vocalBandFilterR.process(vr);

      double ml = mL[i] - vMidBandL * residualAlpha;
      double mr = mR[i] - vMidBandR * residualAlpha;

      // - Khi đang có giọng hát lớn (vocalEnv > 0.02), nén nhẹ dải Mid 1.6kHz của nhạc nền đi một chút
      //   để triệt tiêu nốt phần bóng giọng (vocal ghosting) còn sót lại
      final double dipBlend = (vocalEnv * 4.5).clamp(0.0, 0.85);
      final double dippedL = musicPresenceDipL.process(ml);
      final double dippedR = musicPresenceDipR.process(mr);
      ml = ml * (1.0 - dipBlend) + dippedL * dipBlend;
      mr = mr * (1.0 - dipBlend) + dippedR * dipBlend;

      mL[i] = ml.clamp(-0.98, 0.98);
      mR[i] = mr.clamp(-0.98, 0.98);
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

  factory _SimpleBiquad.bandPass(int sr, double freq, double q) {
    final double w0 = 2.0 * math.pi * freq / sr;
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

  factory _SimpleBiquad.peaking(int sr, double freq, double q, double gainDb) {
    final double a = math.pow(10.0, gainDb / 40.0).toDouble();
    final double w0 = 2.0 * math.pi * freq / sr;
    final double cosW = math.cos(w0);
    final double alpha = math.sin(w0) / (2.0 * q);
    final double a0 = 1.0 + alpha / a;
    return _SimpleBiquad(
      (1.0 + alpha * a) / a0,
      (-2.0 * cosW) / a0,
      (1.0 - alpha * a) / a0,
      (-2.0 * cosW) / a0,
      (1.0 - alpha / a) / a0,
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
