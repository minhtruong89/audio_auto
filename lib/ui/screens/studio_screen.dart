import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/mixer_controls.dart';
import '../widgets/waveform_ab_player.dart';

/// Màn hình Karaoke Enhancement Studio:
/// - Chọn file lưu sẵn / Thu âm trực tiếp Mic + Loa Karaoke / Nạp bản thu mẫu
/// - Nghe đối chiếu tức thì Bản Gốc (Before) vs Đã Làm Đẹp (After)
/// - Chuyển đổi linh hoạt giữa cả 3 phương án điều khiển (1-Touch, Smart Presets, Pro Mixer)
class KaraokeStudioScreen extends StatelessWidget {
  final AppController controller;

  const KaraokeStudioScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
      children: [
        // 1. Nguồn âm thanh đầu vào (Chọn file / Thu Mic Karaoke / Bản thu Mẫu)
        _buildSourceInputCard(context),
        const SizedBox(height: 14),

        // 2. Trình phát sóng âm & Đối chiếu tức thì Before / After
        WaveformAbPlayer(controller: controller),
        const SizedBox(height: 14),

        // 3. Thanh trạng thái xử lý & Báo cáo kỹ thuật DSP
        _buildDspReportBanner(context),
        const SizedBox(height: 14),

        // 4. Bảng điều khiển 3 Chế độ (Option 1: 1-Touch, Option 2: Presets, Option 3: Pro Mixer)
        StudioModeControlPanel(controller: controller),
      ],
    );
  }

  Widget _buildSourceInputCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.queue_music_rounded, color: AppTheme.accentCyan, size: 19),
              SizedBox(width: 8),
              Text(
                'Nguồn Thu Karaoke (Giọng Hát + Loa Ngoài)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    side: BorderSide(
                      color: AppTheme.accentCyan.withValues(alpha: 0.5),
                    ),
                  ),
                  onPressed: controller.isBusyProcessing
                      ? null
                      : controller.pickAudioFileFromDevice,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text(
                    'Chọn File Máy',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: controller.isRecordingKaraoke
                        ? AppTheme.accentRose
                        : AppTheme.primaryNeon,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  onPressed: controller.isBusyProcessing
                      ? null
                      : controller.toggleLiveKaraokeRecording,
                  icon: Icon(
                    controller.isRecordingKaraoke
                        ? Icons.stop_rounded
                        : Icons.mic_external_on_rounded,
                    size: 18,
                  ),
                  label: Text(
                    controller.isRecordingKaraoke ? 'Dừng Thu' : 'Thu Mic Hát',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    side: BorderSide(
                      color: AppTheme.accentEmerald.withValues(alpha: 0.5),
                    ),
                  ),
                  onPressed: controller.isBusyProcessing
                      ? null
                      : controller.loadBuiltInDemoKaraoke,
                  icon: const Icon(
                    Icons.library_music_outlined,
                    size: 18,
                    color: AppTheme.accentEmerald,
                  ),
                  label: const Text(
                    'Nạp Bản Mẫu',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentEmerald,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDspReportBanner(BuildContext context) {
    final report = controller.lastReport;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardElevated,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (controller.isBusyProcessing)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          else
            const Icon(
              Icons.graphic_eq_rounded,
              color: AppTheme.accentEmerald,
              size: 18,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              controller.statusMessage,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (report != null && controller.enhancedFilePath != null)
            IconButton(
              tooltip: 'Chia sẻ / Xuất file WAV đã làm đẹp',
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                final path = controller.enhancedFilePath;
                if (path != null) {
                  await SharePlus.instance.share(
                    ShareParams(
                      files: [XFile(path)],
                      text: 'Bản thu Karaoke đã làm đẹp bằng AI + DSP On-Device',
                    ),
                  );
                }
              },
              icon: const Icon(
                Icons.ios_share_rounded,
                size: 18,
                color: AppTheme.accentCyan,
              ),
            ),
        ],
      ),
    );
  }
}
