import 'package:flutter/material.dart';
import '../../models/studio_mode.dart';
import '../../state/app_controller.dart';
import '../theme/app_theme.dart';

/// Giao diện 3 Tab gom gọn, trực quan & phân màu riêng biệt:
/// 1. [Hòa trộn] (Xanh Cyan): Phong cách nhanh, Mục tiêu, Khớp Tông Tự Động, Cân bằng & Dìm nhạc nhường giọng
/// 2. [Giọng Vocal] (Xanh Ngọc Emerald): Chuyển giọng, Scale-Locked Auto-Tune, 5-Band EQ Vocal, Compressor, Reverb
/// 3. [Nhạc nền] (Vàng Hổ Phách Amber): Chromagram Key, Chỉnh Tone Beat (±6 bán cung), Stereo Width & 5-Band EQ Beat
class StudioModeControlPanel extends StatelessWidget {
  final AppController controller;

  const StudioModeControlPanel({super.key, required this.controller});

  Color _accentForMode(StudioControlMode mode) {
    switch (mode) {
      case StudioControlMode.mix:
        return AppTheme.accentCyan;
      case StudioControlMode.vocal:
        return AppTheme.accentEmerald;
      case StudioControlMode.music:
        return AppTheme.accentAmber;
    }
  }

  IconData _iconForMode(StudioControlMode mode) {
    switch (mode) {
      case StudioControlMode.mix:
        return Icons.tune_rounded;
      case StudioControlMode.vocal:
        return Icons.record_voice_over_rounded;
      case StudioControlMode.music:
        return Icons.library_music_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeMode = controller.controlMode;
    final accent = _accentForMode(activeMode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _build3TabBar(activeMode),
        const SizedBox(height: 12),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accent,
            thumbColor: accent,
            overlayColor: accent.withValues(alpha: 0.18),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
            trackHeight: 3.5,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: switch (activeMode) {
              StudioControlMode.mix => _buildMixTab(context, accent),
              StudioControlMode.vocal => _buildVocalTab(context, accent),
              StudioControlMode.music => _buildMusicTab(context, accent),
            },
          ),
        ),
      ],
    );
  }

  /// Thanh 3 Tab màu sắc riêng biệt: Hòa trộn | Giọng Vocal | Nhạc nền
  Widget _build3TabBar(StudioControlMode activeMode) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        children: StudioControlMode.values.map((mode) {
          final bool selected = activeMode == mode;
          final Color color = _accentForMode(mode);
          return Expanded(
            child: GestureDetector(
              onTap: () => controller.setStudioControlMode(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                decoration: BoxDecoration(
                  color: selected
                      ? color.withValues(alpha: 0.20)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? color : Colors.transparent,
                    width: 1.3,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _iconForMode(mode),
                      size: 16,
                      color: selected ? color : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        mode.shortTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                          color: selected ? color : AppTheme.textSecondary,
                        ),
                      ),
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
  // TAB 1: HÒA TRỘN (Màu Cyan - Cân bằng Giọng/Nhạc, Presets nhanh & Khớp Tông)
  // ===========================================================================
  Widget _buildMixTab(BuildContext context, Color accent) {
    final p = controller.dspParams;
    final profile = controller.voiceProfile;
    final report = controller.lastReport;
    final detectedKey = report?.detectedMusicKey;
    final bool keepKey = controller.preserveSongKey;

    return _themedTabContainer(
      key: const ValueKey('tab_mix'),
      accent: accent,
      title: 'Hòa Trộn Giọng & Nhạc Nền',
      subtitle:
          'Gom gọn chế độ 1 chạm, phong cách nhanh và cách quyện Giọng + Nhạc.',
      icon: Icons.tune_rounded,
      headerAction: TextButton.icon(
        onPressed: controller.isBusyProcessing
            ? null
            : controller.resetDspToVoiceProfile,
        icon: Icon(Icons.auto_fix_high_rounded, size: 16, color: accent),
        label: Text(
          'AI 1 Chạm',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
      ),
      children: [
        // 1. Mục tiêu giọng (Đổi theo giọng lưu vs Tự hát giữ tông)
        Row(
          children: [
            Expanded(
              child: _goalButton(
                title: 'Áp Giọng Đã Lưu',
                subtitle: 'Dịch tông + âm sắc mẫu',
                icon: Icons.switch_account_rounded,
                selected: !keepKey,
                activeColor: accent,
                onTap: controller.isBusyProcessing
                    ? null
                    : () => controller.setPreserveSongKey(false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _goalButton(
                title: 'Tự Hát (Giữ Tông)',
                subtitle: 'Không lệch beat thật',
                icon: Icons.mic_none_rounded,
                selected: keepKey,
                activeColor: AppTheme.accentEmerald,
                onTap: controller.isBusyProcessing
                    ? null
                    : () => controller.setPreserveSongKey(true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 2. Phong cách nhanh (1-Touch AI + Smart Presets + Chỉ Đổi Giọng Thô)
        Text(
          'Phong Cách Nhanh (${profile.displayLabelWithType})',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            ...KaraokePresetStyle.values.map((preset) {
              final bool selected =
                  !controller.isPureDryVoiceTest &&
                  controller.selectedPreset == preset;
              return ChoiceChip(
                label: Text(
                  preset == KaraokePresetStyle.aiProfileMatched
                      ? 'Theo AI Giọng'
                      : preset.title.split('(').first.trim(),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Colors.black : AppTheme.textPrimary,
                  ),
                ),
                selected: selected,
                selectedColor: accent,
                backgroundColor: AppTheme.bgDark,
                side: BorderSide(
                  color: selected
                      ? accent
                      : Colors.white.withValues(alpha: 0.12),
                ),
                onSelected: controller.isBusyProcessing
                    ? null
                    : (_) async {
                        await controller.updatePresetConfiguration(
                          preset: preset,
                        );
                        await controller.applyDspToCurrentTrack();
                      },
              );
            }),
            ChoiceChip(
              label: Text(
                'Chỉ Đổi Giọng (Thô)',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: controller.isPureDryVoiceTest
                      ? FontWeight.w800
                      : FontWeight.w600,
                  color: controller.isPureDryVoiceTest
                      ? Colors.black
                      : AppTheme.accentEmerald,
                ),
              ),
              selected: controller.isPureDryVoiceTest,
              selectedColor: AppTheme.accentEmerald,
              backgroundColor: AppTheme.bgDark,
              side: BorderSide(
                color: controller.isPureDryVoiceTest
                    ? AppTheme.accentEmerald
                    : AppTheme.accentEmerald.withValues(alpha: 0.45),
              ),
              onSelected: controller.isBusyProcessing
                  ? null
                  : (_) => controller.applyPureVoiceConversionOnly(),
            ),
          ],
        ),
        const Divider(height: 22),

        // 3. Khớp Tông Tự Động (Chromagram Key Detection + Scale-Locked)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.bgDark.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: p.autoMatchVocalToMusicKey
                  ? accent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.piano_rounded, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      detectedKey != null
                          ? 'Tông Nhạc AI (Chromagram): ${detectedKey.labelVi}'
                          : 'Tông Nhạc AI (Chromagram): Đang chờ phân tích',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
              if (detectedKey != null) ...[
                const SizedBox(height: 4),
                Text(
                  detectedKey.suggestedVocalShiftSemitones == 0
                      ? 'Giọng hát đang nằm trong âm giai ${detectedKey.shortName} (khớp tông nhạc nền).'
                      : 'Phát hiện giọng và nhạc đang lệch ${detectedKey.suggestedVocalShiftSemitones.abs()} bán cung (khuyên dùng dịch ${detectedKey.suggestedVocalShiftSemitones > 0 ? "+" : ""}${detectedKey.suggestedVocalShiftSemitones} st để khớp ${detectedKey.shortName}).',
                  style: TextStyle(
                    fontSize: 11.2,
                    color: detectedKey.suggestedVocalShiftSemitones == 0
                        ? AppTheme.textSecondary
                        : AppTheme.accentAmber,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              _compactSwitchRow(
                label: 'Khớp Tông Tự Động (Auto Key Sync)',
                subtitle: 'Kéo giọng về đúng tông hợp âm nhạc nền khi bị lệch quá',
                value: p.autoMatchVocalToMusicKey,
                accent: accent,
                onChanged: (v) {
                  controller.updateProMixerParams(
                    p.copyWith(autoMatchVocalToMusicKey: v),
                  );
                  controller.applyDspToCurrentTrack();
                },
              ),
              _compactSwitchRow(
                label: 'Khóa Auto-Tune theo 7 nốt Tông Nhạc (Scale-Locked)',
                subtitle: 'Tránh Auto-Tune kéo nhầm vào nốt ngoài tông bài hát',
                value: p.scaleLockedAutoTune,
                accent: accent,
                onChanged: (v) {
                  controller.updateProMixerParams(
                    p.copyWith(scaleLockedAutoTune: v),
                  );
                  controller.applyDspToCurrentTrack();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 4. Thông số Hòa quyện Giọng & Nhạc
        _sliderRow(
          label: 'Cân bằng Giọng hát / Nhạc nền',
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
        _sliderRow(
          label: 'Dìm nhạc nhường chỗ giọng (Sidechain Ducking)',
          valueText: '${(p.sidechainDuckingAmount * 100).round()}%',
          value: p.sidechainDuckingAmount,
          min: 0.0,
          max: 1.0,
          onChanged: (v) => controller.updateProMixerParams(
            p.copyWith(sidechainDuckingAmount: v),
          ),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
        _sliderRow(
          label: 'Độ quyện Vang chung (Glue Reverb)',
          valueText: '${(p.reverbWetMix * 100).round()}%',
          value: p.reverbWetMix,
          min: 0.0,
          max: 0.6,
          onChanged: (v) => controller.updateProMixerParams(
            p.copyWith(enableReverbDelay: v > 0.01, reverbWetMix: v),
          ),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
        _sliderRow(
          label: 'Độ rộng Không gian Stereo tổng (Master Width)',
          valueText: '${(p.stereoWidth * 100).round()}%',
          value: p.stereoWidth,
          min: 0.6,
          max: 1.5,
          onChanged: (v) =>
              controller.updateProMixerParams(p.copyWith(stereoWidth: v)),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 2: GIỌNG VOCAL (Màu Emerald - Chuyển giọng, Auto-Tune & 5-Band EQ Vocal)
  // ===========================================================================
  Widget _buildVocalTab(BuildContext context, Color accent) {
    final p = controller.dspParams;

    return _themedTabContainer(
      key: const ValueKey('tab_vocal'),
      accent: accent,
      title: 'Chỉnh Chuyên Sâu Giọng Vocal',
      subtitle:
          '5-Band EQ riêng cho giọng hát, chuyển màu giọng, Auto-Tune, Compressor & Reverb.',
      icon: Icons.record_voice_over_rounded,
      headerAction: TextButton.icon(
        onPressed: controller.isBusyProcessing
            ? null
            : controller.resetDspToVoiceProfile,
        icon: Icon(Icons.restore, size: 16, color: accent),
        label: Text(
          'Theo Hồ Sơ',
          style: TextStyle(fontSize: 12, color: accent),
        ),
      ),
      children: [
        _sectionHeader(
          title: '1. Chuyển Giọng & Âm Lượng Vocal',
          accent: accent,
          enabled: p.enableVoiceConversion,
          onToggle: (v) {
            controller.updateProMixerParams(
              p.copyWith(enableVoiceConversion: v),
            );
            controller.applyDspToCurrentTrack();
          },
        ),
        _sliderRow(
          label: 'Mức độ ép theo màu giọng đã lưu',
          valueText: '${(p.voiceConversionStrength * 100).round()}%',
          value: p.voiceConversionStrength,
          min: 0.0,
          max: 1.0,
          onChanged: (v) => controller.updateProMixerParams(
            p.copyWith(voiceConversionStrength: v),
          ),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
        _sliderRow(
          label: 'Âm lượng Giọng hát (Vocal Gain)',
          valueText:
              '${p.vocalGainDb >= 0 ? "+" : ""}${p.vocalGainDb.toStringAsFixed(1)} dB',
          value: p.vocalGainDb,
          min: -4.0,
          max: 8.0,
          onChanged: (v) =>
              controller.updateProMixerParams(p.copyWith(vocalGainDb: v)),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
        const Divider(height: 20),

        _sectionHeader(
          title: '2. Pitch Correction / Auto-Tune (Giọng Hát)',
          accent: accent,
          enabled: p.enablePitchCorrection,
          onToggle: (v) {
            controller.updateProMixerParams(
              p.copyWith(enablePitchCorrection: v),
            );
            controller.applyDspToCurrentTrack();
          },
        ),
        _compactSwitchRow(
          label: 'Khóa theo Tông Nhạc (Scale-Locked Auto-Tune)',
          subtitle: 'Kéo chuẩn vào 7 nốt của bài hát thay vì 12 nốt tự do',
          value: p.scaleLockedAutoTune,
          accent: accent,
          onChanged: (v) {
            controller.updateProMixerParams(
              p.copyWith(scaleLockedAutoTune: v),
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

        _sectionHeader(
          title: '3. 5-Band Parametric EQ (Giọng Vocal)',
          accent: accent,
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
          valueText:
              '${p.eqLowMid280HzDb >= 0 ? "+" : ""}${p.eqLowMid280HzDb.toStringAsFixed(1)} dB',
          value: p.eqLowMid280HzDb,
          min: -6.0,
          max: 6.0,
          onChanged: (v) =>
              controller.updateProMixerParams(p.copyWith(eqLowMid280HzDb: v)),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
        _sliderRow(
          label: '1.2kHz (Giảm giọng mũi / Nasal)',
          valueText:
              '${p.eqMid1200HzDb >= 0 ? "+" : ""}${p.eqMid1200HzDb.toStringAsFixed(1)} dB',
          value: p.eqMid1200HzDb,
          min: -6.0,
          max: 6.0,
          onChanged: (v) =>
              controller.updateProMixerParams(p.copyWith(eqMid1200HzDb: v)),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
        _sliderRow(
          label: '3.5kHz (Độ nổi bật giọng - Presence)',
          valueText:
              '${p.eqHighMid3500HzDb >= 0 ? "+" : ""}${p.eqHighMid3500HzDb.toStringAsFixed(1)} dB',
          value: p.eqHighMid3500HzDb,
          min: -6.0,
          max: 7.0,
          onChanged: (v) => controller.updateProMixerParams(
            p.copyWith(eqHighMid3500HzDb: v),
          ),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
        _sliderRow(
          label: '10kHz (Độ bay bổng - Air)',
          valueText:
              '${p.eqAir10kHzDb >= 0 ? "+" : ""}${p.eqAir10kHzDb.toStringAsFixed(1)} dB',
          value: p.eqAir10kHzDb,
          min: -6.0,
          max: 7.0,
          onChanged: (v) =>
              controller.updateProMixerParams(p.copyWith(eqAir10kHzDb: v)),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
        const Divider(height: 20),

        _sectionHeader(
          title: '4. Compressor, De-Esser & Không Gian Vocal',
          accent: accent,
          enabled: p.enableCompressor && p.enableReverbDelay,
          onToggle: (v) {
            controller.updateProMixerParams(
              p.copyWith(
                enableCompressor: v,
                enableNoiseGateAndDeEsser: v,
                enableReverbDelay: v,
              ),
            );
            controller.applyDspToCurrentTrack();
          },
        ),
        _sliderRow(
          label: 'Tỷ lệ nén làm đều hơi (Compressor Ratio)',
          valueText: '${p.compRatio.toStringAsFixed(1)} : 1',
          value: p.compRatio,
          min: 1.5,
          max: 6.5,
          onChanged: (v) =>
              controller.updateProMixerParams(p.copyWith(compRatio: v)),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
        _sliderRow(
          label: 'Giảm âm xì chói s/x/ch (De-Esser)',
          valueText: '${(p.deEsserAmount * 100).round()}%',
          value: p.deEsserAmount,
          min: 0.0,
          max: 0.9,
          onChanged: (v) =>
              controller.updateProMixerParams(p.copyWith(deEsserAmount: v)),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
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
    );
  }

  // ===========================================================================
  // TAB 3: NHẠC NỀN (Màu Amber - Tone Beat ±6st, Stereo Width & 5-Band EQ Beat)
  // ===========================================================================
  Widget _buildMusicTab(BuildContext context, Color accent) {
    final p = controller.dspParams;
    final detectedKey = controller.lastReport?.detectedMusicKey;
    final int semitoneInt = p.musicTransposeSemitones.round();

    return _themedTabContainer(
      key: const ValueKey('tab_music'),
      accent: accent,
      title: 'Chỉnh Chuyên Sâu Nhạc Nền (Beat)',
      subtitle:
          'Nâng/hạ Tone nhạc nền khớp quãng hát, mở rộng Stereo và 5-Band EQ riêng cho Beat.',
      icon: Icons.library_music_rounded,
      headerAction: TextButton.icon(
        onPressed: controller.isBusyProcessing
            ? null
            : controller.resetMusicStemSettings,
        icon: Icon(Icons.restore, size: 16, color: accent),
        label: Text(
          'Reset Beat',
          style: TextStyle(fontSize: 12, color: accent),
        ),
      ),
      children: [
        // 1. Chỉnh Tone Nhạc nền (-6 .. +6 bán cung)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.bgDark.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: semitoneInt != 0
                  ? accent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.music_note_rounded, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      detectedKey != null
                          ? 'Tông gốc Beat: ${detectedKey.labelVi}'
                          : 'Chỉnh Tone Nhạc Nền (Key Transpose)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _sliderRow(
                label: 'Nâng / Hạ Tone Nhạc (Transpose)',
                valueText:
                    '${p.musicTransposeSemitones > 0 ? "+" : ""}${p.musicTransposeSemitones.round()} bán cung',
                value: p.musicTransposeSemitones,
                min: -6.0,
                max: 6.0,
                onChanged: (v) => controller.updateProMixerParams(
                  p.copyWith(musicTransposeSemitones: v.roundToDouble()),
                ),
                onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [-2, -1, 0, 1, 2].map((step) {
                  final bool selected = semitoneInt == step;
                  return ChoiceChip(
                    label: Text(
                      step == 0
                          ? '0 (Gốc)'
                          : '${step > 0 ? "+" : ""}$step Tone',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.black : AppTheme.textPrimary,
                      ),
                    ),
                    selected: selected,
                    selectedColor: accent,
                    backgroundColor: AppTheme.cardElevated,
                    onSelected: controller.isBusyProcessing
                        ? null
                        : (_) {
                            controller.updateProMixerParams(
                              p.copyWith(
                                musicTransposeSemitones: step.toDouble(),
                              ),
                            );
                            controller.applyDspToCurrentTrack();
                          },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. Âm lượng & Stereo Width riêng của Nhạc nền
        _sliderRow(
          label: 'Âm lượng Nhạc nền (Music Gain)',
          valueText:
              '${p.musicGainDb >= 0 ? "+" : ""}${p.musicGainDb.toStringAsFixed(1)} dB',
          value: p.musicGainDb,
          min: -10.0,
          max: 5.0,
          onChanged: (v) =>
              controller.updateProMixerParams(p.copyWith(musicGainDb: v)),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
        _sliderRow(
          label: 'Độ rộng Không gian Beat (Music Stereo Width)',
          valueText: '${(p.musicStereoWidth * 100).round()}%',
          value: p.musicStereoWidth,
          min: 0.5,
          max: 1.6,
          onChanged: (v) =>
              controller.updateProMixerParams(p.copyWith(musicStereoWidth: v)),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
        const Divider(height: 20),

        // 3. 5-Band EQ chuyên sâu cho Nhạc nền
        _sectionHeader(
          title: '5-Band Parametric EQ (Riêng cho Nhạc Nền)',
          accent: accent,
          enabled: p.enableMusicMasteringEq,
          onToggle: (v) {
            controller.updateProMixerParams(
              p.copyWith(enableMusicMasteringEq: v),
            );
            controller.applyDspToCurrentTrack();
          },
        ),
        _sliderRow(
          label: '100Hz (Lực Trống & Bass nền)',
          valueText:
              '${p.musicEqSub100HzDb >= 0 ? "+" : ""}${p.musicEqSub100HzDb.toStringAsFixed(1)} dB',
          value: p.musicEqSub100HzDb,
          min: -6.0,
          max: 6.0,
          onChanged: (v) =>
              controller.updateProMixerParams(p.copyWith(musicEqSub100HzDb: v)),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
        _sliderRow(
          label: '280Hz (Cắt ù / Bùn phòng từ loa)',
          valueText:
              '${p.musicEqLowMid280HzDb >= 0 ? "+" : ""}${p.musicEqLowMid280HzDb.toStringAsFixed(1)} dB',
          value: p.musicEqLowMid280HzDb,
          min: -6.0,
          max: 6.0,
          onChanged: (v) => controller.updateProMixerParams(
            p.copyWith(musicEqLowMid280HzDb: v),
          ),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
        _sliderRow(
          label: '1.2kHz (Trung âm nhạc cụ)',
          valueText:
              '${p.musicEqMid1200HzDb >= 0 ? "+" : ""}${p.musicEqMid1200HzDb.toStringAsFixed(1)} dB',
          value: p.musicEqMid1200HzDb,
          min: -6.0,
          max: 6.0,
          onChanged: (v) => controller.updateProMixerParams(
            p.copyWith(musicEqMid1200HzDb: v),
          ),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
        _sliderRow(
          label: '3.5kHz (Độ sắc đàn / Nhường chỗ Vocal)',
          valueText:
              '${p.musicEqHighMid3500HzDb >= 0 ? "+" : ""}${p.musicEqHighMid3500HzDb.toStringAsFixed(1)} dB',
          value: p.musicEqHighMid3500HzDb,
          min: -6.0,
          max: 6.0,
          onChanged: (v) => controller.updateProMixerParams(
            p.copyWith(musicEqHighMid3500HzDb: v),
          ),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
        _sliderRow(
          label: '10kHz (Độ sáng & Chi tiết Hi-Hat/Air)',
          valueText:
              '${p.musicEqAir10kHzDb >= 0 ? "+" : ""}${p.musicEqAir10kHzDb.toStringAsFixed(1)} dB',
          value: p.musicEqAir10kHzDb,
          min: -6.0,
          max: 6.0,
          onChanged: (v) =>
              controller.updateProMixerParams(p.copyWith(musicEqAir10kHzDb: v)),
          onChangeEnd: (_) => controller.applyDspToCurrentTrack(),
        ),
      ],
    );
  }

  Widget _themedTabContainer({
    required Key key,
    required Color accent,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
    Widget? headerAction,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.11),
            AppTheme.cardDark,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              ?headerAction,
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _goalButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required Color activeColor,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.16)
              : AppTheme.bgDark.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? activeColor : Colors.white.withValues(alpha: 0.08),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? activeColor : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.2,
                      fontWeight: FontWeight.w700,
                      color: selected ? activeColor : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9.8,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required String title,
    required Color accent,
    required bool enabled,
    required ValueChanged<bool> onToggle,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ),
        Switch(
          value: enabled,
          activeThumbColor: accent,
          onChanged: onToggle,
        ),
      ],
    );
  }

  Widget _compactSwitchRow({
    required String label,
    required String subtitle,
    required bool value,
    required Color accent,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: accent,
            onChanged: onChanged,
          ),
        ],
      ),
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
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.2,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              valueText,
              style: const TextStyle(
                fontSize: 12.2,
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
}
