import 'package:flutter/material.dart';
import '../../models/studio_mode.dart';
import '../../state/app_controller.dart';
import '../theme/app_theme.dart';

/// Giao diện cho Chế độ 1 (1-Touch Auto), Chế độ 2 (Smart Presets) và Chế độ 3 (Pro Mixer)
class StudioModeControlPanel extends StatelessWidget {
  final AppController controller;

  const StudioModeControlPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildModeSelectorBar(),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: switch (controller.controlMode) {
            StudioControlMode.oneTouchAuto => _buildOneTouchPanel(context),
            StudioControlMode.smartPresets => _buildSmartPresetsPanel(context),
            StudioControlMode.proMixer => _buildProMixerPanel(context),
          },
        ),
      ],
    );
  }

  /// Thanh chọn nhanh 3 phương án điều khiển để người dùng test đối chiếu
  Widget _buildModeSelectorBar() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        children: StudioControlMode.values.map((mode) {
          final bool selected = controller.controlMode == mode;
          return Expanded(
            child: GestureDetector(
              onTap: () => controller.setStudioControlMode(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(
                          colors: [AppTheme.primaryNeon, Color(0xFF536DFE)],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      mode.shortTitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected ? Colors.white : AppTheme.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ===========================================================================
  // OPTION 1: CHỈ 1 NÚT TỰ ĐỘNG DUY NHẤT DỰA TRÊN HỒ SƠ GIỌNG ĐÃ ĐO
  // ===========================================================================
  Widget _buildOneTouchPanel(BuildContext context) {
    final profile = controller.voiceProfile;
    final p = controller.dspParams;

    return Container(
      key: const ValueKey('mode_one_touch'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primaryNeon.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNeon.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_fix_high_rounded,
                  color: AppTheme.accentCyan,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      StudioControlMode.oneTouchAuto.fullTitle,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Hồ sơ hiện tại: ${profile.vocalType.title} (${profile.vocalType.rangeLabel})',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.accentCyan,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            profile.aiSummary,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _badgeChip('Tách Vocal On-Device: BẬT'),
              _badgeChip(
                'Auto-Tune: ${(p.pitchCorrectionStrength * 100).round()}%',
              ),
              _badgeChip(
                'Bù Ấm 280Hz: ${p.eqLowMid280HzDb >= 0 ? "+" : ""}${p.eqLowMid280HzDb.toStringAsFixed(1)}dB',
              ),
              _badgeChip(
                'Độ sáng 3.5kHz: +${p.eqHighMid3500HzDb.toStringAsFixed(1)}dB',
              ),
              _badgeChip(
                'De-esser @${(p.deEsserFrequencyHz / 1000).toStringAsFixed(1)}kHz',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNeon,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: controller.isBusyProcessing
                  ? null
                  : controller.resetDspToVoiceProfile,
              icon: const Icon(Icons.bolt_rounded),
              label: const Text(
                'Tự Động Làm Đẹp Giọng 1 Chạm (Theo Hồ Sơ Giọng)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // OPTION 2: SMART PRESETS (CHỌN PHONG CÁCH + THANH KÉO MỨC ĐỘ CAN THIỆP)
  // ===========================================================================
  Widget _buildSmartPresetsPanel(BuildContext context) {
    return Container(
      key: const ValueKey('mode_smart_presets'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Chọn Phong cách Âm thanh (Presets)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...KaraokePresetStyle.values.map((preset) {
            final bool selected = controller.selectedPreset == preset;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  await controller.updatePresetConfiguration(preset: preset);
                  await controller.applyDspToCurrentTrack();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.primaryNeon.withValues(alpha: 0.2)
                        : AppTheme.cardElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? AppTheme.accentCyan
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: selected
                            ? AppTheme.accentCyan
                            : AppTheme.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              preset.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: selected
                                    ? Colors.white
                                    : AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              preset.subtitle,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const Divider(height: 22),

          // Thanh kéo Mức độ can thiệp DSP (0% -> 150%)
          _sliderRow(
            label: 'Mức độ can thiệp làm đẹp (AI Intensity)',
            valueText: '${(controller.presetIntensity * 100).round()}%',
            value: controller.presetIntensity,
            min: 0.2,
            max: 1.4,
            onChanged: (v) =>
                controller.updatePresetConfiguration(intensity: v),
            onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
          ),
          const SizedBox(height: 6),

          // Thanh kéo Cân bằng Giọng hát vs Nhạc nền từ loa
          _sliderRow(
            label: 'Cân bằng Giọng hát / Nhạc nền Loa ngoài',
            valueText: controller.vocalMusicBalance >= 0
                ? 'Ưu tiên Giọng (+${(controller.vocalMusicBalance * 100).round()}%)'
                : 'Ưu tiên Nhạc (${(controller.vocalMusicBalance * 100).round()}%)',
            value: controller.vocalMusicBalance,
            min: -0.8,
            max: 0.8,
            onChanged: (v) =>
                controller.updatePresetConfiguration(vocalMusicBalance: v),
            onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // OPTION 3: PRO MIXER (BÀN TRỘN KỸ THUẬT CHUYÊN SÂU)
  // ===========================================================================
  Widget _buildProMixerPanel(BuildContext context) {
    final p = controller.dspParams;

    return Container(
      key: const ValueKey('mode_pro_mixer'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Bàn Trộn Kỹ Thuật Chuyên Sâu (Pro Mixer)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: controller.resetDspToVoiceProfile,
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Reset về AI gợi ý', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 1. Tách Giọng & Trộn Stem
          _proSectionHeader(
            title: '1. Tách Giọng & Cân Bằng Nhạc Loa Ngoài (Stem Mixer)',
            enabled: p.enableStemSeparation,
            onToggle: (v) {
              controller.updateProMixerParams(
                p.copyWith(enableStemSeparation: v),
              );
              controller.applyDspToCurrentTrack();
            },
          ),
          _sliderRow(
            label: 'Âm lượng Giọng hát đã tách (Vocal Gain)',
            valueText: '${p.vocalGainDb >= 0 ? "+" : ""}${p.vocalGainDb.toStringAsFixed(1)} dB',
            value: p.vocalGainDb,
            min: -4.0,
            max: 8.0,
            onChanged: (v) =>
                controller.updateProMixerParams(p.copyWith(vocalGainDb: v)),
            onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
          ),
          _sliderRow(
            label: 'Âm lượng Nhạc nền từ loa (Instrumental Gain)',
            valueText: '${p.musicGainDb >= 0 ? "+" : ""}${p.musicGainDb.toStringAsFixed(1)} dB',
            value: p.musicGainDb,
            min: -10.0,
            max: 4.0,
            onChanged: (v) =>
                controller.updateProMixerParams(p.copyWith(musicGainDb: v)),
            onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
          ),
          const Divider(height: 20),

          // 2. Pitch Correction / Auto-Tune
          _proSectionHeader(
            title: '2. Pitch Correction / Auto-Tune (Chỉnh chênh phô)',
            enabled: p.enablePitchCorrection,
            onToggle: (v) {
              controller.updateProMixerParams(
                p.copyWith(enablePitchCorrection: v),
              );
              controller.applyDspToCurrentTrack();
            },
          ),
          _sliderRow(
            label: 'Lực kéo chuẩn nốt (Correction Strength)',
            valueText: '${(p.pitchCorrectionStrength * 100).round()}%',
            value: p.pitchCorrectionStrength,
            min: 0.0,
            max: 1.0,
            onChanged: (v) => controller.updateProMixerParams(
              p.copyWith(pitchCorrectionStrength: v),
            ),
            onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
          ),
          _sliderRow(
            label: 'Tốc độ bắt nốt (Retune Speed)',
            valueText: '${(p.retuneSpeed * 100).round()}%',
            value: p.retuneSpeed,
            min: 0.1,
            max: 1.0,
            onChanged: (v) =>
                controller.updateProMixerParams(p.copyWith(retuneSpeed: v)),
            onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
          ),
          const Divider(height: 20),

          // 3. 5-Band Parametric EQ
          _proSectionHeader(
            title: '3. 5-Band Parametric EQ (Bù dải tần giọng)',
            enabled: p.enableEq,
            onToggle: (v) {
              controller.updateProMixerParams(p.copyWith(enableEq: v));
              controller.applyDspToCurrentTrack();
            },
          ),
          _sliderRow(
            label: '100Hz (Cắt ù Bass mic)',
            valueText: '${p.eqSub100HzDb.toStringAsFixed(1)} dB',
            value: p.eqSub100HzDb,
            min: -8.0,
            max: 4.0,
            onChanged: (v) =>
                controller.updateProMixerParams(p.copyWith(eqSub100HzDb: v)),
            onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
          ),
          _sliderRow(
            label: '280Hz (Độ ấm & Dày giọng - Warmth)',
            valueText: '${p.eqLowMid280HzDb >= 0 ? "+" : ""}${p.eqLowMid280HzDb.toStringAsFixed(1)} dB',
            value: p.eqLowMid280HzDb,
            min: -6.0,
            max: 6.0,
            onChanged: (v) =>
                controller.updateProMixerParams(p.copyWith(eqLowMid280HzDb: v)),
            onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
          ),
          _sliderRow(
            label: '1.2kHz (Giảm giọng mũi / Nasal)',
            valueText: '${p.eqMid1200HzDb >= 0 ? "+" : ""}${p.eqMid1200HzDb.toStringAsFixed(1)} dB',
            value: p.eqMid1200HzDb,
            min: -6.0,
            max: 6.0,
            onChanged: (v) =>
                controller.updateProMixerParams(p.copyWith(eqMid1200HzDb: v)),
            onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
          ),
          _sliderRow(
            label: '3.5kHz (Độ nổi bật giọng - Presence)',
            valueText: '${p.eqHighMid3500HzDb >= 0 ? "+" : ""}${p.eqHighMid3500HzDb.toStringAsFixed(1)} dB',
            value: p.eqHighMid3500HzDb,
            min: -6.0,
            max: 7.0,
            onChanged: (v) => controller.updateProMixerParams(
              p.copyWith(eqHighMid3500HzDb: v),
            ),
            onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
          ),
          _sliderRow(
            label: '10kHz (Độ bay bổng phòng thu - Air)',
            valueText: '${p.eqAir10kHzDb >= 0 ? "+" : ""}${p.eqAir10kHzDb.toStringAsFixed(1)} dB',
            value: p.eqAir10kHzDb,
            min: -6.0,
            max: 7.0,
            onChanged: (v) =>
                controller.updateProMixerParams(p.copyWith(eqAir10kHzDb: v)),
            onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
          ),
          const Divider(height: 20),

          // 4. Compressor & De-Esser
          _proSectionHeader(
            title: '4. Vocal Compressor & De-Esser (Làm đều & Giảm chói)',
            enabled: p.enableCompressor,
            onToggle: (v) {
              controller.updateProMixerParams(
                p.copyWith(enableCompressor: v, enableNoiseGateAndDeEsser: v),
              );
              controller.applyDspToCurrentTrack();
            },
          ),
          _sliderRow(
            label: 'Tỷ lệ nén (Compressor Ratio)',
            valueText: '${p.compRatio.toStringAsFixed(1)} : 1',
            value: p.compRatio,
            min: 1.5,
            max: 6.5,
            onChanged: (v) =>
                controller.updateProMixerParams(p.copyWith(compRatio: v)),
            onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
          ),
          _sliderRow(
            label: 'Giảm tiếng xì s/x/ch (De-Esser Amount)',
            valueText: '${(p.deEsserAmount * 100).round()}%',
            value: p.deEsserAmount,
            min: 0.0,
            max: 0.9,
            onChanged: (v) =>
                controller.updateProMixerParams(p.copyWith(deEsserAmount: v)),
            onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
          ),
          const Divider(height: 20),

          // 5. Stereo Reverb & Echo Delay
          _proSectionHeader(
            title: '5. Stereo Reverb & Echo Delay (Độ vang hòa quyện)',
            enabled: p.enableReverbDelay,
            onToggle: (v) {
              controller.updateProMixerParams(p.copyWith(enableReverbDelay: v));
              controller.applyDspToCurrentTrack();
            },
          ),
          _sliderRow(
            label: 'Độ lớn phòng vang (Reverb Room Size)',
            valueText: '${(p.reverbRoomSize * 100).round()}%',
            value: p.reverbRoomSize,
            min: 0.2,
            max: 0.95,
            onChanged: (v) =>
                controller.updateProMixerParams(p.copyWith(reverbRoomSize: v)),
            onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
          ),
          _sliderRow(
            label: 'Mức độ pha tiếng vang (Reverb Wet Mix)',
            valueText: '${(p.reverbWetMix * 100).round()}%',
            value: p.reverbWetMix,
            min: 0.0,
            max: 0.6,
            onChanged: (v) =>
                controller.updateProMixerParams(p.copyWith(reverbWetMix: v)),
            onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
          ),
          _sliderRow(
            label: 'Độ ngân nhại đuôi câu (Echo Delay Mix)',
            valueText: '${(p.delayMix * 100).round()}%',
            value: p.delayMix,
            min: 0.0,
            max: 0.45,
            onChanged: (v) =>
                controller.updateProMixerParams(p.copyWith(delayMix: v)),
            onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
          ),
        ],
      ),
    );
  }

  Widget _proSectionHeader({
    required String title,
    required bool enabled,
    required ValueChanged<bool> onToggle,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.accentCyan,
            ),
          ),
        ),
        Switch(
          value: enabled,
          activeThumbColor: AppTheme.accentCyan,
          onChanged: onToggle,
        ),
      ],
    );
  }

  Widget _sliderRow({
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary,
              ),
            ),
            Text(
              valueText,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }

  Widget _badgeChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.cardElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}
