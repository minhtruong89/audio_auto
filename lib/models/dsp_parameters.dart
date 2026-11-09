import 'studio_mode.dart';
import 'voice_profile.dart';

/// Toàn bộ thông số của Pipeline Tách Nhạc & Chuỗi 5 Hiệu ứng DSP Làm đẹp Giọng
class DspParameters {
  // 0. Tách giọng & Cân bằng Stem (Vocal / Instrumental từ loa ngoài)
  final bool enableStemSeparation;
  final double vocalGainDb; // Độ lớn giọng hát sau khi tách (-6dB -> +8dB)
  final double musicGainDb; // Độ lớn nhạc nền từ loa (-12dB -> +4dB)
  final double stereoWidth; // Độ rộng không gian stereo (0.5 -> 1.5)

  // 1. Khử tạp âm & De-esser (Giảm tiếng xì/chói)
  final bool enableNoiseGateAndDeEsser;
  final double noiseGateThresholdDb; // (-65dB -> -30dB)
  final double deEsserFrequencyHz; // (4500Hz -> 8500Hz)
  final double deEsserAmount; // (0.0 -> 1.0)

  // 2. Pitch Correction / Auto-Tune
  final bool enablePitchCorrection;
  final double pitchCorrectionStrength; // Mức độ kéo về đúng nốt (0.0 -> 1.0)
  final double retuneSpeed; // Tốc độ kéo nốt (0.1: Tự nhiên -> 1.0: Cực nhanh kiểu T-Pain)

  // 3. Adaptive 5-Band Parametric EQ (dB: -8.0 -> +8.0)
  final bool enableEq;
  final double eqSub100HzDb; // Cắt ù / Bass mic
  final double eqLowMid280HzDb; // Độ ấm / Độ dày giọng
  final double eqMid1200HzDb; // Độ rõ / Giảm tiếng mũi (Nasal)
  final double eqHighMid3500HzDb; // Độ nổi bật trước nhạc nền (Presence)
  final double eqAir10kHzDb; // Độ sáng bay bổng (Air)

  // 4. Dynamic Vocal Compressor
  final bool enableCompressor;
  final double compThresholdDb; // (-36dB -> -6dB)
  final double compRatio; // (1.5:1 -> 8.0:1)
  final double compMakeupGainDb; // (0dB -> +9dB)

  // 5. Stereo Reverb & Echo Delay
  final bool enableReverbDelay;
  final double reverbRoomSize; // (0.1 -> 0.98)
  final double reverbDamping; // (0.1 -> 0.9)
  final double reverbWetMix; // (0.0 -> 0.65)
  final double delayTimeMs; // (80ms -> 380ms)
  final double delayFeedback; // (0.0 -> 0.55)
  final double delayMix; // (0.0 -> 0.45)

  // Thanh kéo cường độ tổng cho chế độ Smart Presets (0.0 -> 1.5, mặc định 1.0)
  final double masterIntensity;

  const DspParameters({
    this.enableStemSeparation = true,
    this.vocalGainDb = 3.0,
    this.musicGainDb = -1.5,
    this.stereoWidth = 1.15,
    this.enableNoiseGateAndDeEsser = true,
    this.noiseGateThresholdDb = -46.0,
    this.deEsserFrequencyHz = 6400.0,
    this.deEsserAmount = 0.45,
    this.enablePitchCorrection = true,
    this.pitchCorrectionStrength = 0.55,
    this.retuneSpeed = 0.5,
    this.enableEq = true,
    this.eqSub100HzDb = -3.0,
    this.eqLowMid280HzDb = 2.0,
    this.eqMid1200HzDb = -0.8,
    this.eqHighMid3500HzDb = 3.2,
    this.eqAir10kHzDb = 2.8,
    this.enableCompressor = true,
    this.compThresholdDb = -20.0,
    this.compRatio = 3.2,
    this.compMakeupGainDb = 3.5,
    this.enableReverbDelay = true,
    this.reverbRoomSize = 0.72,
    this.reverbDamping = 0.45,
    this.reverbWetMix = 0.28,
    this.delayTimeMs = 185.0,
    this.delayFeedback = 0.25,
    this.delayMix = 0.16,
    this.masterIntensity = 1.0,
  });

  /// Tự động nội suy bộ tham số DSP tối ưu từ Hồ sơ Giọng của người dùng (1-Touch Auto)
  factory DspParameters.fromVoiceProfile(UserVoiceProfile profile) {
    final gains = profile.eqCompensationGainsDb;
    final pitchNeed = (profile.pitchJitterPercent / 4.5).clamp(0.25, 0.88);
    final deEssNeed = (profile.sibilanceRatio * 1.4).clamp(0.2, 0.85);
    final compRatio = (2.2 + (profile.dynamicStabilityDb / 2.5)).clamp(2.0, 5.5);

    return DspParameters(
      enableStemSeparation: true,
      vocalGainDb: 3.2,
      musicGainDb: -1.8,
      stereoWidth: 1.2,
      enableNoiseGateAndDeEsser: true,
      noiseGateThresholdDb: (profile.noiseFloorDb + 4.0).clamp(-60.0, -32.0),
      deEsserFrequencyHz: profile.sibilancePeakHz.clamp(5000.0, 8200.0),
      deEsserAmount: deEssNeed,
      enablePitchCorrection: true,
      pitchCorrectionStrength: pitchNeed,
      retuneSpeed: (pitchNeed * 0.85).clamp(0.3, 0.8),
      enableEq: true,
      eqSub100HzDb: gains[0],
      eqLowMid280HzDb: gains[1],
      eqMid1200HzDb: gains[2],
      eqHighMid3500HzDb: gains[3],
      eqAir10kHzDb: gains[4],
      enableCompressor: true,
      compThresholdDb: -21.0,
      compRatio: compRatio,
      compMakeupGainDb: 3.5,
      enableReverbDelay: true,
      reverbRoomSize: 0.74,
      reverbDamping: 0.42,
      reverbWetMix: 0.27,
      delayTimeMs: 190.0,
      delayFeedback: 0.24,
      delayMix: 0.15,
      masterIntensity: 1.0,
    );
  }

  /// Tạo bộ tham số theo Preset + kết hợp với đặc trưng giọng của người dùng
  factory DspParameters.fromPreset(
    KaraokePresetStyle preset,
    UserVoiceProfile profile, {
    double intensity = 1.0,
    double vocalMusicBalance = 0.0, // -1.0 (nhiều nhạc) -> +1.0 (nhiều giọng)
  }) {
    final base = DspParameters.fromVoiceProfile(profile);
    final vocalBoost = 3.0 + vocalMusicBalance * 3.5;
    final musicAtten = -1.5 - vocalMusicBalance * 3.0;

    switch (preset) {
      case KaraokePresetStyle.aiProfileMatched:
        return base.copyWith(
          masterIntensity: intensity,
          vocalGainDb: vocalBoost,
          musicGainDb: musicAtten,
        );
      case KaraokePresetStyle.studioPop:
        return base.copyWith(
          masterIntensity: intensity,
          vocalGainDb: vocalBoost + 0.5,
          musicGainDb: musicAtten,
          pitchCorrectionStrength: 0.72,
          retuneSpeed: 0.68,
          eqSub100HzDb: -3.5,
          eqLowMid280HzDb: base.eqLowMid280HzDb * 0.8 + 1.2,
          eqHighMid3500HzDb: 3.8,
          eqAir10kHzDb: 3.5,
          compThresholdDb: -23.0,
          compRatio: 4.0,
          compMakeupGainDb: 4.2,
          reverbRoomSize: 0.65,
          reverbWetMix: 0.22,
          delayTimeMs: 160.0,
          delayMix: 0.12,
        );
      case KaraokePresetStyle.boleroSweet:
        return base.copyWith(
          masterIntensity: intensity,
          vocalGainDb: vocalBoost + 1.0,
          musicGainDb: musicAtten - 0.5,
          pitchCorrectionStrength: 0.50,
          retuneSpeed: 0.42,
          eqSub100HzDb: -2.0,
          eqLowMid280HzDb: 3.2,
          eqMid1200HzDb: 0.5,
          eqHighMid3500HzDb: 2.6,
          eqAir10kHzDb: 2.2,
          compThresholdDb: -19.0,
          compRatio: 2.8,
          reverbRoomSize: 0.86,
          reverbDamping: 0.35,
          reverbWetMix: 0.38,
          delayTimeMs: 245.0,
          delayFeedback: 0.36,
          delayMix: 0.26,
        );
      case KaraokePresetStyle.acousticNatural:
        return base.copyWith(
          masterIntensity: intensity,
          vocalGainDb: vocalBoost,
          musicGainDb: musicAtten + 0.5,
          pitchCorrectionStrength: 0.32,
          retuneSpeed: 0.30,
          eqSub100HzDb: -2.5,
          eqLowMid280HzDb: 1.4,
          eqMid1200HzDb: -0.5,
          eqHighMid3500HzDb: 2.0,
          eqAir10kHzDb: 2.5,
          compThresholdDb: -18.0,
          compRatio: 2.2,
          compMakeupGainDb: 2.2,
          reverbRoomSize: 0.52,
          reverbDamping: 0.55,
          reverbWetMix: 0.18,
          delayMix: 0.08,
        );
      case KaraokePresetStyle.liveStage:
        return base.copyWith(
          masterIntensity: intensity,
          vocalGainDb: vocalBoost + 1.5,
          musicGainDb: musicAtten - 1.0,
          pitchCorrectionStrength: 0.82,
          retuneSpeed: 0.78,
          eqSub100HzDb: -4.0,
          eqLowMid280HzDb: 2.2,
          eqHighMid3500HzDb: 4.5,
          eqAir10kHzDb: 3.8,
          compThresholdDb: -24.0,
          compRatio: 4.8,
          compMakeupGainDb: 4.8,
          reverbRoomSize: 0.82,
          reverbWetMix: 0.32,
          delayTimeMs: 210.0,
          delayFeedback: 0.30,
          delayMix: 0.22,
        );
    }
  }

  DspParameters copyWith({
    bool? enableStemSeparation,
    double? vocalGainDb,
    double? musicGainDb,
    double? stereoWidth,
    bool? enableNoiseGateAndDeEsser,
    double? noiseGateThresholdDb,
    double? deEsserFrequencyHz,
    double? deEsserAmount,
    bool? enablePitchCorrection,
    double? pitchCorrectionStrength,
    double? retuneSpeed,
    bool? enableEq,
    double? eqSub100HzDb,
    double? eqLowMid280HzDb,
    double? eqMid1200HzDb,
    double? eqHighMid3500HzDb,
    double? eqAir10kHzDb,
    bool? enableCompressor,
    double? compThresholdDb,
    double? compRatio,
    double? compMakeupGainDb,
    bool? enableReverbDelay,
    double? reverbRoomSize,
    double? reverbDamping,
    double? reverbWetMix,
    double? delayTimeMs,
    double? delayFeedback,
    double? delayMix,
    double? masterIntensity,
  }) {
    return DspParameters(
      enableStemSeparation: enableStemSeparation ?? this.enableStemSeparation,
      vocalGainDb: vocalGainDb ?? this.vocalGainDb,
      musicGainDb: musicGainDb ?? this.musicGainDb,
      stereoWidth: stereoWidth ?? this.stereoWidth,
      enableNoiseGateAndDeEsser:
          enableNoiseGateAndDeEsser ?? this.enableNoiseGateAndDeEsser,
      noiseGateThresholdDb: noiseGateThresholdDb ?? this.noiseGateThresholdDb,
      deEsserFrequencyHz: deEsserFrequencyHz ?? this.deEsserFrequencyHz,
      deEsserAmount: deEsserAmount ?? this.deEsserAmount,
      enablePitchCorrection:
          enablePitchCorrection ?? this.enablePitchCorrection,
      pitchCorrectionStrength:
          pitchCorrectionStrength ?? this.pitchCorrectionStrength,
      retuneSpeed: retuneSpeed ?? this.retuneSpeed,
      enableEq: enableEq ?? this.enableEq,
      eqSub100HzDb: eqSub100HzDb ?? this.eqSub100HzDb,
      eqLowMid280HzDb: eqLowMid280HzDb ?? this.eqLowMid280HzDb,
      eqMid1200HzDb: eqMid1200HzDb ?? this.eqMid1200HzDb,
      eqHighMid3500HzDb: eqHighMid3500HzDb ?? this.eqHighMid3500HzDb,
      eqAir10kHzDb: eqAir10kHzDb ?? this.eqAir10kHzDb,
      enableCompressor: enableCompressor ?? this.enableCompressor,
      compThresholdDb: compThresholdDb ?? this.compThresholdDb,
      compRatio: compRatio ?? this.compRatio,
      compMakeupGainDb: compMakeupGainDb ?? this.compMakeupGainDb,
      enableReverbDelay: enableReverbDelay ?? this.enableReverbDelay,
      reverbRoomSize: reverbRoomSize ?? this.reverbRoomSize,
      reverbDamping: reverbDamping ?? this.reverbDamping,
      reverbWetMix: reverbWetMix ?? this.reverbWetMix,
      delayTimeMs: delayTimeMs ?? this.delayTimeMs,
      delayFeedback: delayFeedback ?? this.delayFeedback,
      delayMix: delayMix ?? this.delayMix,
      masterIntensity: masterIntensity ?? this.masterIntensity,
    );
  }
}
