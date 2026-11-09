import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dsp_parameters.dart';
import '../models/studio_mode.dart';
import '../models/voice_profile.dart';
import '../services/audio_io_service.dart';
import '../services/dsp_engine_service.dart';
import '../services/voice_analyzer_service.dart';

/// Quản lý trạng thái trung tâm của ứng dụng:
/// - Hồ sơ giọng nói (4 bước đo + lưu trữ bền vững)
/// - Luồng thu âm Mic / Chọn file / Tạo file Karaoke Demo
/// - Chạy Pipeline Tách giọng & DSP theo 3 chế độ (1-Touch, Smart Presets, Pro Mixer)
/// - Phát nhạc đối chiếu tức thì (Before / After A/B Testing)
class AppController extends ChangeNotifier {
  final AudioIoService _audioIo = AudioIoService();
  final VoiceAnalyzerService _analyzer = VoiceAnalyzerService();
  final DspEngineService _dspEngine = DspEngineService();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  UserVoiceProfile _voiceProfile = UserVoiceProfile.defaultDemo();
  bool _hasCustomProfile = false;

  // Trạng thái 4 bước đo giọng (Wizard)
  final List<StepAnalysisMetrics?> _wizardSteps = [null, null, null, null];
  bool _isRecordingWizard = false;
  double _liveMicAmplitudeDb = -60.0;
  Timer? _ampTimer;

  // Trạng thái Karaoke Studio
  StudioControlMode _controlMode = StudioControlMode.oneTouchAuto;
  KaraokePresetStyle _selectedPreset = KaraokePresetStyle.aiProfileMatched;
  double _presetIntensity = 1.0;
  double _vocalMusicBalance = 0.0; // -1.0 -> +1.0
  late DspParameters _dspParams;

  String _currentTrackName = 'Bản thu Karaoke Mẫu (Giọng + Loa ngoài)';
  String? _originalFilePath;
  String? _enhancedFilePath;
  PcmAudioData? _originalPcm;
  PcmAudioData? _enhancedPcm;
  DspProcessingReport? _lastReport;

  List<double> _originalWaveform = List<double>.filled(64, 0.2);
  List<double> _enhancedWaveform = List<double>.filled(64, 0.35);

  bool _isBusyProcessing = false;
  bool _isRecordingKaraoke = false;
  String _statusMessage = 'Sẵn sàng xử lý âm thanh On-Device';

  // Trạng thái trình phát đối chiếu A/B (Before vs After)
  bool _isPlaying = false;
  bool _isListeningEnhanced = true; // true = Đã làm đẹp (After), false = Bản gốc (Before)
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = const Duration(seconds: 8);

  AppController() {
    _dspParams = DspParameters.fromVoiceProfile(_voiceProfile);
    _initPlayerListeners();
    _initializeApp();
  }

  // Getters
  UserVoiceProfile get voiceProfile => _voiceProfile;
  bool get hasCustomProfile => _hasCustomProfile;
  List<StepAnalysisMetrics?> get wizardSteps => List.unmodifiable(_wizardSteps);
  bool get isRecordingWizard => _isRecordingWizard;
  double get liveMicAmplitudeDb => _liveMicAmplitudeDb;

  StudioControlMode get controlMode => _controlMode;
  KaraokePresetStyle get selectedPreset => _selectedPreset;
  double get presetIntensity => _presetIntensity;
  double get vocalMusicBalance => _vocalMusicBalance;
  DspParameters get dspParams => _dspParams;

  String get currentTrackName => _currentTrackName;
  String? get originalFilePath => _originalFilePath;
  String? get enhancedFilePath => _enhancedFilePath;
  DspProcessingReport? get lastReport => _lastReport;
  List<double> get originalWaveform => _originalWaveform;
  List<double> get enhancedWaveform => _enhancedWaveform;

  bool get isBusyProcessing => _isBusyProcessing;
  bool get isRecordingKaraoke => _isRecordingKaraoke;
  String get statusMessage => _statusMessage;

  bool get isPlaying => _isPlaying;
  bool get isListeningEnhanced => _isListeningEnhanced;
  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;

  void _initPlayerListeners() {
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      notifyListeners();
    });
    _player.onPositionChanged.listen((pos) {
      _currentPosition = pos;
      notifyListeners();
    });
    _player.onDurationChanged.listen((dur) {
      if (dur.inMilliseconds > 0) {
        _totalDuration = dur;
        notifyListeners();
      }
    });
  }

  Future<void> _initializeApp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString('user_voice_profile_v1');
      if (savedJson != null && savedJson.isNotEmpty) {
        _voiceProfile = UserVoiceProfile.fromJson(savedJson);
        _hasCustomProfile = true;
        _dspParams = DspParameters.fromVoiceProfile(_voiceProfile);
      }
    } catch (_) {}

    // Khởi tạo sẵn 1 bản thu Karaoke mẫu (lẫn giọng + nhạc loa ngoài) và xử lý sẵn để test ngay
    await loadBuiltInDemoKaraoke();
  }

  // ===========================================================================
  // PHÂN HỆ 1: WIZARD 4 BƯỚC THU & PHÂN TÍCH ĐẶC TRƯNG GIỌNG
  // ===========================================================================

  /// Bắt đầu thu âm từ Mic cho bước [stepIndex] (0 -> 3)
  Future<void> startWizardStepRecording(int stepIndex) async {
    if (_isRecordingWizard) return;
    try {
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        _statusMessage =
            'Không có quyền Microphone hoặc đang trên máy ảo. Bạn có thể bấm "Giả lập thu mẫu" để test!';
        notifyListeners();
        return;
      }

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/wizard_step_${stepIndex + 1}.wav';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );

      _isRecordingWizard = true;
      _statusMessage = 'Đang thu âm Bước ${stepIndex + 1}... Hãy phát âm vào Mic!';
      _startAmplitudeMonitor();
      notifyListeners();
    } catch (e) {
      _isRecordingWizard = false;
      _statusMessage =
          'Thiết bị chưa sẵn sàng thu Mic ($e). Đang dùng mẫu giọng giả lập cho Bước ${stepIndex + 1}.';
      notifyListeners();
      await simulateWizardStepAnalysis(stepIndex);
    }
  }

  /// Dừng thu âm bước [stepIndex] và phân tích đặc trưng giọng
  Future<void> stopWizardStepRecording(int stepIndex) async {
    if (!_isRecordingWizard) return;
    _stopAmplitudeMonitor();
    _isRecordingWizard = false;
    _isBusyProcessing = true;
    _statusMessage = 'Đang phân tích FFT, YIN Pitch & Formant cho Bước ${stepIndex + 1}...';
    notifyListeners();

    try {
      final path = await _recorder.stop();
      if (path != null && await File(path).exists()) {
        final pcm = await _audioIo.readWavFile(path);
        final metrics = _analyzer.analyzeAudioClip(pcm);
        _wizardSteps[stepIndex] = metrics;
        _statusMessage = 'Đã hoàn tất phân tích Bước ${stepIndex + 1}!';
      } else {
        await simulateWizardStepAnalysis(stepIndex);
      }
    } catch (_) {
      await simulateWizardStepAnalysis(stepIndex);
    } finally {
      _isBusyProcessing = false;
      notifyListeners();
    }
  }

  /// Giả lập thu & phân tích cho bước [stepIndex] (Rất tiện khi test nhanh trên máy ảo)
  Future<void> simulateWizardStepAnalysis(int stepIndex) async {
    _isBusyProcessing = true;
    _statusMessage = 'Đang chạy thuật toán phân tích mẫu giọng Bước ${stepIndex + 1}...';
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 350));
    final demoAudio = _audioIo.generateDemoKaraokeMix(durationSeconds: 3.5);
    final metrics = _analyzer.analyzeAudioClip(demoAudio);
    _wizardSteps[stepIndex] = metrics;

    _isBusyProcessing = false;
    _statusMessage = 'Đã trích xuất xong đặc trưng Bước ${stepIndex + 1}!';
    notifyListeners();
  }

  /// Hoàn tất cả 4 bước và tổng hợp thành Hồ sơ Giọng của người dùng
  Future<void> finalizeVoiceProfileFromWizard() async {
    _isBusyProcessing = true;
    _statusMessage = 'Đang tổng hợp Hồ sơ giọng & tính đường cong bù DSP...';
    notifyListeners();

    for (int i = 0; i < 4; i++) {
      if (_wizardSteps[i] == null) {
        final demo = _audioIo.generateDemoKaraokeMix(durationSeconds: 2.5);
        _wizardSteps[i] = _analyzer.analyzeAudioClip(demo);
      }
    }

    final validSteps = _wizardSteps.whereType<StepAnalysisMetrics>().toList();
    _voiceProfile = _analyzer.buildProfileFrom4Steps(validSteps);
    _hasCustomProfile = true;

    // Cập nhật ngay bộ tham số DSP tự động theo Hồ sơ giọng mới
    _dspParams = DspParameters.fromVoiceProfile(_voiceProfile);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_voice_profile_v1', _voiceProfile.toJson());
    } catch (_) {}

    // Tự động áp dụng hồ sơ giọng mới lên bản thu Karaoke hiện tại
    await applyDspToCurrentTrack();

    _isBusyProcessing = false;
    _statusMessage = 'Đã lưu Hồ sơ giọng cá nhân & cập nhật bộ DSP Karaoke!';
    notifyListeners();
  }

  // ===========================================================================
  // PHÂN HỆ 2: CHỌN FILE / THU ÂM KARAOKE & XỬ LÝ THEO 3 CHẾ ĐỘ
  // ===========================================================================

  /// Tải bản thu Karaoke Mẫu (gồm Giọng hát + Loa ngoài + Tạp âm) để test ngay lập tức
  Future<void> loadBuiltInDemoKaraoke() async {
    _isBusyProcessing = true;
    _statusMessage = 'Đang tạo bản thu Karaoke mẫu (Giọng + Nhạc loa ngoài)...';
    notifyListeners();

    try {
      await _player.stop();
      final pcm = _audioIo.generateDemoKaraokeMix(durationSeconds: 8.0);
      _originalPcm = pcm;
      _currentTrackName = 'Karaoke Mẫu (Giọng + Nhạc Loa Ngoài)';
      _originalWaveform = pcm.extractWaveformPeaks(64);
      _totalDuration = Duration(
        milliseconds: (pcm.durationSeconds * 1000).round(),
      );

      try {
        final dir = await getTemporaryDirectory();
        final origFile = await _audioIo.writeWavFile(
          pcm,
          '${dir.path}/karaoke_original.wav',
        );
        _originalFilePath = origFile.path;
      } catch (_) {}

      await applyDspToCurrentTrack();
    } finally {
      _isBusyProcessing = false;
      notifyListeners();
    }
  }

  /// Chọn một file âm thanh lưu sẵn trong máy (Giai đoạn 1)
  Future<void> pickAudioFileFromDevice() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'm4a', 'aac', 'flac'],
      );
      if (files.isEmpty || files.first.path == null) return;

      final pickedPath = files.first.path!;
      final pickedName = files.first.name;

      _isBusyProcessing = true;
      _statusMessage = 'Đang đọc file "$pickedName"...';
      notifyListeners();

      await _player.stop();
      final pcm = await _audioIo.readWavFile(pickedPath);
      _originalPcm = pcm;
      _currentTrackName = pickedName;
      _originalWaveform = pcm.extractWaveformPeaks(64);
      _totalDuration = Duration(
        milliseconds: (pcm.durationSeconds * 1000).round(),
      );

      final dir = await getTemporaryDirectory();
      final origFile = await _audioIo.writeWavFile(
        pcm,
        '${dir.path}/picked_original.wav',
      );
      _originalFilePath = origFile.path;

      await applyDspToCurrentTrack();
    } catch (e) {
      _statusMessage = 'Không thể đọc file ($e). Vui lòng ưu tiên chọn file WAV hoặc dùng mẫu thử.';
    } finally {
      _isBusyProcessing = false;
      notifyListeners();
    }
  }

  /// Thu âm trực tiếp lúc hát Karaoke (Mic thu cả giọng hát và tiếng nhạc từ loa ngoài)
  Future<void> toggleLiveKaraokeRecording() async {
    if (_isRecordingKaraoke) {
      _stopAmplitudeMonitor();
      _isRecordingKaraoke = false;
      _isBusyProcessing = true;
      _statusMessage = 'Đang lưu bản thu Karaoke và chạy AI Tách giọng + DSP...';
      notifyListeners();

      try {
        final path = await _recorder.stop();
        if (path != null && await File(path).exists()) {
          final pcm = await _audioIo.readWavFile(path);
          _originalPcm = pcm;
          _originalFilePath = path;
          _currentTrackName = 'Bản thu Mic Karaoke (${pcm.durationSeconds.toStringAsFixed(1)}s)';
          _originalWaveform = pcm.extractWaveformPeaks(64);
          _totalDuration = Duration(
            milliseconds: (pcm.durationSeconds * 1000).round(),
          );
          await applyDspToCurrentTrack();
        }
      } catch (e) {
        _statusMessage = 'Lỗi khi kết thúc thu âm: $e';
      } finally {
        _isBusyProcessing = false;
        notifyListeners();
      }
      return;
    }

    // Bắt đầu thu
    try {
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        _statusMessage = 'Chưa cấp quyền Microphone. Hãy dùng nút "Nạp Bản Thu Mẫu" để test!';
        notifyListeners();
        return;
      }
      await _player.stop();
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/karaoke_mic_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 2,
        ),
        path: path,
      );
      _isRecordingKaraoke = true;
      _statusMessage = 'Đang thu âm Mic (Hát cùng loa Karaoke)... Bấm lần nữa để dừng & làm đẹp!';
      _startAmplitudeMonitor();
      notifyListeners();
    } catch (e) {
      _isRecordingKaraoke = false;
      _statusMessage = 'Không thể mở Mic ($e).';
      notifyListeners();
    }
  }

  /// Chuyển đổi giữa 3 chế độ điều khiển (Option 1: 1-Touch, Option 2: Smart Presets, Option 3: Pro Mixer)
  Future<void> setStudioControlMode(StudioControlMode mode) async {
    if (_controlMode == mode) return;
    _controlMode = mode;

    if (mode == StudioControlMode.oneTouchAuto) {
      _dspParams = DspParameters.fromVoiceProfile(_voiceProfile);
      await applyDspToCurrentTrack();
    } else if (mode == StudioControlMode.smartPresets) {
      _dspParams = DspParameters.fromPreset(
        _selectedPreset,
        _voiceProfile,
        intensity: _presetIntensity,
        vocalMusicBalance: _vocalMusicBalance,
      );
      await applyDspToCurrentTrack();
    } else {
      notifyListeners();
    }
  }

  /// Thay đổi Preset hoặc Thanh kéo Cường độ ở Chế độ 2 (Smart Presets)
  Future<void> updatePresetConfiguration({
    KaraokePresetStyle? preset,
    double? intensity,
    double? vocalMusicBalance,
  }) async {
    if (preset != null) _selectedPreset = preset;
    if (intensity != null) _presetIntensity = intensity;
    if (vocalMusicBalance != null) _vocalMusicBalance = vocalMusicBalance;

    _dspParams = DspParameters.fromPreset(
      _selectedPreset,
      _voiceProfile,
      intensity: _presetIntensity,
      vocalMusicBalance: _vocalMusicBalance,
    );
    notifyListeners();
  }

  /// Thay đổi tham số chi tiết ở Chế độ 3 (Pro Mixer)
  void updateProMixerParams(DspParameters newParams) {
    _dspParams = newParams;
    notifyListeners();
  }

  /// Reset bộ tham số về đúng gợi ý AI từ Hồ sơ giọng của người dùng
  Future<void> resetDspToVoiceProfile() async {
    _dspParams = DspParameters.fromVoiceProfile(_voiceProfile);
    _selectedPreset = KaraokePresetStyle.aiProfileMatched;
    _presetIntensity = 1.0;
    _vocalMusicBalance = 0.0;
    await applyDspToCurrentTrack();
  }

  /// Thực thi Pipeline Tách Nhạc & Chuỗi 5 Hiệu ứng DSP lên bản thu hiện tại
  Future<void> applyDspToCurrentTrack() async {
    final input = _originalPcm;
    if (input == null) return;

    _isBusyProcessing = true;
    _statusMessage =
        'Đang tách Vocal khỏi nhạc loa ngoài & chạy chuỗi 5 hiệu ứng DSP...';
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 40));

    final report = _dspEngine.processKaraokeTrack(input, _dspParams);
    _enhancedPcm = report.outputAudio;
    _lastReport = report;
    _enhancedWaveform = _enhancedPcm!.extractWaveformPeaks(64);

    try {
      final dir = await getTemporaryDirectory();
      final outFile = await _audioIo.writeWavFile(
        _enhancedPcm!,
        '${dir.path}/karaoke_enhanced.wav',
      );
      _enhancedFilePath = outFile.path;
    } catch (_) {}

    _isBusyProcessing = false;
    _statusMessage =
        'Hoàn tất trong ${report.processingTimeMs}ms • Đã chỉnh ${report.pitchCorrectedFrames} khung Pitch • Peak ${report.peakOutputDb.toStringAsFixed(1)} dBFS';
    notifyListeners();

    // Nếu đang phát nhạc thì cập nhật nguồn phát sang bản mới
    if (_isPlaying && _isListeningEnhanced && _enhancedFilePath != null) {
      final pos = _currentPosition;
      await _player.play(DeviceFileSource(_enhancedFilePath!));
      await _player.seek(pos);
    }
  }

  // ===========================================================================
  // PHÂN HỆ 3: TRÌNH PHÁT ĐỐI CHIẾU A/B (NGHE GỐC vs ĐÃ LÀM ĐẸP)
  // ===========================================================================

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
      return;
    }

    final targetPath =
        _isListeningEnhanced ? _enhancedFilePath : _originalFilePath;
    if (targetPath == null || !await File(targetPath).exists()) {
      _statusMessage = 'Chưa có file âm thanh để phát.';
      notifyListeners();
      return;
    }

    await _player.play(DeviceFileSource(targetPath));
  }

  /// Chuyển đổi tức thì giữa Nghe Bản Gốc (Before) và Bản Đã Chỉnh Hay Hơn (After)
  Future<void> setAbComparisonMode(bool listenEnhanced) async {
    if (_isListeningEnhanced == listenEnhanced) return;
    _isListeningEnhanced = listenEnhanced;
    notifyListeners();

    if (_isPlaying) {
      final pos = _currentPosition;
      final targetPath =
          _isListeningEnhanced ? _enhancedFilePath : _originalFilePath;
      if (targetPath != null && await File(targetPath).exists()) {
        await _player.play(DeviceFileSource(targetPath));
        await _player.seek(pos);
      }
    }
  }

  Future<void> seekTo(Duration position) async {
    _currentPosition = position;
    notifyListeners();
    try {
      await _player.seek(position);
    } catch (_) {}
  }

  void _startAmplitudeMonitor() {
    _ampTimer?.cancel();
    _ampTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      try {
        final amp = await _recorder.getAmplitude();
        _liveMicAmplitudeDb = amp.current.clamp(-65.0, 0.0);
        notifyListeners();
      } catch (_) {}
    });
  }

  void _stopAmplitudeMonitor() {
    _ampTimer?.cancel();
    _ampTimer = null;
    _liveMicAmplitudeDb = -60.0;
  }

  @override
  void dispose() {
    _stopAmplitudeMonitor();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }
}
