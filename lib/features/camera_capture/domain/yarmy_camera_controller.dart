import 'package:flutter/material.dart';

import 'camera_capture_state.dart';

abstract class YarmyCameraController extends ChangeNotifier {
  CameraCaptureState get state;

  Future<void> initialize();

  Future<void> pause();

  Widget buildPreview(BuildContext context);
}
