import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'camera_capture_state.dart';

abstract class YarmyCameraController extends ChangeNotifier {
  CameraCaptureState get state;

  ValueListenable<CameraRecordingProgress> get recordingProgress;

  Future<void> initialize();

  Future<void> pause();

  Future<void> startRecording();

  Future<void> stopRecording();

  Widget buildPreview(BuildContext context);
}
