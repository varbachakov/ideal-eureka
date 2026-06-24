import 'package:flutter/material.dart';

import '../features/camera_capture/presentation/camera_capture_screen.dart';
import 'yarmy_theme.dart';

class YarmyApp extends StatelessWidget {
  const YarmyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yarmy',
      debugShowCheckedModeBanner: false,
      theme: buildYarmyTheme(),
      home: const CameraCaptureScreen(),
    );
  }
}
