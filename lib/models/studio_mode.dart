/// 3 chế độ điều khiển trên màn hình Karaoke Studio để người dùng test và so sánh
enum StudioControlMode {
  oneTouchAuto(
    '1-Touch Auto',
    'Tự động 100% theo Hồ sơ giọng',
    'Chỉ cần 1 nút bấm, AI tự động tách giọng khỏi nhạc loa ngoài và bù trừ EQ, Auto-Tune, Reverb theo đúng đặc trưng giọng đã đo.',
  ),
  smartPresets(
    'Smart Presets',
    'Chọn Phong cách & Thanh kéo Cường độ',
    'Chọn nhanh phong cách nhạc (Phòng thu, Bolero, Acoustic, Hát Live) kết hợp thanh kéo mức độ can thiệp và cân bằng Giọng/Nhạc.',
  ),
  proMixer(
    'Pro Mixer',
    'Bàn trộn Kỹ thuật Chuyên sâu',
    'Can thiệp chi tiết từng hiệu ứng: Tách Stem, 5 cần EQ, Pitch Correction (Auto-Tune), Compressor, De-esser và Không gian Reverb/Delay.',
  );

  final String shortTitle;
  final String fullTitle;
  final String description;

  const StudioControlMode(this.shortTitle, this.fullTitle, this.description);
}

/// Các Preset phong cách âm nhạc cho chế độ Smart Presets
enum KaraokePresetStyle {
  aiProfileMatched(
    'Theo Hồ Sơ Giọng AI',
    'Tối ưu chuẩn xác theo 4 bước đo giọng của riêng bạn',
  ),
  studioPop(
    'Phòng Thu (Studio Pop)',
    'Giọng sáng, rõ nét, nén chặt, Reverb vừa phải hiện đại',
  ),
  boleroSweet(
    'Bolero / Trữ Tình',
    'Giọng dày ấm, ngân vang sâu, Echo mềm mại ngọt ngào',
  ),
  acousticNatural(
    'Acoustic Mộc',
    'Giữ chất giọng tự nhiên, khử ồn sạch, không gian phòng nhỏ ấm cúng',
  ),
  liveStage(
    'Sân Khấu Live / Remix',
    'Đẩy cao độ nổi bật giọng vượt lên nhạc nền sôi động, Auto-Tune rõ',
  );

  final String title;
  final String subtitle;

  const KaraokePresetStyle(this.title, this.subtitle);
}
