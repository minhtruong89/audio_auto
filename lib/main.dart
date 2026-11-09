import 'package:flutter/material.dart';
import 'state/app_controller.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AudioAutoKaraokeApp());
}

class AudioAutoKaraokeApp extends StatefulWidget {
  const AudioAutoKaraokeApp({super.key});

  @override
  State<AudioAutoKaraokeApp> createState() => _AudioAutoKaraokeAppState();
}

class _AudioAutoKaraokeAppState extends State<AudioAutoKaraokeApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VocalAI Karaoke Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkStudioTheme,
      home: HomeScreen(controller: _controller),
    );
  }
}
