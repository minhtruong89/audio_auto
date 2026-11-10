/// 3 nhóm tab điều khiển trực quan theo từng thành phần âm thanh:
/// - Hòa trộn: Cách phối quyện Giọng + Nhạc, Phong cách nhanh, Khớp tông tự động
/// - Giọng Vocal: Chỉnh sâu 5-Band EQ Vocal, Auto-Tune khóa âm giai, Compressor, De-Esser, Reverb
/// - Nhạc nền: Chỉnh Tone Beat (±6 bán cung), Độ rộng Stereo và 5-Band EQ riêng cho Nhạc nền
enum StudioControlMode {
  mix(
    'Hòa trộn',
    'Hòa trộn Giọng & Nhạc nền',
    'Chọn phong cách nhanh (1-Touch / Presets), cân bằng độ hòa quyện Giọng/Nhạc, dìm nhạc nhường giọng và khớp tông tự động.',
  ),
  vocal(
    'Giọng Vocal',
    'Tinh chỉnh Giọng Hát (Vocal)',
    'Can thiệp chi tiết luồng giọng: chuyển màu giọng, Auto-Tune khóa âm giai, 5-Band EQ Vocal, Compressor, De-Esser & Reverb.',
  ),
  music(
    'Nhạc nền',
    'Tinh chỉnh Nhạc Nền (Beat)',
    'Thay đổi Tone nhạc nền (±6 bán cung), độ rộng không gian Stereo và 5-Band EQ riêng cho luồng nhạc nền.',
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
