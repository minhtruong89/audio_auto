import 'studio_mode.dart';
import 'voice_profile.dart';

/// Toàn bộ thông số của Pipeline Tách Nhạc & Chuỗi 5 Hiệu ứng DSP Làm đẹp Giọng
class DspParameters {
  // 0. Tách giọng & Cân bằng Stem / Hòa trộn (Mix)
  final bool enableStemSeparation;
  final double vocalGainDb; // Độ lớn giọng hát sau khi tách (-6dB -> +8dB)
  final double musicGainDb; // Độ lớn nhạc nền từ loa (-12dB -> +4dB)
  final double stereoWidth; // Độ rộng không gian stereo tổng (0.5 -> 1.5)
  final double sidechainDuckingAmount; // Mức dìm nhẹ nhạc khi cất giọng (0.0 -> 1.0)
  final bool autoMatchVocalToMusicKey; // Tự động kéo tông giọng về khớp tông nhạc nền phát hiện được
  final bool scaleLockedAutoTune; // Khóa Auto-Tune chỉ kéo về 7 nốt hợp âm của tông nhạc

  // 0.5. Chuyển đổi Đặc trưng Giọng & Quãng Giọng (Voice Timbre & Pitch Adaptation)
  final bool enableVoiceConversion;
  final bool preserveSongKey; // true = Tự hát thật (KHÔNG dịch bán cung gây lệch tông nhạc beat), false = Đổi tông theo giọng mẫu
  final double targetProfileF0Hz; // Tần số F0 đặc trưng của giọng đã lưu (Hz)
  final double targetProfileCentroidHz; // Trọng tâm âm sắc của giọng đã lưu (Hz)
  final double voiceConversionStrength; // Mức độ ép màu giọng & cao độ về giọng đã lưu (0.0 -> 1.0)

  // 0.8. Tùy chỉnh chuyên sâu riêng cho Nhạc nền (Music Stem EQ & Tone)
  final bool enableMusicMasteringEq;
  final double musicTransposeSemitones; // Chỉnh Tone Nhạc (-6.0 -> +6.0 bán cung)
  final double musicStereoWidth; // Độ rộng Stereo riêng cho Nhạc nền (0.5 -> 1.6)
  final double musicEqSub100HzDb; // Bass nhạc nền (100Hz)
  final double musicEqLowMid280HzDb; // Độ ấm / Cắt ù phòng (280Hz)
  final double musicEqMid1200HzDb; // Trung âm nhạc nền (1.2kHz)
  final double musicEqHighMid3500HzDb; // Nhạc cụ / Vocal Pocket (3.5kHz)
  final double musicEqAir10kHzDb; // Độ sáng nhạc nền (10kHz)

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
    this.sidechainDuckingAmount = 0.45,
    this.autoMatchVocalToMusicKey = false,
    this.scaleLockedAutoTune = true,
    this.enableMusicMasteringEq = true,
    this.musicTransposeSemitones = 0.0,
    this.musicStereoWidth = 1.12,
    this.musicEqSub100HzDb = 0.8,
    this.musicEqLowMid280HzDb = -1.8,
    this.musicEqMid1200HzDb = -1.2,
    this.musicEqHighMid3500HzDb = -0.8,
    this.musicEqAir10kHzDb = 1.8,
    this.enableVoiceConversion = true,
    this.preserveSongKey = false,
    this.targetProfileF0Hz = 155.0,
    this.targetProfileCentroidHz = 1850.0,
    this.voiceConversionStrength = 0.85,
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
  /// Mỗi đặc trưng giọng (F0, Centroid, Dynamic, Jitter, Sibilance) sẽ định hình màu âm riêng biệt
  factory DspParameters.fromVoiceProfile(
    UserVoiceProfile profile, {
    bool preserveSongKey = false,
  }) {
    final gains = profile.eqCompensationGainsDb;
    final pitchNeed = (profile.pitchJitterPercent / 4.2).clamp(0.22, 0.90);
    final deEssNeed = (profile.sibilanceRatio * 1.45).clamp(0.18, 0.85);
    final compRatio = (2.0 + (profile.dynamicStabilityDb / 2.2)).clamp(1.8, 5.5);

    // Cá nhân hóa không gian vang & độ dày theo quãng giọng (F0) và độ sáng (Centroid)
    final bool isDeepVoice = profile.speakingF0MeanHz < 165.0;
    final double roomByVoice = isDeepVoice
        ? 0.54 // Giọng trầm cần phòng gọn hơn để không bị ù
        : 0.68; // Giọng cao/thanh hợp với đuôi vang rộng hơn
    final double wetBySmoothness =
        (0.16 + (1.0 - profile.warmthScore) * 0.10).clamp(0.15, 0.25);
    final double delayMixByPower =
        (0.08 + (1.0 - profile.powerScore) * 0.08).clamp(0.07, 0.15);

    return DspParameters(
      enableStemSeparation: true,
      vocalGainDb: (2.6 + (1.0 - profile.powerScore) * 1.8).clamp(2.2, 4.5),
      musicGainDb: -1.6,
      stereoWidth: isDeepVoice ? 1.12 : 1.24,
      sidechainDuckingAmount: 0.45,
      autoMatchVocalToMusicKey: false,
      scaleLockedAutoTune: true,
      enableMusicMasteringEq: true,
      musicTransposeSemitones: 0.0,
      musicStereoWidth: 1.12,
      musicEqSub100HzDb: 0.8,
      musicEqLowMid280HzDb: -1.8,
      musicEqMid1200HzDb: -1.2,
      musicEqHighMid3500HzDb: -0.8,
      musicEqAir10kHzDb: 1.8,
      enableVoiceConversion: true,
      preserveSongKey: preserveSongKey,
      targetProfileF0Hz: profile.speakingF0MeanHz.clamp(85.0, 400.0),
      targetProfileCentroidHz: profile.spectralCentroidHz.clamp(950.0, 3600.0),
      voiceConversionStrength: 0.88,
      enableNoiseGateAndDeEsser: true,
      noiseGateThresholdDb: (profile.noiseFloorDb + 4.0).clamp(-60.0, -32.0),
      deEsserFrequencyHz: profile.sibilancePeakHz.clamp(5000.0, 8200.0),
      deEsserAmount: deEssNeed,
      enablePitchCorrection: true,
      pitchCorrectionStrength: pitchNeed,
      retuneSpeed: (pitchNeed * 0.85).clamp(0.3, 0.82),
      enableEq: true,
      eqSub100HzDb: gains[0],
      eqLowMid280HzDb: gains[1],
      eqMid1200HzDb: gains[2],
      eqHighMid3500HzDb: gains[3],
      eqAir10kHzDb: gains[4],
      enableCompressor: true,
      compThresholdDb: -20.5,
      compRatio: compRatio,
      compMakeupGainDb: (2.8 + (1.0 - profile.powerScore) * 1.5).clamp(2.5, 4.5),
      enableReverbDelay: true,
      reverbRoomSize: roomByVoice,
      reverbDamping: isDeepVoice ? 0.52 : 0.40,
      reverbWetMix: wetBySmoothness,
      delayTimeMs: isDeepVoice ? 165.0 : 195.0,
      delayFeedback: 0.18,
      delayMix: delayMixByPower,
      masterIntensity: 1.0,
    );
  }

  /// Chế độ Thử Nghiệm Thuần Túy: CHỈ tách giọng và đổi đặc trưng sang Giọng Đã Lưu
  /// (Tắt toàn bộ Auto-Tune, EQ làm đẹp, Compressor, De-Esser, Reverb và Echo Delay)
  factory DspParameters.pureVoiceConversionOnly(
    UserVoiceProfile profile, {
    bool preserveSongKey = false,
  }) {
    return DspParameters(
      enableStemSeparation: true,
      vocalGainDb: 0.0,
      musicGainDb: 0.0,
      stereoWidth: 1.0,
      sidechainDuckingAmount: 0.0,
      autoMatchVocalToMusicKey: false,
      scaleLockedAutoTune: false,
      enableMusicMasteringEq: false,
      musicTransposeSemitones: 0.0,
      musicStereoWidth: 1.0,
      musicEqSub100HzDb: 0.0,
      musicEqLowMid280HzDb: 0.0,
      musicEqMid1200HzDb: 0.0,
      musicEqHighMid3500HzDb: 0.0,
      musicEqAir10kHzDb: 0.0,
      enableVoiceConversion: true,
      preserveSongKey: preserveSongKey,
      targetProfileF0Hz: profile.speakingF0MeanHz.clamp(85.0, 400.0),
      targetProfileCentroidHz: profile.spectralCentroidHz.clamp(950.0, 3600.0),
      voiceConversionStrength: 1.0,
      enableNoiseGateAndDeEsser: false,
      enablePitchCorrection: false,
      enableEq: false,
      eqSub100HzDb: 0.0,
      eqLowMid280HzDb: 0.0,
      eqMid1200HzDb: 0.0,
      eqHighMid3500HzDb: 0.0,
      eqAir10kHzDb: 0.0,
      enableCompressor: false,
      enableReverbDelay: false,
      reverbWetMix: 0.0,
      delayMix: 0.0,
      masterIntensity: 1.0,
    );
  }

  /// Tạo bộ tham số theo Preset + kết hợp chặt chẽ với đặc trưng Hồ sơ giọng của người dùng
  factory DspParameters.fromPreset(
    KaraokePresetStyle preset,
    UserVoiceProfile profile, {
    double intensity = 1.0,
    double vocalMusicBalance = 0.0, // -1.0 (nhiều nhạc) -> +1.0 (nhiều giọng)
    bool preserveSongKey = false,
  }) {
    final base = DspParameters.fromVoiceProfile(
      profile,
      preserveSongKey: preserveSongKey,
    );
    final vocalBoost = base.vocalGainDb + vocalMusicBalance * 3.5;
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
          vocalGainDb: vocalBoost + 0.4,
          musicGainDb: musicAtten,
          pitchCorrectionStrength: (base.pitchCorrectionStrength + 0.15).clamp(0.35, 0.92),
          retuneSpeed: 0.68,
          eqSub100HzDb: base.eqSub100HzDb - 0.5,
          eqLowMid280HzDb: base.eqLowMid280HzDb + 0.5,
          eqMid1200HzDb: base.eqMid1200HzDb,
          eqHighMid3500HzDb: base.eqHighMid3500HzDb + 1.0,
          eqAir10kHzDb: base.eqAir10kHzDb + 1.2,
          compThresholdDb: -22.0,
          compRatio: (base.compRatio + 0.6).clamp(2.5, 5.5),
          compMakeupGainDb: base.compMakeupGainDb + 0.5,
          reverbRoomSize: 0.55,
          reverbWetMix: 0.16,
          delayTimeMs: 155.0,
          delayMix: 0.09,
        );
      case KaraokePresetStyle.boleroSweet:
        return base.copyWith(
          masterIntensity: intensity,
          vocalGainDb: vocalBoost + 0.8,
          musicGainDb: musicAtten - 0.5,
          pitchCorrectionStrength: base.pitchCorrectionStrength,
          retuneSpeed: 0.45,
          eqSub100HzDb: base.eqSub100HzDb + 0.5,
          eqLowMid280HzDb: base.eqLowMid280HzDb + 1.8,
          eqMid1200HzDb: base.eqMid1200HzDb + 0.6,
          eqHighMid3500HzDb: base.eqHighMid3500HzDb,
          eqAir10kHzDb: base.eqAir10kHzDb,
          compThresholdDb: -19.0,
          compRatio: base.compRatio,
          reverbRoomSize: 0.76,
          reverbDamping: 0.38,
          reverbWetMix: 0.28,
          delayTimeMs: 225.0,
          delayFeedback: 0.26,
          delayMix: 0.18,
        );
      case KaraokePresetStyle.acousticNatural:
        return base.copyWith(
          masterIntensity: intensity,
          vocalGainDb: vocalBoost,
          musicGainDb: musicAtten + 0.5,
          pitchCorrectionStrength: (base.pitchCorrectionStrength * 0.65).clamp(0.15, 0.55),
          retuneSpeed: 0.30,
          eqSub100HzDb: base.eqSub100HzDb,
          eqLowMid280HzDb: base.eqLowMid280HzDb * 0.85,
          eqMid1200HzDb: base.eqMid1200HzDb,
          eqHighMid3500HzDb: base.eqHighMid3500HzDb * 0.85,
          eqAir10kHzDb: base.eqAir10kHzDb * 0.9,
          compThresholdDb: -18.0,
          compRatio: 2.1,
          compMakeupGainDb: 2.2,
          reverbRoomSize: 0.46,
          reverbDamping: 0.55,
          reverbWetMix: 0.13,
          delayMix: 0.06,
        );
      case KaraokePresetStyle.liveStage:
        return base.copyWith(
          masterIntensity: intensity,
          vocalGainDb: vocalBoost + 1.2,
          musicGainDb: musicAtten - 1.0,
          pitchCorrectionStrength: (base.pitchCorrectionStrength + 0.22).clamp(0.5, 0.95),
          retuneSpeed: 0.78,
          eqSub100HzDb: base.eqSub100HzDb - 1.0,
          eqLowMid280HzDb: base.eqLowMid280HzDb + 0.8,
          eqHighMid3500HzDb: base.eqHighMid3500HzDb + 1.6,
          eqAir10kHzDb: base.eqAir10kHzDb + 1.4,
          compThresholdDb: -23.0,
          compRatio: 4.5,
          compMakeupGainDb: 4.2,
          reverbRoomSize: 0.72,
          reverbWetMix: 0.24,
          delayTimeMs: 200.0,
          delayFeedback: 0.22,
          delayMix: 0.15,
        );
    }
  }

  DspParameters copyWith({
    bool? enableStemSeparation,
    double? vocalGainDb,
    double? musicGainDb,
    double? stereoWidth,
    double? sidechainDuckingAmount,
    bool? autoMatchVocalToMusicKey,
    bool? scaleLockedAutoTune,
    bool? enableMusicMasteringEq,
    double? musicTransposeSemitones,
    double? musicStereoWidth,
    double? musicEqSub100HzDb,
    double? musicEqLowMid280HzDb,
    double? musicEqMid1200HzDb,
    double? musicEqHighMid3500HzDb,
    double? musicEqAir10kHzDb,
    bool? enableVoiceConversion,
    bool? preserveSongKey,
    double? targetProfileF0Hz,
    double? targetProfileCentroidHz,
    double? voiceConversionStrength,
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
      sidechainDuckingAmount:
          sidechainDuckingAmount ?? this.sidechainDuckingAmount,
      autoMatchVocalToMusicKey:
          autoMatchVocalToMusicKey ?? this.autoMatchVocalToMusicKey,
      scaleLockedAutoTune: scaleLockedAutoTune ?? this.scaleLockedAutoTune,
      enableMusicMasteringEq:
          enableMusicMasteringEq ?? this.enableMusicMasteringEq,
      musicTransposeSemitones:
          musicTransposeSemitones ?? this.musicTransposeSemitones,
      musicStereoWidth: musicStereoWidth ?? this.musicStereoWidth,
      musicEqSub100HzDb: musicEqSub100HzDb ?? this.musicEqSub100HzDb,
      musicEqLowMid280HzDb: musicEqLowMid280HzDb ?? this.musicEqLowMid280HzDb,
      musicEqMid1200HzDb: musicEqMid1200HzDb ?? this.musicEqMid1200HzDb,
      musicEqHighMid3500HzDb:
          musicEqHighMid3500HzDb ?? this.musicEqHighMid3500HzDb,
      musicEqAir10kHzDb: musicEqAir10kHzDb ?? this.musicEqAir10kHzDb,
      enableVoiceConversion:
          enableVoiceConversion ?? this.enableVoiceConversion,
      preserveSongKey: preserveSongKey ?? this.preserveSongKey,
      targetProfileF0Hz: targetProfileF0Hz ?? this.targetProfileF0Hz,
      targetProfileCentroidHz:
          targetProfileCentroidHz ?? this.targetProfileCentroidHz,
      voiceConversionStrength:
          voiceConversionStrength ?? this.voiceConversionStrength,
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
