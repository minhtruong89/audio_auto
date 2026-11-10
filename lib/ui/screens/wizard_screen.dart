import 'package:flutter/material.dart';
import '../../models/voice_profile.dart';
import '../../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/radar_profile_chart.dart';

class _WizardStepInfo {
  final int index;
  final String title;
  final String subtitle;
  final String promptText;
  final String targetFeature;

  const _WizardStepInfo({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.promptText,
    required this.targetFeature,
  });
}

/// Màn hình Chuỗi 4 Bước Thu & Phân Tích Đặc Trưng Giọng Nói của người dùng
class VoiceProfilingWizardScreen extends StatefulWidget {
  final AppController controller;

  const VoiceProfilingWizardScreen({
    super.key,
    required this.controller,
  });

  @override
  State<VoiceProfilingWizardScreen> createState() =>
      _VoiceProfilingWizardScreenState();
}

class _VoiceProfilingWizardScreenState
    extends State<VoiceProfilingWizardScreen> {
  int _activeStep = 0;

  static const List<_WizardStepInfo> _steps = [
    _WizardStepInfo(
      index: 0,
      title: 'Bước 1: Đo Tạp Âm Phòng & Giọng Nói Tự Nhiên',
      subtitle: 'Giữ im lặng 1 giây đầu rồi nói tự nhiên câu gợi ý (không bắt buộc đúng từng chữ)',
      promptText: '"Xin chào, bắt đầu phân tích giọng nói"',
      targetFeature: 'Trích xuất: Noise Floor (dB), F0 trung bình & Trọng tâm phổ (Spectral Centroid)',
    ),
    _WizardStepInfo(
      index: 1,
      title: 'Bước 2: Đo Quãng Giọng (Thang Âm Đồ ↗ Đố)',
      subtitle:
          'Hát nâng cao tông dần từng bậc (không đọc ngang giọng) và ngân dài chữ "Đố" cuối ở nốt cao nhất bạn lên tới',
      promptText: '"Đồ ↗ Rê ↗ Mi ↗ Pha ↗ Son ↗ La ↗ Si ↗ Đố..."',
      targetFeature:
          'Trích xuất: Quãng giọng (Bass/Baritone/Tenor/Alto/Soprano), Độ mở bán cung & Vùng giọng đẹp nhất',
    ),
    _WizardStepInfo(
      index: 2,
      title: 'Bước 3: Độ Ổn Định Hơi & Cao Độ (Sustained Note)',
      subtitle: 'Ngân dài 1 nốt nhạc đều hơi trong khoảng 4 - 5 giây',
      promptText: '"Laaaaaaaa..." (Giữ thẳng cao độ và đều hơi)',
      targetFeature: 'Trích xuất: Độ lệch cao độ (Pitch Jitter %) để tính lực kéo Auto-Tune & Compressor',
    ),
    _WizardStepInfo(
      index: 3,
      title: 'Bước 4: Đo Âm Xì (Sibilance) & Đường Cong Bù 5-Band EQ',
      subtitle: 'Hát hoặc đọc rõ câu có nhiều phụ âm s, x, ch, t để đo tần số chói mic',
      promptText:
          '"Mưa vẫn mưa bay trên tầng tháp cổ..."',
      targetFeature: 'Trích xuất: Đỉnh Sibilance (5kHz-8kHz) cho De-esser & Đường cong bù 5-Band EQ',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final step = _steps[_activeStep];
    final metrics = ctrl.wizardSteps[_activeStep];
    final completedCount = ctrl.wizardSteps.where((e) => e != null).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // Thẻ Hồ sơ giọng hiện tại + Biểu đồ Radar 5 cạnh
        _buildProfileSummaryCard(ctrl, completedCount),
        const SizedBox(height: 16),

        // Thanh tiến trình chọn 4 bước
        Row(
          children: List.generate(_steps.length, (idx) {
            final bool isCurrent = idx == _activeStep;
            final bool isDone = ctrl.wizardSteps[idx] != null;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _activeStep = idx),
                child: Container(
                  margin: EdgeInsets.only(right: idx < 3 ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? AppTheme.primaryNeon
                        : (isDone
                            ? AppTheme.accentEmerald.withValues(alpha: 0.2)
                            : AppTheme.cardDark),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCurrent
                          ? AppTheme.accentCyan
                          : (isDone
                              ? AppTheme.accentEmerald
                              : Colors.white.withValues(alpha: 0.1)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isDone ? Icons.check_circle : Icons.mic_none,
                        size: 15,
                        color: isDone ? AppTheme.accentEmerald : Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Bước ${idx + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 14),

        // Thẻ thực hành Bước hiện tại
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.cardDark,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.accentCyan,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                step.subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 14),

              // Hộp câu mẫu để người dùng đọc/hát
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.bgDark,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.primaryNeon.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  children: [
                    const Text(
                      'MẪU THU ÂM:',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accentAmber,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      step.promptText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                        color: Colors.white,
                        height: 1.35,
                      ),
                    ),
                    if (_activeStep == 1) ...[
                      const SizedBox(height: 12),
                      _buildDoReMiStaircaseVisual(),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          side: BorderSide(
                            color: AppTheme.accentAmber.withValues(alpha: 0.6),
                          ),
                        ),
                        onPressed: ctrl.isRecordingWizard
                            ? null
                            : ctrl.playDoReMiGuideTone,
                        icon: const Icon(
                          Icons.volume_up_rounded,
                          size: 16,
                          color: AppTheme.accentAmber,
                        ),
                        label: const Text(
                          'Nghe Giai Điệu Mẫu (Đồ ↗ Đố)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentAmber,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                step.targetFeature,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),

              // Thanh đo mức âm lượng Mic trực tiếp khi đang thu
              if (ctrl.isRecordingWizard) ...[
                _buildLiveMicMeter(ctrl.liveMicAmplitudeDb),
                const SizedBox(height: 14),
              ],

              // Hàng nút Thu âm bằng Mic hoặc Giả lập mẫu thử nhanh
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: ctrl.isRecordingWizard
                            ? AppTheme.accentRose
                            : AppTheme.primaryNeon,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: ctrl.isBusyProcessing
                          ? null
                          : () async {
                              if (ctrl.isRecordingWizard) {
                                await ctrl.stopWizardStepRecording(_activeStep);
                              } else {
                                await ctrl.startWizardStepRecording(_activeStep);
                              }
                            },
                      icon: Icon(
                        ctrl.isRecordingWizard
                            ? Icons.stop_circle_outlined
                            : Icons.mic_rounded,
                      ),
                      label: Text(
                        ctrl.isRecordingWizard
                            ? 'Dừng & Phân Tích Ngay'
                            : 'Thu Âm Bước ${_activeStep + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(
                          color: AppTheme.accentCyan.withValues(alpha: 0.5),
                        ),
                      ),
                      onPressed: (ctrl.isBusyProcessing || ctrl.isRecordingWizard)
                          ? null
                          : () => ctrl.simulateWizardStepAnalysis(_activeStep),
                      icon: const Icon(Icons.science_outlined, size: 18),
                      label: const Text(
                        'Giả lập mẫu',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ),
                ],
              ),

              // Hiển thị kết quả đo & Kiểm định chất lượng (QC) của bước này nếu đã đo xong
              if (metrics != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (metrics.isQualityValid
                            ? AppTheme.accentEmerald
                            : AppTheme.accentAmber)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (metrics.isQualityValid
                              ? AppTheme.accentEmerald
                              : AppTheme.accentAmber)
                          .withValues(alpha: 0.45),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            metrics.isQualityValid
                                ? Icons.verified_rounded
                                : Icons.warning_amber_rounded,
                            color: metrics.isQualityValid
                                ? AppTheme.accentEmerald
                                : AppTheme.accentAmber,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              metrics.isQualityValid
                                  ? 'Bản thu đạt chuẩn (Bước ${_activeStep + 1})'
                                  : 'Cần lưu ý chất lượng thu (Bước ${_activeStep + 1})',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: metrics.isQualityValid
                                    ? AppTheme.accentEmerald
                                    : AppTheme.accentAmber,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        metrics.qualityFeedback,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          _metricTag(
                            'SNR (Độ rõ/Ồn)',
                            '+${metrics.snrDb.toStringAsFixed(1)} dB',
                          ),
                          _metricTag(
                            'F0 Trung bình',
                            '${metrics.meanPitchHz.toStringAsFixed(1)} Hz',
                          ),
                          _metricTag(
                            'Dải Pitch',
                            '${metrics.minPitchHz.round()} - ${metrics.maxPitchHz.round()} Hz',
                          ),
                          _metricTag(
                            'Độ lệch Pitch (Jitter)',
                            '${metrics.pitchJitterPercent.toStringAsFixed(2)}%',
                          ),
                          _metricTag(
                            'Độ sáng phổ',
                            '${metrics.spectralCentroidHz.round()} Hz',
                          ),
                          _metricTag(
                            'Đỉnh âm xì',
                            '${(metrics.sibilancePeakHz / 1000).toStringAsFixed(1)} kHz',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),
              // Nút chuyển bước tiếp theo hoặc Hoàn tất Hồ sơ giọng
              Row(
                children: [
                  if (_activeStep > 0) ...[
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () => setState(() => _activeStep--),
                      icon: const Icon(Icons.arrow_back_ios_new, size: 14),
                      label: const Text('Bước trước'),
                    ),
                    const SizedBox(width: 8),
                  ] else
                    const Spacer(),
                  if (_activeStep < 3) ...[
                    if (_activeStep > 0) const Spacer(),
                    FilledButton.tonalIcon(
                      onPressed: () => setState(() => _activeStep++),
                      icon: const Icon(Icons.arrow_forward_ios, size: 14),
                      label: Text('Sang Bước ${_activeStep + 2}'),
                    ),
                  ] else
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accentEmerald,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        onPressed: ctrl.isBusyProcessing
                            ? null
                            : () => _handleAnalyzeAndSaveDialog(ctrl),
                        icon: const Icon(Icons.analytics_outlined, size: 18),
                        label: const Text(
                          'Phân tích',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleAnalyzeAndSaveDialog(AppController ctrl) async {
    final previewProfile = await ctrl.analyze4StepsForPreview();
    if (!mounted) return;

    UserVoiceProfile editedProfile = previewProfile;
    final nameController = TextEditingController(text: previewProfile.name);
    final savedName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final bool isMale = editedProfile.isMaleVoice;
            return AlertDialog(
              backgroundColor: AppTheme.cardDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: AppTheme.accentCyan.withValues(alpha: 0.4),
                ),
              ),
              title: const Row(
                children: [
                  Icon(Icons.save_alt_rounded, color: AppTheme.accentCyan, size: 22),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Lưu Hồ Sơ Giọng Của Bạn',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Phân loại: ${editedProfile.vocalType.title}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.accentEmerald,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tần số nói (F0): ${editedProfile.speakingF0MeanHz.round()}Hz • Quãng đo: ${editedProfile.minPitchHz.round()}–${editedProfile.maxPitchHz.round()}Hz',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text(
                        'Giới tính giọng:',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Nam', style: TextStyle(fontSize: 12)),
                        selected: isMale,
                        selectedColor: AppTheme.accentCyan.withValues(alpha: 0.25),
                        onSelected: (_) {
                          setDialogState(() {
                            final double fixedF0 =
                                editedProfile.speakingF0MeanHz > 175.0
                                    ? (editedProfile.speakingF0MeanHz / 2.0)
                                        .clamp(105.0, 155.0)
                                    : editedProfile.speakingF0MeanHz;
                            editedProfile = editedProfile.copyWith(
                              speakingF0MeanHz: fixedF0,
                              vocalType: fixedF0 < 115.0
                                  ? VocalRangeType.bass
                                  : VocalRangeType.baritone,
                            );
                            if (nameController.text.contains('(Nữ)')) {
                              nameController.text =
                                  nameController.text.replaceAll('(Nữ)', '(Nam)');
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Nữ', style: TextStyle(fontSize: 12)),
                        selected: !isMale,
                        selectedColor: AppTheme.primaryNeon.withValues(alpha: 0.28),
                        onSelected: (_) {
                          setDialogState(() {
                            final double fixedF0 =
                                editedProfile.speakingF0MeanHz < 175.0
                                    ? (editedProfile.speakingF0MeanHz * 1.65)
                                        .clamp(195.0, 260.0)
                                    : editedProfile.speakingF0MeanHz;
                            editedProfile = editedProfile.copyWith(
                              speakingF0MeanHz: fixedF0,
                              vocalType: VocalRangeType.mezzoSoprano,
                            );
                            if (nameController.text.contains('(Nam)')) {
                              nameController.text =
                                  nameController.text.replaceAll('(Nam)', '(Nữ)');
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Nhập tên gợi nhớ cho giọng này (để chọn lại nhanh những lần mở app sau):',
                    style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'VD: Giọng Nam Phòng Khách, Giọng Hát Bolero...',
                      filled: true,
                      fillColor: AppTheme.bgDark,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Hủy'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accentEmerald,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(nameController.text),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text(
                    'Lưu Giọng',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (savedName != null && mounted) {
      await ctrl.saveAnalyzedVoiceProfile(editedProfile, savedName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã lưu "${ctrl.voiceProfile.name}"! Bạn có thể bấm sang tab "2. Làm Đẹp Karaoke" ở dưới.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildProfileSummaryCard(AppController ctrl, int completedCount) {
    final profile = ctrl.voiceProfile;
    final savedList = ctrl.savedProfiles;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hộp chọn nhanh trong Danh sách các giọng đã lưu (mặc định chọn giọng mới nhất)
          if (savedList.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.bgDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.accentCyan.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.folder_shared_rounded,
                    color: AppTheme.accentCyan,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Giọng đã lưu:',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: savedList.any((e) => e.id == profile.id)
                            ? profile.id
                            : savedList.first.id,
                        isExpanded: true,
                        dropdownColor: AppTheme.cardElevated,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        items: savedList.map((item) {
                          return DropdownMenuItem<String>(
                            value: item.id,
                            child: Text(
                              item.displayLabelWithType,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (selectedId) {
                          if (selectedId == null) return;
                          final found = savedList.firstWhere(
                            (e) => e.id == selectedId,
                            orElse: () => savedList.first,
                          );
                          ctrl.selectSavedVoiceProfile(found);
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Xóa hồ sơ giọng đang chọn',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => ctrl.deleteSavedVoiceProfile(profile.id),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: AppTheme.accentRose,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: (ctrl.hasCustomProfile
                                      ? AppTheme.accentEmerald
                                      : AppTheme.accentAmber)
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              ctrl.hasCustomProfile
                                  ? 'ĐANG CHỌN: ${profile.name.toUpperCase()}'
                                  : 'CHƯA CÓ GIỌNG LƯU ($completedCount/4 BƯỚC)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: ctrl.hasCustomProfile
                                    ? AppTheme.accentEmerald
                                    : AppTheme.accentAmber,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      profile.vocalType.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Dải tần số: ${profile.minPitchHz.round()}Hz – ${profile.maxPitchHz.round()}Hz • Vùng giọng đẹp: ~${profile.comfortZoneHz.round()}Hz',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (completedCount > 0)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  onPressed: ctrl.isBusyProcessing
                      ? null
                      : () {
                          ctrl.resetWizardSteps();
                          setState(() => _activeStep = 0);
                        },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text(
                    'Đo lại',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Center(child: RadarProfileChart(profile: profile, size: 215)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.cardElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.psychology_alt_rounded,
                  color: AppTheme.accentCyan,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    profile.aiSummary,
                    style: const TextStyle(
                      fontSize: 12.2,
                      color: AppTheme.textPrimary,
                      height: 1.38,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveMicMeter(double db) {
    final double norm = ((db + 60.0) / 60.0).clamp(0.05, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Mức tín hiệu Microphone trực tiếp:',
              style: TextStyle(fontSize: 12, color: AppTheme.accentAmber),
            ),
            Text(
              '${db.toStringAsFixed(1)} dBFS',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: norm,
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppTheme.accentEmerald,
            ),
          ),
        ),
      ],
    );
  }

  Widget _metricTag(String label, String val) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          TextSpan(
            text: val,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Minh họa trực quan 8 bậc thang cao độ Đồ -> Đố đi lên để người dùng hát nâng tông theo
  Widget _buildDoReMiStaircaseVisual() {
    const notes = ['Đồ', 'Rê', 'Mi', 'Pha', 'Son', 'La', 'Si', 'Đố'];
    return SizedBox(
      height: 68,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(notes.length, (i) {
          final double barHeight = 10.0 + i * 4.5;
          return Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  notes[i],
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: i >= 5 ? AppTheme.accentCyan : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: barHeight,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        AppTheme.primaryNeon.withValues(alpha: 0.65),
                        AppTheme.accentCyan,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
