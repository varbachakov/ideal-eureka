import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import '../domain/camera_capture_state.dart';
import '../domain/yarmy_camera_controller.dart';

class FlutterYarmyCameraController extends YarmyCameraController {
  CameraController? _cameraController;
  CameraCaptureState _state = const CameraCaptureState.initializing();
  bool _isDisposed = false;

  @override
  CameraCaptureState get state => _state;

  @override
  Future<void> initialize() async {
    await _disposeCameraController();
    _setState(const CameraCaptureState.initializing());

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setState(const CameraCaptureState.unavailable());
        return;
      }

      final camera = _selectDefaultCamera(cameras);
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: true,
      );

      await controller.initialize();

      if (_isDisposed) {
        await controller.dispose();
        return;
      }

      _cameraController = controller;
      _setState(const CameraCaptureState.ready());
    } on CameraException catch (error) {
      _setState(_mapCameraException(error));
    } catch (_) {
      _setState(const CameraCaptureState.failed());
    }
  }

  @override
  Future<void> pause() async {
    await _disposeCameraController();
    if (!_isDisposed) {
      _setState(const CameraCaptureState.initializing());
    }
  }

  @override
  Widget buildPreview(BuildContext context) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return CameraPreview(controller);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cameraController?.dispose();
    _cameraController = null;
    super.dispose();
  }

  CameraDescription _selectDefaultCamera(List<CameraDescription> cameras) {
    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.back) {
        return camera;
      }
    }

    return cameras.first;
  }

  CameraCaptureState _mapCameraException(CameraException error) {
    return switch (error.code) {
      'CameraAccessDenied' ||
      'CameraAccessDeniedWithoutPrompt' ||
      'CameraAccessRestricted' => const CameraCaptureState.permissionDenied(),
      'AudioAccessDenied' ||
      'AudioAccessDeniedWithoutPrompt' ||
      'AudioAccessRestricted' => const CameraCaptureState.permissionDenied(
        title: 'Нет доступа к микрофону',
        message: 'Разрешите доступ к микрофону, чтобы записать звук истории.',
      ),
      _ => CameraCaptureState.failed(
        message: error.description ?? 'Попробуйте открыть камеру еще раз.',
      ),
    };
  }

  Future<void> _disposeCameraController() async {
    final controller = _cameraController;
    _cameraController = null;
    await controller?.dispose();
  }

  void _setState(CameraCaptureState state) {
    if (_isDisposed) {
      return;
    }

    _state = state;
    notifyListeners();
  }
}
