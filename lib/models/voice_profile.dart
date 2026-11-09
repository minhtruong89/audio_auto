import 'dart:convert';

/// Phân loại quãng giọng tự động dựa trên tần số cơ bản (F0)
enum VocalRangeType {
  bass('Nam Trầm (Bass)', '80Hz - 330Hz'),
  baritone('Nam Trung (Baritone)', '100Hz - 400Hz'),
  tenor('Nam Cao (Tenor)', '130Hz - 520Hz'),
  alto('Nữ Trầm/Trung (Alto)', '175Hz - 700Hz'),
  mezzoSoprano('Nữ Trung Cao (Mezzo-Soprano)', '200Hz - 880Hz'),
  soprano('Nữ Cao (Soprano)', '250Hz - 1050Hz');

  final String title;
  final String rangeLabel;
  const VocalRangeType(this.title, this.rangeLabel);
}

/// Hồ sơ đặc trưng giọng của người dùng được trích xuất qua 4 bước thu âm
class UserVoiceProfile {
  final String id;
  final DateTime createdAt;

  // Bước 1: Tạp âm nền & Giọng nói tự nhiên
  final double noiseFloorDb; // Ngưỡng tạp âm môi trường (-65dB đến -30dB)
  final double speakingF0MeanHz; // Cao độ trung bình khi nói (Hz)
  final double spectralCentroidHz; // Độ sáng âm sắc trung bình (Hz)

  // Bước 2: Quãng giọng (Pitch Range Glide)
  final double minPitchHz;
  final double maxPitchHz;
  final double comfortZoneHz;
  final VocalRangeType vocalType;

  // Bước 3: Độ ổn định hơi & Cao độ (Sustained Note)
  final double pitchJitterPercent; // Độ chênh/dao động cao độ (%)
  final double vibratoRateHz; // Tần số rung giọng tự nhiên (Hz)
  final double dynamicStabilityDb; // Độ đều âm lượng (dB)

  // Bước 4: Âm xì (Sibilance) & Đường cong bù EQ 5 dải
  final double sibilancePeakHz; // Tần số chói âm s/x/ch (thường 5500 - 8000 Hz)
  final double sibilanceRatio; // Tỷ lệ năng lượng âm xì (0.0 - 1.0)

  /// 5 dải bù EQ tự động (dB) từ -6.0 đến +6.0:
  /// [0]: Low Cut / Sub (100Hz)
  /// [1]: Low-Mid / Độ ấm (280Hz)
  /// [2]: Mid / Độ rõ (1200Hz)
  /// [3]: High-Mid / Độ nổi bật (3500Hz)
  /// [4]: Air / Độ bay bổng (10000Hz)
  final List<double> eqCompensationGainsDb;

  const UserVoiceProfile({
    required this.id,
    required this.createdAt,
    required this.noiseFloorDb,
    required this.speakingF0MeanHz,
    required this.spectralCentroidHz,
    required this.minPitchHz,
    required this.maxPitchHz,
    required this.comfortZoneHz,
    required this.vocalType,
    required this.pitchJitterPercent,
    required this.vibratoRateHz,
    required this.dynamicStabilityDb,
    required this.sibilancePeakHz,
    required this.sibilanceRatio,
    required this.eqCompensationGainsDb,
  });

  /// Hồ sơ mặc định thông minh khi người dùng muốn test ngay mà chưa đo
  factory UserVoiceProfile.defaultDemo() {
    return UserVoiceProfile(
      id: 'demo_profile',
      createdAt: DateTime(2026, 11, 9),
      noiseFloorDb: -48.0,
      speakingF0MeanHz: 155.0,
      spectralCentroidHz: 1850.0,
      minPitchHz: 110.0,
      maxPitchHz: 440.0,
      comfortZoneHz: 210.0,
      vocalType: VocalRangeType.baritone,
      pitchJitterPercent: 2.4,
      vibratoRateHz: 5.5,
      dynamicStabilityDb: 3.2,
      sibilancePeakHz: 6400.0,
      sibilanceRatio: 0.28,
      eqCompensationGainsDb: const [-2.5, 1.8, -0.8, 3.2, 2.5],
    );
  }

  /// Điểm số 5 cạnh trên biểu đồ Radar (thang 0.0 -> 1.0)
  double get warmthScore =>
      (1.0 - ((spectralCentroidHz - 1200.0) / 2200.0)).clamp(0.25, 0.95);

  double get brightnessScore =>
      ((spectralCentroidHz - 1000.0) / 2400.0).clamp(0.25, 0.95);

  double get powerScore =>
      (1.0 - (dynamicStabilityDb / 10.0)).clamp(0.3, 0.96);

  double get pitchAccuracyScore =>
      (1.0 - (pitchJitterPercent / 8.0)).clamp(0.3, 0.98);

  double get smoothnessScore =>
      (1.0 - sibilanceRatio * 1.4).clamp(0.3, 0.95);

  /// Tóm tắt nhận xét AI bằng tiếng Việt dựa trên thông số giọng
  String get aiSummary {
    final List<String> notes = [];
    if (warmthScore > 0.65) {
      notes.add('Giọng có độ ấm tự nhiên tốt ở dải trầm-trung');
    } else {
      notes.add('Giọng hơi mỏng ở dải Low-Mid, AI sẽ bù +${eqCompensationGainsDb[1].toStringAsFixed(1)}dB ở 280Hz');
    }

    if (brightnessScore < 0.55) {
      notes.add('thiếu độ mở ở dải cao (Air), sẽ tăng nhẹ dải 3.5kHz & 10kHz để giọng thoát và bắt mic hơn');
    } else {
      notes.add('dải cao sáng rõ');
    }

    if (pitchJitterPercent > 2.0) {
      notes.add('cần hỗ trợ Pitch Correction (Auto-Tune) mức trung bình để giữ cao độ vững ở nốt ngân dài');
    } else {
      notes.add('độ ổn định cao độ rất tốt, chỉ cần Auto-Tune nhẹ tự nhiên');
    }

    return '${vocalType.title}: ${notes.join(', ')}.';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'noiseFloorDb': noiseFloorDb,
      'speakingF0MeanHz': speakingF0MeanHz,
      'spectralCentroidHz': spectralCentroidHz,
      'minPitchHz': minPitchHz,
      'maxPitchHz': maxPitchHz,
      'comfortZoneHz': comfortZoneHz,
      'vocalType': vocalType.name,
      'pitchJitterPercent': pitchJitterPercent,
      'vibratoRateHz': vibratoRateHz,
      'dynamicStabilityDb': dynamicStabilityDb,
      'sibilancePeakHz': sibilancePeakHz,
      'sibilanceRatio': sibilanceRatio,
      'eqCompensationGainsDb': eqCompensationGainsDb,
    };
  }

  factory UserVoiceProfile.fromMap(Map<String, dynamic> map) {
    return UserVoiceProfile(
      id: map['id'] as String? ?? 'profile',
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      noiseFloorDb: (map['noiseFloorDb'] as num?)?.toDouble() ?? -48.0,
      speakingF0MeanHz: (map['speakingF0MeanHz'] as num?)?.toDouble() ?? 160.0,
      spectralCentroidHz: (map['spectralCentroidHz'] as num?)?.toDouble() ?? 1800.0,
      minPitchHz: (map['minPitchHz'] as num?)?.toDouble() ?? 110.0,
      maxPitchHz: (map['maxPitchHz'] as num?)?.toDouble() ?? 440.0,
      comfortZoneHz: (map['comfortZoneHz'] as num?)?.toDouble() ?? 220.0,
      vocalType: VocalRangeType.values.firstWhere(
        (e) => e.name == map['vocalType'],
        orElse: () => VocalRangeType.baritone,
      ),
      pitchJitterPercent: (map['pitchJitterPercent'] as num?)?.toDouble() ?? 2.0,
      vibratoRateHz: (map['vibratoRateHz'] as num?)?.toDouble() ?? 5.5,
      dynamicStabilityDb: (map['dynamicStabilityDb'] as num?)?.toDouble() ?? 3.0,
      sibilancePeakHz: (map['sibilancePeakHz'] as num?)?.toDouble() ?? 6500.0,
      sibilanceRatio: (map['sibilanceRatio'] as num?)?.toDouble() ?? 0.25,
      eqCompensationGainsDb: (map['eqCompensationGainsDb'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [-2.0, 1.5, -0.5, 3.0, 2.0],
    );
  }

  String toJson() => jsonEncode(toMap());

  factory UserVoiceProfile.fromJson(String source) =>
      UserVoiceProfile.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
