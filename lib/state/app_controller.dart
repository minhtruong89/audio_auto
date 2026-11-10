import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dsp_parameters.dart';
import '../models/studio_mode.dart';
import '../models/voice_profile.dart';
import '../services/audio_io_service.dart';
import '../services/dsp_engine_service.dart';
import '../services/vocal_separator_service.dart';
import '../services/voice_analyzer_service.dart';

/// 4 chế độ nghe đối chiếu và kiểm tra chất lượng tách giọng (Stem Solo):
enum AudioListenMode {
  original, // Bản thu thô gốc (Before)
  enhancedMix, // Bản đã tách + chuyển giọng + DSP + trộn lại (After)
  vocalSolo, // Chỉ nghe riêng đường Giọng đã tách (Test độ sạch Vocal)
  musicSolo, // Chỉ nghe riêng đường Nhạc nền đã tách (Test độ sạch Beat)
}

/// Quản lý trạng thái trung tâm của ứng dụng:
/// - Hồ sơ giọng nói (4 bước đo + lưu trữ bền vững)
/// - Luồng thu âm Mic / Chọn file / Tạo file Karaoke Demo
/// - Chạy Pipeline Tách giọng & DSP theo 3 chế độ (1-Touch, Smart Presets, Pro Mixer)
/// - Phát nhạc đối chiếu tức thì (Before / After A/B Testing)
class AppController extends ChangeNotifier {
  final AudioIoService _audioIo = AudioIoService();
  final VoiceAnalyzerService _analyzer = VoiceAnalyzerService();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  UserVoiceProfile _voiceProfile = UserVoiceProfile.defaultDemo();
  final List<UserVoiceProfile> _savedProfiles = [];
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
  String? _vocalSoloFilePath;
  String? _musicSoloFilePath;
  String? _onnxModelFilePath;
  PcmAudioData? _originalPcm;
  PcmAudioData? _enhancedPcm;
  SeparatedStems? _cachedStems;
  int? _cachedStemsInputLength;
  double? _cachedStemsSignature;
  DspProcessingReport? _lastReport;

  List<double> _originalWaveform = List<double>.filled(64, 0.2);
  List<double> _enhancedWaveform = List<double>.filled(64, 0.35);
  List<double> _vocalSoloWaveform = List<double>.filled(64, 0.3);
  List<double> _musicSoloWaveform = List<double>.filled(64, 0.25);

  bool _isBusyProcessing = false;
  bool _isRecordingKaraoke = false;
  String _statusMessage = 'Sẵn sàng xử lý âm thanh On-Device';

  // Trạng thái trình phát đối chiếu A/B & Solo Stems
  bool _isPlaying = false;
  AudioListenMode _listenMode = AudioListenMode.enhancedMix;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = const Duration(seconds: 8);

  AppController() {
    _dspParams = DspParameters.fromVoiceProfile(_voiceProfile);
    _initPlayerListeners();
    _initializeApp();
  }

  // Getters
  UserVoiceProfile get voiceProfile => _voiceProfile;
  List<UserVoiceProfile> get savedProfiles => List.unmodifiable(_savedProfiles);
  bool get hasCustomProfile => _savedProfiles.isNotEmpty || _hasCustomProfile;
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
  String? get vocalSoloFilePath => _vocalSoloFilePath;
  String? get musicSoloFilePath => _musicSoloFilePath;
  DspProcessingReport? get lastReport => _lastReport;
  List<double> get originalWaveform => _originalWaveform;
  List<double> get enhancedWaveform => _enhancedWaveform;
  List<double> get vocalSoloWaveform => _vocalSoloWaveform;
  List<double> get musicSoloWaveform => _musicSoloWaveform;

  bool get isBusyProcessing => _isBusyProcessing;
  bool get isRecordingKaraoke => _isRecordingKaraoke;
  String get statusMessage => _statusMessage;

  bool get isPlaying => _isPlaying;
  AudioListenMode get listenMode => _listenMode;
  bool get isListeningEnhanced => _listenMode != AudioListenMode.original;
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
      final listJson = prefs.getString('saved_voice_profiles_list_v1');
      if (listJson != null && listJson.isNotEmpty) {
        final decoded = jsonDecode(listJson) as List<dynamic>;
        _savedProfiles
          ..clear()
          ..addAll(
            decoded.map(
              (item) =>
                  UserVoiceProfile.fromMap(item as Map<String, dynamic>),
            ),
          );
      } else {
        // Hỗ trợ nâng cấp từ bản lưu đơn cũ nếu có
        final savedJson = prefs.getString('user_voice_profile_v1');
        if (savedJson != null && savedJson.isNotEmpty) {
          final legacy = UserVoiceProfile.fromJson(savedJson);
          _savedProfiles.add(legacy);
        }
      }

      if (_savedProfiles.isNotEmpty) {
        // Sắp xếp giọng hoàn tất gần nhất lên đầu và mặc định chọn giọng đó
        _savedProfiles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _voiceProfile = _savedProfiles.first;
        _hasCustomProfile = true;
        _dspParams = DspParameters.fromVoiceProfile(_voiceProfile);
      }
    } catch (_) {}

    // Khởi tạo sẵn 1 bản thu Karaoke mẫu ở dạng nhẹ (Chưa chạy ONNX nặng ngay lúc mở app để tránh nghẽn máy)
    // Khi người dùng bấm sang Tab 2 (Làm Đẹp Karaoke), hệ thống mới giải nén model và chạy trong Background Isolate
    await loadBuiltInDemoKaraoke(processImmediately: false);
  }

  /// Được gọi khi người dùng chuyển sang Tab 2 (Làm Đẹp Karaoke) để xử lý nếu bản mẫu chưa được chạy DSP
  Future<void> ensureStudioTrackProcessed() async {
    if (_originalPcm != null && _enhancedPcm == null && !_isBusyProcessing) {
      await applyDspToCurrentTrack();
    }
  }

  /// Giải nén file model `assets/models/UVR_MDXNET_9482.onnx` ra bộ nhớ thiết bị để chạy trên Background Isolate
  Future<void> _ensureAiOnnxModelLoaded() async {
    if (_onnxModelFilePath != null && await File(_onnxModelFilePath!).exists()) {
      return;
    }
    try {
      final dir = await getApplicationSupportDirectory();
      final modelFile = File('${dir.path}/UVR_MDXNET_9482.onnx');
      if (!await modelFile.exists() || await modelFile.length() < 1000000) {
        _statusMessage =
            'Đang khởi tạo mô hình AI tách giọng UVR-MDX-NET ONNX lần đầu...';
        notifyListeners();
        final byteData = await rootBundle.load(
          'assets/models/UVR_MDXNET_9482.onnx',
        );
        final bytes = byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );
        await modelFile.writeAsBytes(bytes, flush: true);
      }
      _onnxModelFilePath = modelFile.path;
    } catch (_) {}
  }

  double _computeAudioSignature(PcmAudioData audio) {
    final int n = audio.length;
    if (n == 0) return 0.0;
    final int step = (n ~/ 128) > 1 ? (n ~/ 128) : 1;
    double acc = 0.0;
    for (int i = 0; i < n; i += step) {
      acc += audio.leftChannel[i] * (i + 1) - audio.rightChannel[i] * 0.5;
    }
    return acc;
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
        final metrics = _analyzer.analyzeAudioClip(pcm, stepIndex: stepIndex);
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
    final metrics = _analyzer.analyzeAudioClip(demoAudio, stepIndex: stepIndex);
    _wizardSteps[stepIndex] = metrics;

    _isBusyProcessing = false;
    _statusMessage = 'Đã trích xuất xong đặc trưng Bước ${stepIndex + 1}!';
    notifyListeners();
  }

  /// Phát thang âm mẫu "Đồ Rê Mi Pha Son La Si Đố" để người dùng nghe và bắt tông ở Bước 2
  Future<void> playDoReMiGuideTone() async {
    try {
      await _player.stop();
      final guidePcm = _audioIo.generateDoReMiGuideScale(durationSeconds: 3.6);
      final dir = await getTemporaryDirectory();
      final file = await _audioIo.writeWavFile(
        guidePcm,
        '${dir.path}/doremi_guide.wav',
      );
      _statusMessage =
          'Đang phát thang âm mẫu: Đồ ↗ Rê ↗ Mi ↗ Pha ↗ Son ↗ La ↗ Si ↗ Đố...';
      notifyListeners();
      await _player.play(DeviceFileSource(file.path));
    } catch (e) {
      _statusMessage = 'Không thể phát âm mẫu ($e).';
      notifyListeners();
    }
  }

  /// Xóa kết quả 4 bước hiện tại để người dùng đo lại một hồ sơ giọng mới từ Bước 1
  void resetWizardSteps() {
    for (int i = 0; i < 4; i++) {
      _wizardSteps[i] = null;
    }
    _statusMessage = 'Đã làm mới 4 bước! Hãy bắt đầu thu âm từ Bước 1.';
    notifyListeners();
  }

  /// Phân tích tổng hợp từ 4 bước để tạo ra một [UserVoiceProfile] chờ người dùng đặt tên và lưu
  Future<UserVoiceProfile> analyze4StepsForPreview() async {
    _isBusyProcessing = true;
    _statusMessage = 'Đang phân tích tổng hợp đặc trưng giọng 4 bước...';
    notifyListeners();

    for (int i = 0; i < 4; i++) {
      if (_wizardSteps[i] == null) {
        final demo = _audioIo.generateDemoKaraokeMix(durationSeconds: 2.5);
        _wizardSteps[i] = _analyzer.analyzeAudioClip(demo, stepIndex: i);
      }
    }

    final validSteps = _wizardSteps.whereType<StepAnalysisMetrics>().toList();
    final analyzed = _analyzer.buildProfileFrom4Steps(validSteps);
    final defaultName =
        'Giọng của tôi #${_savedProfiles.length + 1} (${analyzed.vocalType.title.split(' ').first})';
    final previewProfile = analyzed.copyWith(
      name: defaultName,
      createdAt: DateTime.now(),
    );

    _isBusyProcessing = false;
    _statusMessage = 'Phân tích hoàn tất! Hãy nhập tên để lưu hồ sơ giọng.';
    notifyListeners();
    return previewProfile;
  }

  /// Lưu hồ sơ giọng đã phân tích với tên do người dùng đặt và chọn làm giọng mặc định
  Future<void> saveAnalyzedVoiceProfile(
    UserVoiceProfile profile,
    String customName,
  ) async {
    final trimmed = customName.trim();
    final finalProfile = profile.copyWith(
      name: trimmed.isEmpty ? 'Giọng #${_savedProfiles.length + 1}' : trimmed,
      createdAt: DateTime.now(),
    );

    _savedProfiles.removeWhere((p) => p.id == finalProfile.id);
    _savedProfiles.insert(0, finalProfile); // Giọng mới nhất luôn ở vị trí đầu tiên
    _voiceProfile = finalProfile;
    _hasCustomProfile = true;
    _dspParams = DspParameters.fromVoiceProfile(_voiceProfile);

    await _persistSavedProfiles();
    await applyDspToCurrentTrack();

    _statusMessage =
        'Đã lưu giọng "${finalProfile.name}"! Bạn có thể sang tab 2. Làm Đẹp Karaoke.';
    notifyListeners();
  }

  /// Chọn một hồ sơ giọng đã lưu trong danh sách và cập nhật ngay theo chế độ hiện tại
  Future<void> selectSavedVoiceProfile(UserVoiceProfile profile) async {
    _voiceProfile = profile;
    _hasCustomProfile = true;
    if (_controlMode == StudioControlMode.smartPresets) {
      _dspParams = DspParameters.fromPreset(
        _selectedPreset,
        _voiceProfile,
        intensity: _presetIntensity,
        vocalMusicBalance: _vocalMusicBalance,
      );
    } else {
      _dspParams = DspParameters.fromVoiceProfile(_voiceProfile);
    }
    await applyDspToCurrentTrack();
    _statusMessage = 'Đang áp dụng hồ sơ giọng "${profile.name}"';
    notifyListeners();
  }

  /// Xóa một hồ sơ giọng khỏi danh sách đã lưu
  Future<void> deleteSavedVoiceProfile(String id) async {
    _savedProfiles.removeWhere((p) => p.id == id);
    if (_savedProfiles.isNotEmpty) {
      _voiceProfile = _savedProfiles.first;
      _hasCustomProfile = true;
      _dspParams = DspParameters.fromVoiceProfile(_voiceProfile);
    } else {
      _voiceProfile = UserVoiceProfile.defaultDemo();
      _hasCustomProfile = false;
    }
    await _persistSavedProfiles();
    notifyListeners();
  }

  Future<void> _persistSavedProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listMap = _savedProfiles.map((e) => e.toMap()).toList();
      await prefs.setString('saved_voice_profiles_list_v1', jsonEncode(listMap));
      if (_savedProfiles.isNotEmpty) {
        await prefs.setString(
          'user_voice_profile_v1',
          _savedProfiles.first.toJson(),
        );
      }
    } catch (_) {}
  }

  // ===========================================================================
  // PHÂN HỆ 2: CHỌN FILE / THU ÂM KARAOKE & XỬ LÝ THEO 3 CHẾ ĐỘ
  // ===========================================================================

  /// Lấy danh sách tất cả các file âm thanh mẫu có trong thư mục `assets/audio/`
  Future<List<String>> listAvailableSampleAssets() async {
    const fallbackAssets = [
      'assets/audio/diem_xua.wav',
      'assets/audio/diem_xua_nu.wav',
    ];
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final found = manifest
          .listAssets()
          .where((path) => path.startsWith('assets/audio/'))
          .toList()
        ..sort();
      return found.isNotEmpty ? found : fallbackAssets;
    } catch (_) {
      return fallbackAssets;
    }
  }

  /// Tải một bản thu Karaoke mẫu cụ thể từ `assets/audio/` (mặc định là `diem_xua.wav`)
  Future<void> loadBuiltInDemoKaraoke({
    String assetPath = 'assets/audio/diem_xua.wav',
    bool processImmediately = true,
  }) async {
    final fileName = assetPath.split('/').last;
    _isBusyProcessing = true;
    _statusMessage = 'Đang nạp bản thu mẫu "$fileName"...';
    notifyListeners();

    try {
      await _player.stop();
      PcmAudioData pcm;
      try {
        final byteData = await rootBundle.load(assetPath);
        final wavBytes = byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );
        pcm = _audioIo.decodeWavBytes(wavBytes);
        _currentTrackName =
            '$fileName (${pcm.durationSeconds.toStringAsFixed(1)}s)';
      } catch (_) {
        pcm = _audioIo.generateDemoKaraokeMix(durationSeconds: 8.0);
        _currentTrackName = 'Karaoke Mẫu (Giọng + Nhạc Loa Ngoài)';
      }

      _originalPcm = pcm;
      _enhancedPcm = null;
      _originalWaveform = pcm.extractWaveformPeaks(64);
      _totalDuration = Duration(
        milliseconds: (pcm.durationSeconds * 1000).round(),
      );

      try {
        final dir = await getTemporaryDirectory();
        if (_originalFilePath != null) {
          final oldOrig = File(_originalFilePath!);
          if (await oldOrig.exists()) {
            await oldOrig.delete();
          }
        }
        final ts = DateTime.now().millisecondsSinceEpoch;
        final origFile = await _audioIo.writeWavFile(
          pcm,
          '${dir.path}/karaoke_original_$ts.wav',
        );
        _originalFilePath = origFile.path;
      } catch (_) {}

      if (processImmediately) {
        await applyDspToCurrentTrack();
      } else {
        _statusMessage =
            'Đã nạp "$fileName". Sang Tab 2 để AI tách giọng & áp hồ sơ giọng!';
      }
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

  /// Thực thi Pipeline Tách Nhạc & Chuỗi 5 Hiệu ứng DSP trên Background Isolate
  /// để Giao diện (UI Thread) luôn mượt 60fps, tuyệt đối không bao giờ bị đơ (ANR / Not Responding)!
  Future<void> applyDspToCurrentTrack() async {
    final input = _originalPcm;
    if (input == null) return;

    await _ensureAiOnnxModelLoaded();

    final double sig = _computeAudioSignature(input);
    final bool hasCachedStems = _cachedStems != null &&
        _cachedStemsInputLength == input.length &&
        _cachedStemsSignature == sig;

    _isBusyProcessing = true;
    _statusMessage = hasCachedStems
        ? 'Đang áp đặc trưng giọng "${_voiceProfile.name}" & chạy DSP (từ Cache)...'
        : 'Đang chạy AI UVR-MDX-NET tách riêng Giọng & Nhạc nền (ngầm trên Isolate)...';
    notifyListeners();

    final paramsSnapshot = _dspParams;
    final modelPathSnapshot = _onnxModelFilePath;
    final cachedStemsSnapshot = hasCachedStems ? _cachedStems : null;
    final tempDir = await getTemporaryDirectory();
    final tempDirPath = tempDir.path;
    final ts = DateTime.now().millisecondsSinceEpoch;

    // Xóa các file cũ nếu có
    for (final oldPath in [
      _enhancedFilePath,
      _vocalSoloFilePath,
      _musicSoloFilePath,
    ]) {
      if (oldPath != null) {
        try {
          final oldFile = File(oldPath);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        } catch (_) {}
      }
    }

    // Đẩy toàn bộ tác vụ nặng (ONNX C++ FFI + Pitch Shift + 5-Stage DSP + Ghi 3 file WAV) sang Background Isolate
    final isoResult = await Isolate.run(() async {
      final engine = DspEngineService();
      final io = AudioIoService();
      SeparatedStems stems;
      if (cachedStemsSnapshot != null && paramsSnapshot.enableStemSeparation) {
        stems = cachedStemsSnapshot;
      } else if (paramsSnapshot.enableStemSeparation) {
        final sep = VocalSeparatorService();
        try {
          if (modelPathSnapshot != null && modelPathSnapshot.isNotEmpty) {
            sep.initAiOnnxModel(modelPathSnapshot, numThreads: 2);
          }
          stems = sep.separateVocalAndMusic(input);
        } finally {
          sep.dispose();
        }
      } else {
        stems = SeparatedStems(
          vocalStem: input,
          instrumentalStem: PcmAudioData(
            sampleRate: input.sampleRate,
            channels: 2,
            leftChannel: Float64List(input.length),
            rightChannel: Float64List(input.length),
          ),
        );
      }

      final report = engine.processSeparatedStems(
        vocalStem: stems.vocalStem,
        musicStem: stems.instrumentalStem,
        params: paramsSnapshot,
        usedAiOnnxModel: stems.usedAiOnnxModel,
      );

      final enhWave = report.outputAudio.extractWaveformPeaks(64);
      final vocWave = report.vocalOnlyAudio.extractWaveformPeaks(64);
      final musWave = report.musicOnlyAudio.extractWaveformPeaks(64);

      String? enhPath;
      String? vocPath;
      String? musPath;
      try {
        final outFile = await io.writeWavFile(
          report.outputAudio,
          '$tempDirPath/karaoke_enhanced_$ts.wav',
        );
        final vocalFile = await io.writeWavFile(
          report.vocalOnlyAudio,
          '$tempDirPath/karaoke_vocal_solo_$ts.wav',
        );
        final musicFile = await io.writeWavFile(
          report.musicOnlyAudio,
          '$tempDirPath/karaoke_music_solo_$ts.wav',
        );
        enhPath = outFile.path;
        vocPath = vocalFile.path;
        musPath = musicFile.path;
      } catch (_) {}

      return (
        stems: stems,
        report: report,
        enhWave: enhWave,
        vocWave: vocWave,
        musWave: musWave,
        enhPath: enhPath,
        vocPath: vocPath,
        musPath: musPath,
      );
    });

    if (paramsSnapshot.enableStemSeparation) {
      _cachedStems = isoResult.stems;
      _cachedStemsInputLength = input.length;
      _cachedStemsSignature = sig;
    }

    final report = isoResult.report;
    _enhancedPcm = report.outputAudio;
    _lastReport = report;
    _enhancedWaveform = isoResult.enhWave;
    _vocalSoloWaveform = isoResult.vocWave;
    _musicSoloWaveform = isoResult.musWave;
    _enhancedFilePath = isoResult.enhPath;
    _vocalSoloFilePath = isoResult.vocPath;
    _musicSoloFilePath = isoResult.musPath;

    _isBusyProcessing = false;
    final aiTag = report.usedAiOnnxModel ? '[AI UVR-ONNX]' : '[DSP STFT]';
    final shiftTxt = report.appliedSemitoneShift.abs() >= 0.35
        ? '$aiTag Dịch ${report.appliedSemitoneShift >= 0 ? "+" : ""}${report.appliedSemitoneShift.toStringAsFixed(1)} bán cung (${report.trackOriginalF0Hz.round()}Hz -> F0 giọng lưu ${_voiceProfile.speakingF0MeanHz.round()}Hz)'
        : '$aiTag Khớp màu giọng "${_voiceProfile.name}" (F0 ${_voiceProfile.speakingF0MeanHz.round()}Hz)';
    _statusMessage =
        '$shiftTxt • ${report.processingTimeMs}ms • ${report.pitchCorrectedFrames} khung Pitch';
    notifyListeners();

    // Nếu đang phát nhạc thì cập nhật nguồn phát sang bản mới tương ứng chế độ đang nghe
    final activePath = _filePathForMode(_listenMode);
    if (_isPlaying &&
        _listenMode != AudioListenMode.original &&
        activePath != null) {
      final pos = _currentPosition;
      await _player.play(DeviceFileSource(activePath));
      await _player.seek(pos);
    }
  }

  // ===========================================================================
  // PHÂN HỆ 3: TRÌNH PHÁT ĐỐI CHIẾU A/B & KIỂM TRA TÁCH GIỌNG (SOLO STEMS)
  // ===========================================================================

  String? _filePathForMode(AudioListenMode mode) {
    switch (mode) {
      case AudioListenMode.original:
        return _originalFilePath;
      case AudioListenMode.enhancedMix:
        return _enhancedFilePath;
      case AudioListenMode.vocalSolo:
        return _vocalSoloFilePath ?? _enhancedFilePath;
      case AudioListenMode.musicSolo:
        return _musicSoloFilePath ?? _originalFilePath;
    }
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
      return;
    }

    final targetPath = _filePathForMode(_listenMode);
    if (targetPath == null || !await File(targetPath).exists()) {
      _statusMessage = 'Chưa có file âm thanh để phát.';
      notifyListeners();
      return;
    }

    await _player.play(DeviceFileSource(targetPath));
  }

  /// Chuyển đổi tức thì giữa 4 chế độ nghe:
  /// 1. Gốc (Before)
  /// 2. Đã chỉnh (After Mix)
  /// 3. Chỉ Giọng (Vocal Solo - kiểm tra độ sạch tách giọng)
  /// 4. Chỉ Nhạc (Music Solo - kiểm tra nhạc nền tách ra)
  Future<void> setListenMode(AudioListenMode mode) async {
    if (_listenMode == mode) return;
    _listenMode = mode;
    notifyListeners();

    if (_isPlaying) {
      final pos = _currentPosition;
      final targetPath = _filePathForMode(_listenMode);
      if (targetPath != null && await File(targetPath).exists()) {
        await _player.play(DeviceFileSource(targetPath));
        await _player.seek(pos);
      }
    }
  }

  /// Tương thích với bộ gọi bật/tắt Before/After
  Future<void> setAbComparisonMode(bool listenEnhanced) async {
    await setListenMode(
      listenEnhanced ? AudioListenMode.enhancedMix : AudioListenMode.original,
    );
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
