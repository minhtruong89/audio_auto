import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Dữ liệu âm thanh PCM đã giải mã trong bộ nhớ để phục vụ phân tích & DSP
class PcmAudioData {
  final int sampleRate;
  final int channels;
  final Float64List leftChannel;
  final Float64List rightChannel;

  PcmAudioData({
    required this.sampleRate,
    required this.channels,
    required this.leftChannel,
    Float64List? rightChannel,
  }) : rightChannel = rightChannel ?? Float64List.fromList(leftChannel);

  int get length => leftChannel.length;

  double get durationSeconds =>
      sampleRate > 0 ? leftChannel.length / sampleRate : 0.0;

  /// Tạo tín hiệu Mono phục vụ phân tích đặc trưng giọng (FFT, YIN Pitch)
  Float64List toMono() {
    final mono = Float64List(leftChannel.length);
    for (int i = 0; i < leftChannel.length; i++) {
      mono[i] = 0.5 * (leftChannel[i] + rightChannel[i]);
    }
    return mono;
  }

  /// Trích xuất biên độ sóng âm (Waveform peaks) để vẽ lên giao diện A/B Player
  List<double> extractWaveformPeaks(int bucketCount) {
    if (leftChannel.isEmpty || bucketCount <= 0) {
      return List<double>.filled(bucketCount, 0.05);
    }
    final int step = math.max(1, leftChannel.length ~/ bucketCount);
    final List<double> peaks = List<double>.filled(bucketCount, 0.0);

    for (int b = 0; b < bucketCount; b++) {
      final int start = b * step;
      final int end = math.min(leftChannel.length, start + step);
      double maxAbs = 0.0;
      for (int i = start; i < end; i++) {
        final double v =
            (0.5 * (leftChannel[i].abs() + rightChannel[i].abs()));
        if (v > maxAbs) maxAbs = v;
      }
      peaks[b] = maxAbs.clamp(0.03, 1.0);
    }
    return peaks;
  }
}

/// Dịch vụ Đọc/Ghi file WAV chuẩn 16-bit PCM và tạo file Karaoke mẫu để test
class AudioIoService {
  /// Đọc file WAV (hoặc raw PCM) từ đường dẫn thành [PcmAudioData]
  Future<PcmAudioData> readWavFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw ArgumentError('Không tìm thấy file âm thanh: $filePath');
    }
    final bytes = await file.readAsBytes();
    return decodeWavBytes(bytes);
  }

  /// Giải mã mảng byte WAV chuẩn RIFF/WAVE (16-bit hoặc 8/24/32-bit PCM)
  PcmAudioData decodeWavBytes(Uint8List bytes) {
    if (bytes.length < 44) {
      return generateDemoKaraokeMix(durationSeconds: 6.0);
    }

    final bd = ByteData.sublistView(bytes);
    // Kiểm tra header "RIFF"
    final isRiff = bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46;

    if (!isRiff) {
      // Nếu người dùng chọn 1 file khác định dạng raw, giải mã an toàn dưới dạng 16-bit mono/stereo
      return _decodeFallbackRaw16(bytes, sampleRate: 44100, channels: 2);
    }

    int channels = 1;
    int sampleRate = 44100;
    int bitsPerSample = 16;
    int dataOffset = 44;
    int dataLength = bytes.length - 44;

    int offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      if (chunkId == 'fmt ' && offset + 24 <= bytes.length) {
        channels = bd.getUint16(offset + 10, Endian.little);
        sampleRate = bd.getUint32(offset + 12, Endian.little);
        bitsPerSample = bd.getUint16(offset + 22, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = offset + 8;
        dataLength = math.min(chunkSize, bytes.length - dataOffset);
        break;
      }
      offset += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    final int bytesPerSample = (bitsPerSample ~/ 8).clamp(1, 4);
    final int frameSize = bytesPerSample * channels;
    if (frameSize <= 0 || dataOffset >= bytes.length) {
      return generateDemoKaraokeMix(durationSeconds: 6.0);
    }

    final int frameCount = dataLength ~/ frameSize;
    final left = Float64List(frameCount);
    final right = Float64List(frameCount);

    int pos = dataOffset;
    for (int i = 0; i < frameCount; i++) {
      if (pos + frameSize > bytes.length) break;
      final double l = _readSampleNormalized(bd, pos, bitsPerSample);
      final double r = channels > 1
          ? _readSampleNormalized(bd, pos + bytesPerSample, bitsPerSample)
          : l;
      left[i] = l;
      right[i] = r;
      pos += frameSize;
    }

    return PcmAudioData(
      sampleRate: sampleRate,
      channels: channels,
      leftChannel: left,
      rightChannel: right,
    );
  }

  double _readSampleNormalized(ByteData bd, int pos, int bitsPerSample) {
    if (bitsPerSample == 16) {
      return bd.getInt16(pos, Endian.little) / 32768.0;
    } else if (bitsPerSample == 8) {
      return (bd.getUint8(pos) - 128) / 128.0;
    } else if (bitsPerSample == 24) {
      int b0 = bd.getUint8(pos);
      int b1 = bd.getUint8(pos + 1);
      int b2 = bd.getInt8(pos + 2);
      int val = b0 | (b1 << 8) | (b2 << 16);
      return val / 8388608.0;
    } else if (bitsPerSample == 32) {
      return (bd.getInt32(pos, Endian.little) / 2147483648.0).clamp(-1.0, 1.0);
    }
    return 0.0;
  }

  PcmAudioData _decodeFallbackRaw16(
    Uint8List bytes, {
    required int sampleRate,
    required int channels,
  }) {
    final bd = ByteData.sublistView(bytes);
    final frameSize = 2 * channels;
    final frameCount = bytes.length ~/ frameSize;
    final left = Float64List(frameCount);
    final right = Float64List(frameCount);
    for (int i = 0; i < frameCount; i++) {
      final int pos = i * frameSize;
      left[i] = bd.getInt16(pos, Endian.little) / 32768.0;
      right[i] = channels > 1
          ? bd.getInt16(pos + 2, Endian.little) / 32768.0
          : left[i];
    }
    return PcmAudioData(
      sampleRate: sampleRate,
      channels: channels,
      leftChannel: left,
      rightChannel: right,
    );
  }

  /// Mã hóa [PcmAudioData] thành định dạng WAV 16-bit Stereo chuẩn và lưu ra đĩa
  Future<File> writeWavFile(PcmAudioData audio, String outputPath) async {
    final bytes = encodeWavBytes(audio);
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes, flush: true);
  }

  Uint8List encodeWavBytes(PcmAudioData audio) {
    final int numFrames = audio.length;
    const int numChannels = 2;
    const int bitsPerSample = 16;
    const int bytesPerSample = bitsPerSample ~/ 8;
    final int dataSize = numFrames * numChannels * bytesPerSample;
    final int totalSize = 44 + dataSize;

    final buffer = Uint8List(totalSize);
    final bd = ByteData.sublistView(buffer);

    // RIFF header
    buffer.setRange(0, 4, 'RIFF'.codeUnits);
    bd.setUint32(4, totalSize - 8, Endian.little);
    buffer.setRange(8, 12, 'WAVE'.codeUnits);

    // fmt subchunk
    buffer.setRange(12, 16, 'fmt '.codeUnits);
    bd.setUint32(16, 16, Endian.little); // PCM chunk size
    bd.setUint16(20, 1, Endian.little); // AudioFormat = 1 (PCM)
    bd.setUint16(22, numChannels, Endian.little);
    bd.setUint32(24, audio.sampleRate, Endian.little);
    bd.setUint32(
      28,
      audio.sampleRate * numChannels * bytesPerSample,
      Endian.little,
    );
    bd.setUint16(32, numChannels * bytesPerSample, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);

    // data subchunk
    buffer.setRange(36, 40, 'data'.codeUnits);
    bd.setUint32(40, dataSize, Endian.little);

    int offset = 44;
    for (int i = 0; i < numFrames; i++) {
      final int lInt = (audio.leftChannel[i].clamp(-1.0, 1.0) * 32767.0).round();
      final int rInt =
          (audio.rightChannel[i].clamp(-1.0, 1.0) * 32767.0).round();
      bd.setInt16(offset, lInt, Endian.little);
      bd.setInt16(offset + 2, rInt, Endian.little);
      offset += 4;
    }

    return buffer;
  }

  /// Tạo một bản thu Karaoke giả lập (Gồm giọng hát bị phô nhẹ, hơi tối, lẫn tiếng loa nhạc nền và tạp âm)
  /// để bạn có thể test ngay lập tức hiệu quả Trước / Sau (Before / After) trên máy ảo hoặc máy thật!
  PcmAudioData generateDemoKaraokeMix({
    double durationSeconds = 8.0,
    int sampleRate = 44100,
  }) {
    final int numSamples = (durationSeconds * sampleRate).round();
    final left = Float64List(numSamples);
    final right = Float64List(numSamples);
    final rng = math.Random(42);

    // Giai điệu câu hát mẫu (Nốt A3 -> C4 -> D4 -> E4 -> G4 -> E4 -> D4 -> A3)
    // Kèm độ lệch pitch nhẹ (~ +18 cents) để bộ Pitch Correction kéo lại
    final List<double> melodyNotesHz = [
      220.0,
      261.63,
      293.66,
      329.63,
      392.00,
      329.63,
      293.66,
      220.0,
    ];

    double vocalPhase = 0.0;
    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final int noteIdx =
          ((t / durationSeconds) * melodyNotesHz.length).floor().clamp(
                0,
                melodyNotesHz.length - 1,
              );
      final double targetNote = melodyNotesHz[noteIdx];

      // Mô phỏng người hát hơi chênh cao độ (detuned ~1.5%) + rung giọng tự nhiên
      final double vibrato = 4.0 * math.sin(2 * math.pi * 5.4 * t);
      final double pitchDrift = targetNote * 0.016 * math.sin(2 * math.pi * 0.9 * t);
      final double instantF0 = targetNote + vibrato + pitchDrift;

      vocalPhase += 2 * math.pi * instantF0 / sampleRate;

      // Bao hình câu hát (ngắt nhịp tự nhiên giữa các nốt)
      final double noteProgress = (t * (melodyNotesHz.length / durationSeconds)) % 1.0;
      final double env = math.sin(math.pi * noteProgress.clamp(0.0, 1.0));

      // Tổng hợp sóng giọng hát có hài âm (Formants vùng 500Hz, 1200Hz, 2800Hz) + chút âm xì
      double rawVocal = 0.50 * math.sin(vocalPhase) +
          0.32 * math.sin(2 * vocalPhase) +
          0.18 * math.sin(3 * vocalPhase) +
          0.10 * math.sin(5 * vocalPhase) +
          0.06 * math.sin(8 * vocalPhase);

      // Thêm chút âm xì sibilance ở đầu mỗi chữ
      if (noteProgress < 0.08) {
        rawVocal += 0.14 * math.sin(2 * math.pi * 6400.0 * t);
      }
      rawVocal *= env * 0.42;

      // Mô phỏng tiếng nhạc Karaoke từ loa ngoài (Hợp âm Am - F - C - G trải rộng Stereo)
      final double chordRoot = (noteIdx < 2)
          ? 110.0
          : (noteIdx < 4)
              ? 87.31
              : (noteIdx < 6)
                  ? 130.81
                  : 98.0;

      final double musicL = 0.16 * math.sin(2 * math.pi * chordRoot * t) +
          0.10 * math.sin(2 * math.pi * chordRoot * 1.5 * t + 0.4) +
          0.08 * math.sin(2 * math.pi * chordRoot * 2.0 * t);
      final double musicR = 0.16 * math.sin(2 * math.pi * chordRoot * t) +
          0.10 * math.sin(2 * math.pi * chordRoot * 1.5 * t - 0.4) +
          0.08 * math.sin(2 * math.pi * chordRoot * 2.5 * t);

      // Nhịp trống bass nhẹ từ loa karaoke (mỗi 0.5s)
      final double beatPhase = (t % 0.5) / 0.5;
      final double kick = math.exp(-beatPhase * 14.0) *
          math.sin(2 * math.pi * (95.0 - 45.0 * beatPhase) * t) *
          0.18;

      // Nhiễu nền phòng (Room noise)
      final double roomNoise = (rng.nextDouble() * 2.0 - 1.0) * 0.008;

      left[i] = (rawVocal + musicL + kick + roomNoise).clamp(-0.98, 0.98);
      right[i] = (rawVocal + musicR + kick + roomNoise).clamp(-0.98, 0.98);
    }

    return PcmAudioData(
      sampleRate: sampleRate,
      channels: 2,
      leftChannel: left,
      rightChannel: right,
    );
  }

  /// Tạo âm thanh mẫu 8 bậc thang âm "Đồ - Rê - Mi - Pha - Son - La - Si - Đố" (C3 -> C4)
  /// để người dùng bấm nghe mẫu trước khi hát ở Bước 2 (Đo quãng giọng)
  PcmAudioData generateDoReMiGuideScale({
    double durationSeconds = 4.0,
    int sampleRate = 44100,
  }) {
    final int numSamples = (durationSeconds * sampleRate).round();
    final left = Float64List(numSamples);
    final right = Float64List(numSamples);

    // Tần số 8 nốt Đồ -> Đố (C3 = 130.81Hz lên C4 = 261.63Hz, phù hợp cả nam và nữ bắt tông)
    const List<double> scaleHz = [
      130.81, // Đồ
      146.83, // Rê
      164.81, // Mi
      174.61, // Pha
      196.00, // Son
      220.00, // La
      246.94, // Si
      261.63, // Đố
    ];

    double phase = 0.0;
    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final double stepFloat = (t / durationSeconds) * scaleHz.length;
      final int idx = stepFloat.floor().clamp(0, scaleHz.length - 1);
      final double noteProgress = stepFloat - idx;
      final double f0 = scaleHz[idx];

      phase += 2.0 * math.pi * f0 / sampleRate;
      // Âm sắc tiếng đàn Piano/Bell ấm dịu để làm mẫu bắt tông
      final double env = math.sin(math.pi * noteProgress.clamp(0.0, 1.0)) *
          math.exp(-noteProgress * 1.4);
      final double sample = (0.55 * math.sin(phase) +
              0.25 * math.sin(2.0 * phase) +
              0.12 * math.sin(3.0 * phase)) *
          env *
          0.55;

      left[i] = sample;
      right[i] = sample;
    }

    return PcmAudioData(
      sampleRate: sampleRate,
      channels: 2,
      leftChannel: left,
      rightChannel: right,
    );
  }
}
