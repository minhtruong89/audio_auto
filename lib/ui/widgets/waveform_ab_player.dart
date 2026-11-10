import 'package:flutter/material.dart';
import '../../state/app_controller.dart';
import '../theme/app_theme.dart';

/// Thanh phát nhạc kèm sóng âm trực quan và nút gạt chuyển đổi tức thì:
/// [Bản Thu Gốc (Before)]  <--->  [Đã Làm Hay AI+DSP (After)]
class WaveformAbPlayer extends StatelessWidget {
  final AppController controller;

  const WaveformAbPlayer({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final AudioListenMode mode = controller.listenMode;
    final bool isEnhanced = mode != AudioListenMode.original;
    final List<double> peaks;
    final Color activeColor;
    final String modeBadgeText;
    final IconData modeIcon;

    final bool usedAiOnnx = controller.lastReport?.usedAiOnnxModel ?? false;
    switch (mode) {
      case AudioListenMode.original:
        peaks = controller.originalWaveform;
        activeColor = AppTheme.accentAmber;
        modeBadgeText = 'Đang nghe: Bản thu thô (Chưa tách)';
        modeIcon = Icons.mic_none;
        break;
      case AudioListenMode.enhancedMix:
        peaks = controller.enhancedWaveform;
        activeColor = AppTheme.accentCyan;
        modeBadgeText = usedAiOnnx
            ? 'AI UVR-ONNX • Khớp Giọng + Nhạc'
            : 'Đã tách STFT • Khớp Giọng + Nhạc';
        modeIcon = Icons.auto_awesome;
        break;
      case AudioListenMode.vocalSolo:
        peaks = controller.vocalSoloWaveform;
        activeColor = AppTheme.accentEmerald;
        modeBadgeText = usedAiOnnx
            ? 'SOLO GIỌNG (AI UVR): Chỉ Vocal đã chỉnh'
            : 'SOLO GIỌNG: Chỉ nghe Vocal đã tách';
        modeIcon = Icons.record_voice_over;
        break;
      case AudioListenMode.musicSolo:
        peaks = controller.musicSoloWaveform;
        activeColor = AppTheme.primaryNeon;
        modeBadgeText = usedAiOnnx
            ? 'SOLO NHẠC (AI UVR): Beat sạch không lời'
            : 'SOLO NHẠC: Chỉ nghe Nhạc nền đã tách';
        modeIcon = Icons.music_note;
        break;
    }

    final int totalMs = controller.totalDuration.inMilliseconds;
    final int currentMs =
        controller.currentPosition.inMilliseconds.clamp(0, totalMs > 0 ? totalMs : 1);
    final double progress = totalMs > 0 ? currentMs / totalMs : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isEnhanced
              ? activeColor.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.12),
          width: 1.4,
        ),
        boxShadow: [
          if (isEnhanced)
            BoxShadow(
              color: activeColor.withValues(alpha: 0.08),
              blurRadius: 18,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hàng tiêu đề bài
          Row(
            children: [
              Icon(
                modeIcon,
                color: activeColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  controller.currentTrackName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Hàng 4 chế độ nghe kiểm tra: Gốc | Đã chỉnh | Chỉ Giọng (Test tách) | Chỉ Nhạc
          _build4WayModeSelector(mode),
          const SizedBox(height: 14),

          // Sóng âm tương tác (Chạm để tua)
          GestureDetector(
            onTapDown: (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null || totalMs <= 0) return;
              final double ratio =
                  (details.localPosition.dx / (box.size.width - 32))
                      .clamp(0.0, 1.0);
              controller.seekTo(
                Duration(milliseconds: (totalMs * ratio).round()),
              );
            },
            child: SizedBox(
              height: 58,
              width: double.infinity,
              child: CustomPaint(
                painter: _WaveformBarsPainter(
                  peaks: peaks,
                  progress: progress,
                  activeColor: activeColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Hàng nút Play/Pause + Thời gian + Thông số hiệu quả DSP
          Row(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      isEnhanced ? AppTheme.primaryNeon : AppTheme.cardElevated,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onPressed: controller.togglePlayPause,
                icon: Icon(
                  controller.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 22,
                ),
                label: Text(
                  controller.isPlaying ? 'Tạm dừng' : 'Nghe thử',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_formatDuration(controller.currentPosition)} / ${_formatDuration(controller.totalDuration)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              if (controller.lastReport != null)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.cardElevated,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      modeBadgeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: activeColor,
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

  Widget _build4WayModeSelector(AudioListenMode currentMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.bgDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: WrapAlignment.spaceBetween,
        children: [
          _abTabButton(
            label: 'Gốc (Before)',
            icon: Icons.history,
            selected: currentMode == AudioListenMode.original,
            activeColor: AppTheme.accentAmber,
            onTap: () => controller.setListenMode(AudioListenMode.original),
          ),
          _abTabButton(
            label: 'Đã chỉnh (Mix)',
            icon: Icons.auto_awesome,
            selected: currentMode == AudioListenMode.enhancedMix,
            activeColor: AppTheme.accentCyan,
            onTap: () => controller.setListenMode(AudioListenMode.enhancedMix),
          ),
          _abTabButton(
            label: 'Chỉ Giọng (Test tách)',
            icon: Icons.record_voice_over,
            selected: currentMode == AudioListenMode.vocalSolo,
            activeColor: AppTheme.accentEmerald,
            onTap: () => controller.setListenMode(AudioListenMode.vocalSolo),
          ),
          _abTabButton(
            label: 'Chỉ Nhạc',
            icon: Icons.music_note,
            selected: currentMode == AudioListenMode.musicSolo,
            activeColor: AppTheme.primaryNeon,
            onTap: () => controller.setListenMode(AudioListenMode.musicSolo),
          ),
        ],
      ),
    );
  }

  Widget _abTabButton({
    required String label,
    required IconData icon,
    required bool selected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? activeColor.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? activeColor : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? activeColor : AppTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.2,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? activeColor : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$min:$sec';
  }
}

class _WaveformBarsPainter extends CustomPainter {
  final List<double> peaks;
  final double progress;
  final Color activeColor;

  _WaveformBarsPainter({
    required this.peaks,
    required this.progress,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final int n = peaks.length;
    final double barSpace = size.width / n;
    final double barWidth = (barSpace * 0.62).clamp(2.0, 6.0);
    final double midY = size.height / 2;

    for (int i = 0; i < n; i++) {
      final double barProgress = i / n;
      final bool played = barProgress <= progress;
      final double h = (peaks[i].clamp(0.06, 1.0) * size.height * 0.92);

      final paint = Paint()
        ..color = played
            ? activeColor
            : activeColor.withValues(alpha: 0.28)
        ..style = PaintingStyle.fill;

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(i * barSpace + barSpace / 2, midY),
          width: barWidth,
          height: h,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformBarsPainter oldDelegate) => true;
}
