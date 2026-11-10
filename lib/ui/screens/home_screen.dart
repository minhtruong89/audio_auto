import 'package:flutter/material.dart';
import '../../state/app_controller.dart';
import '../theme/app_theme.dart';
import 'studio_screen.dart';
import 'wizard_screen.dart';

/// Màn hình chính kết nối 2 phân hệ:
/// - Tab 1: Phân tích Đặc trưng Giọng (4 bước thu âm + Biểu đồ Radar)
/// - Tab 2: Phòng Thu Karaoke AI+DSP (Tích hợp cả 3 chế độ điều khiển để test)
class HomeScreen extends StatefulWidget {
  final AppController controller;

  const HomeScreen({super.key, required this.controller});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final profile = widget.controller.voiceProfile;
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primaryNeon, AppTheme.accentCyan],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'Sonca Autotune',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentCyan.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.accentCyan.withValues(alpha: 0.55),
                              ),
                            ),
                            child: const Text(
                              'v1.0.0',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.accentCyan,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'On-Device AI + DSP • ${profile.vocalType.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: IndexedStack(
            index: _selectedIndex,
            children: [
              VoiceProfilingWizardScreen(controller: widget.controller),
              KaraokeStudioScreen(controller: widget.controller),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            backgroundColor: AppTheme.cardDark,
            indicatorColor: AppTheme.primaryNeon.withValues(alpha: 0.28),
            selectedIndex: _selectedIndex,
            onDestinationSelected: (idx) {
              if (idx == 1 && !widget.controller.hasCustomProfile) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Bạn chưa có hồ sơ giọng nào được lưu! Hãy bấm "Phân tích" và lưu tên giọng trước khi sang Làm Đẹp Karaoke nhé.',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              setState(() => _selectedIndex = idx);
              if (idx == 1) {
                widget.controller.ensureStudioTrackProcessed();
              }
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.record_voice_over_outlined),
                selectedIcon: Icon(
                  Icons.record_voice_over_rounded,
                  color: AppTheme.accentCyan,
                ),
                label: '1. Đo Đặc Trưng Giọng (4 Bước)',
              ),
              NavigationDestination(
                enabled: widget.controller.hasCustomProfile,
                icon: Icon(
                  Icons.tune_outlined,
                  color: widget.controller.hasCustomProfile
                      ? null
                      : Colors.white.withValues(alpha: 0.28),
                ),
                selectedIcon: const Icon(
                  Icons.tune_rounded,
                  color: AppTheme.accentCyan,
                ),
                label: widget.controller.hasCustomProfile
                    ? '2. Làm Đẹp Karaoke'
                    : '2. Làm Đẹp Karaoke (Chưa lưu giọng)',
              ),
            ],
          ),
        );
      },
    );
  }
}
