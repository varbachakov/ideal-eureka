import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../domain/camera_capture_state.dart';
import '../domain/yarmy_camera_controller.dart';

typedef YarmyCameraSessionFactory = Future<YarmyCameraSession> Function();

typedef YarmyCameraSessionBuilder =
    YarmyCameraSession Function({
      required CameraDescription camera,
      required ResolutionPreset resolutionPreset,
    });

@visibleForTesting
const List<ResolutionPreset> yarmyCameraResolutionFallbacks = [
  ResolutionPreset.high,
  ResolutionPreset.medium,
  ResolutionPreset.low,
];

abstract interface class YarmyCameraSession {
  Future<void> initialize();

  bool get isInitialized;
  bool get isRecordingVideo;

  Future<void> prepareForVideoRecording();

  Future<void> startVideoRecording();

  Future<String> stopVideoRecording();

  Widget buildPreview(BuildContext context);

  Future<void> dispose();
}

class FlutterYarmyCameraController extends YarmyCameraController {
  FlutterYarmyCameraController({
    YarmyCameraSessionFactory? cameraSessionFactory,
  }) : _cameraSessionFactory =
           cameraSessionFactory ?? _createDefaultCameraSession;

  static const Duration maxRecordingDuration = Duration(seconds: 60);
  static const Duration _recordingProgressTickInterval = Duration(seconds: 1);

  final YarmyCameraSessionFactory _cameraSessionFactory;

  YarmyCameraSession? _cameraSession;
  CameraCaptureState _state = const CameraCaptureState.initializing();
  final ValueNotifier<CameraRecordingProgress> _recordingProgress =
      ValueNotifier(
        const CameraRecordingProgress(maxDuration: maxRecordingDuration),
      );
  Timer? _recordingProgressTimer;
  Timer? _maxRecordingTimer;
  DateTime? _recordingStartedAt;
  Future<void>? _startRecordingFuture;
  Future<void>? _stopRecordingFuture;
  int _cameraOperationId = 0;
  bool _isDisposed = false;
  bool _shouldKeepCameraOpen = false;

  @override
  CameraCaptureState get state => _state;

  @override
  ValueListenable<CameraRecordingProgress> get recordingProgress =>
      _recordingProgress;

  @override
  Future<void> initialize() async {
    if (_state.isCaptured) {
      return;
    }

    final currentSession = _cameraSession;
    if (_state.isReady &&
        currentSession != null &&
        currentSession.isInitialized &&
        _stopRecordingFuture == null) {
      _shouldKeepCameraOpen = true;
      return;
    }

    _shouldKeepCameraOpen = true;

    final pendingStop = _stopRecordingFuture;
    if (pendingStop != null) {
      await pendingStop;
      if (_isDisposed ||
          !_shouldKeepCameraOpen ||
          _state.isCaptured ||
          _state.status == CameraCaptureStatus.failed) {
        return;
      }
    }

    final operationId = _nextCameraOperation();
    await _disposeCameraSession();
    if (!_isCurrentCameraOperation(operationId)) {
      return;
    }

    _setState(const CameraCaptureState.initializing());

    try {
      final session = await _cameraSessionFactory();
      if (!_isCurrentCameraOperation(operationId)) {
        await session.dispose();
        return;
      }

      _cameraSession = session;
      _setState(const CameraCaptureState.ready());
    } on _NoCameraAvailableException {
      if (_isCurrentCameraOperation(operationId)) {
        _setState(const CameraCaptureState.unavailable());
      }
    } on CameraException catch (error) {
      if (_isCurrentCameraOperation(operationId)) {
        _setState(_mapCameraException(error));
      }
    } catch (_) {
      if (_isCurrentCameraOperation(operationId)) {
        _setState(const CameraCaptureState.failed());
      }
    }
  }

  @override
  Future<void> pause() async {
    final shouldStopRecording =
        _state.isRecording ||
        _startRecordingFuture != null ||
        _stopRecordingFuture != null;
    if (shouldStopRecording) {
      await _stopRecording(keepCapturedVideo: true);
    }

    _shouldKeepCameraOpen = false;
    _cameraOperationId++;

    await _disposeCameraSession();

    if (!_isDisposed &&
        (_state.status == CameraCaptureStatus.initializing || _state.isReady)) {
      _setState(const CameraCaptureState.initializing());
    }
  }

  @override
  Future<void> startRecording() {
    final existingStart = _startRecordingFuture;
    if (existingStart != null) {
      return existingStart;
    }

    if (!_state.canRecord) {
      return Future<void>.value();
    }

    final operationId = _cameraOperationId;
    final session = _cameraSession;
    if (session == null || !session.isInitialized) {
      _setState(const CameraCaptureState.failed());
      return Future<void>.value();
    }

    if (session.isRecordingVideo || _state.isRecording) {
      return Future<void>.value();
    }

    late final Future<void> startFuture;
    startFuture = _doStartRecording(operationId: operationId, session: session)
        .whenComplete(() {
          if (identical(_startRecordingFuture, startFuture)) {
            _startRecordingFuture = null;
          }
        });
    _startRecordingFuture = startFuture;
    return startFuture;
  }

  Future<void> _doStartRecording({
    required int operationId,
    required YarmyCameraSession session,
  }) async {
    try {
      await session.prepareForVideoRecording();
      if (!_isCurrentCameraOperation(operationId)) {
        return;
      }

      await session.startVideoRecording();
      if (!_isCurrentCameraOperation(operationId)) {
        await _stopStaleRecording(session);
        return;
      }

      _recordingStartedAt = DateTime.now();
      _setRecordingState(Duration.zero);
      _startRecordingTimers();
    } on CameraException catch (error) {
      if (_isCurrentCameraOperation(operationId)) {
        _setState(_mapCameraException(error));
      }
    } catch (_) {
      if (_isCurrentCameraOperation(operationId)) {
        _setState(const CameraCaptureState.failed());
      }
    }
  }

  @override
  Future<void> stopRecording() {
    final pendingStart = _startRecordingFuture;
    if (pendingStart != null) {
      return pendingStart.then((_) async {
        if (_isDisposed) {
          return;
        }

        final session = _cameraSession;
        if (!_state.isRecording && session?.isRecordingVideo != true) {
          return;
        }

        await _stopRecording(keepCapturedVideo: true);
      });
    }

    return _stopRecording(keepCapturedVideo: true);
  }

  @override
  Widget buildPreview(BuildContext context) {
    final session = _cameraSession;
    if (session == null || !session.isInitialized) {
      return const SizedBox.shrink();
    }

    return session.buildPreview(context);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _shouldKeepCameraOpen = false;
    _cameraOperationId++;
    if (_startRecordingFuture != null || _state.isRecording) {
      unawaited(_stopAndDisposeCameraSession());
    } else {
      _stopRecordingTimers();
      final session = _cameraSession;
      _cameraSession = null;
      unawaited(session?.dispose());
    }
    _recordingProgress.dispose();
    super.dispose();
  }

  static CameraDescription? _cachedDefaultCamera;

  static Future<YarmyCameraSession> _createDefaultCameraSession() async {
    final camera = await _resolveDefaultCamera();
    try {
      return await createYarmyCameraSessionWithFallback(
        camera: camera,
        sessionBuilder:
            ({
              required CameraDescription camera,
              required ResolutionPreset resolutionPreset,
            }) => _FlutterYarmyCameraSession(
              camera: camera,
              resolutionPreset: resolutionPreset,
            ),
      );
    } catch (_) {
      _cachedDefaultCamera = null;
      rethrow;
    }
  }

  static Future<CameraDescription> _resolveDefaultCamera() async {
    final cachedCamera = _cachedDefaultCamera;
    if (cachedCamera != null) {
      return cachedCamera;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw const _NoCameraAvailableException();
    }

    final camera = _selectDefaultCamera(cameras);
    _cachedDefaultCamera = camera;
    return camera;
  }

  static CameraDescription _selectDefaultCamera(
    List<CameraDescription> cameras,
  ) {
    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.back) {
        return camera;
      }
    }

    return cameras.first;
  }

  CameraCaptureState _mapCameraException(CameraException error) {
    if (_cameraPermissionErrorCodes.contains(error.code)) {
      return const CameraCaptureState.permissionDenied();
    }

    if (_audioPermissionErrorCodes.contains(error.code)) {
      return const CameraCaptureState.permissionDenied(
        title: 'Нет доступа к микрофону',
        message: 'Разрешите доступ к микрофону, чтобы записать звук истории.',
      );
    }

    return const CameraCaptureState.failed();
  }

  Future<void> _stopRecording({required bool keepCapturedVideo}) async {
    final existingStop = _stopRecordingFuture;
    if (existingStop != null) {
      return existingStop;
    }

    late final Future<void> stopFuture;
    stopFuture = _awaitPendingStartAndStop(keepCapturedVideo: keepCapturedVideo)
        .whenComplete(() {
          if (identical(_stopRecordingFuture, stopFuture)) {
            _stopRecordingFuture = null;
          }
        });
    _stopRecordingFuture = stopFuture;
    return stopFuture;
  }

  Future<void> _awaitPendingStartAndStop({
    required bool keepCapturedVideo,
  }) async {
    final pendingStart = _startRecordingFuture;
    if (pendingStart != null) {
      await pendingStart;
    }

    await _doStopRecording(keepCapturedVideo: keepCapturedVideo);
  }

  Future<void> _doStopRecording({required bool keepCapturedVideo}) async {
    final session = _cameraSession;
    if (session == null || !session.isRecordingVideo) {
      _stopRecordingTimers();
      if (!_isDisposed && _state.isRecording) {
        _setState(const CameraCaptureState.ready());
      }
      return;
    }

    final duration = _currentRecordingDuration();
    _stopRecordingTimers();

    try {
      final path = await session.stopVideoRecording();
      if (keepCapturedVideo) {
        _setState(
          CameraCaptureState.captured(
            video: CapturedVideo(path: path, duration: duration),
          ),
        );
        await _disposeCameraSession();
      } else {
        _setState(const CameraCaptureState.ready());
      }
    } on CameraException catch (error) {
      _setState(_mapCameraException(error));
      await _disposeCameraSession();
    } catch (_) {
      _setState(const CameraCaptureState.failed());
      await _disposeCameraSession();
    }
  }

  Future<void> _stopStaleRecording(YarmyCameraSession session) async {
    try {
      if (session.isRecordingVideo) {
        await session.stopVideoRecording();
      }
    } catch (_) {
      // The lifecycle operation that made this recording stale owns recovery.
    }
  }

  void _startRecordingTimers() {
    _recordingProgressTimer?.cancel();
    _recordingProgressTimer = null;
    _maxRecordingTimer?.cancel();
    _maxRecordingTimer = null;
    _setRecordingProgress(Duration.zero);
    _recordingProgressTimer = Timer.periodic(_recordingProgressTickInterval, (
      _,
    ) {
      _setRecordingProgress(_currentRecordingDuration());
    });
    _maxRecordingTimer = Timer(maxRecordingDuration, () {
      unawaited(stopRecording());
    });
  }

  void _stopRecordingTimers({bool resetProgress = true}) {
    _recordingProgressTimer?.cancel();
    _recordingProgressTimer = null;
    _maxRecordingTimer?.cancel();
    _maxRecordingTimer = null;
    _recordingStartedAt = null;
    if (resetProgress && !_isDisposed) {
      _setRecordingProgress(Duration.zero);
    }
  }

  Duration _currentRecordingDuration() {
    final startedAt = _recordingStartedAt;
    if (startedAt == null) {
      return Duration.zero;
    }

    final duration = DateTime.now().difference(startedAt);
    if (duration > maxRecordingDuration) {
      return maxRecordingDuration;
    }

    return duration;
  }

  void _setRecordingState(Duration duration) {
    _setState(
      CameraCaptureState.recording(
        recordingDuration: duration,
        maxRecordingDuration: maxRecordingDuration,
      ),
    );
  }

  void _setRecordingProgress(Duration duration) {
    _recordingProgress.value = CameraRecordingProgress(
      duration: duration,
      maxDuration: maxRecordingDuration,
    );
  }

  int _nextCameraOperation() {
    _cameraOperationId++;
    return _cameraOperationId;
  }

  bool _isCurrentCameraOperation(int operationId) {
    return !_isDisposed &&
        _shouldKeepCameraOpen &&
        operationId == _cameraOperationId &&
        !_state.isCaptured;
  }

  Future<void> _disposeCameraSession() async {
    _stopRecordingTimers();
    final session = _cameraSession;
    _cameraSession = null;
    await session?.dispose();
  }

  Future<void> _stopAndDisposeCameraSession() async {
    await _stopRecording(keepCapturedVideo: false);
    await _disposeCameraSession();
  }

  void _setState(CameraCaptureState state) {
    if (_isDisposed) {
      return;
    }

    _state = state;
    notifyListeners();
  }
}

@visibleForTesting
Future<YarmyCameraSession> createYarmyCameraSessionWithFallback({
  required CameraDescription camera,
  required YarmyCameraSessionBuilder sessionBuilder,
  List<ResolutionPreset> resolutionFallbacks = yarmyCameraResolutionFallbacks,
}) async {
  CameraException? lastCameraError;
  Object? lastUnknownError;
  StackTrace? lastUnknownStackTrace;

  for (final preset in resolutionFallbacks) {
    final session = sessionBuilder(camera: camera, resolutionPreset: preset);
    try {
      await session.initialize();
      if (kDebugMode) {
        debugPrint('Yarmy camera initialized with ${preset.name} preset.');
      }
      return session;
    } on CameraException catch (error) {
      lastCameraError = error;
      await _disposeFailedInitializationSession(session);
      if (!_shouldRetryCameraInitialization(error)) {
        break;
      }
    } catch (error, stackTrace) {
      lastUnknownError = error;
      lastUnknownStackTrace = stackTrace;
      await _disposeFailedInitializationSession(session);
      break;
    }
  }

  if (lastUnknownError != null) {
    Error.throwWithStackTrace(lastUnknownError, lastUnknownStackTrace!);
  }

  throw lastCameraError ?? CameraException('CameraInitFailed', null);
}

const Set<String> _cameraPermissionErrorCodes = {
  'CameraAccessDenied',
  'CameraAccessDeniedWithoutPrompt',
  'CameraAccessRestricted',
};

const Set<String> _audioPermissionErrorCodes = {
  'AudioAccessDenied',
  'AudioAccessDeniedWithoutPrompt',
  'AudioAccessRestricted',
};

bool _shouldRetryCameraInitialization(CameraException error) {
  return !_cameraPermissionErrorCodes.contains(error.code) &&
      !_audioPermissionErrorCodes.contains(error.code);
}

Future<void> _disposeFailedInitializationSession(
  YarmyCameraSession session,
) async {
  try {
    await session.dispose();
  } catch (_) {
    // Preserve the original camera initialization error.
  }
}

final class _FlutterYarmyCameraSession implements YarmyCameraSession {
  _FlutterYarmyCameraSession({
    required CameraDescription camera,
    required ResolutionPreset resolutionPreset,
  }) : _controller = CameraController(
         camera,
         resolutionPreset,
         enableAudio: true,
       );

  final CameraController _controller;
  Future<void>? _disposeFuture;

  @override
  Future<void> initialize() {
    return _controller.initialize();
  }

  @override
  bool get isInitialized => _controller.value.isInitialized;

  @override
  bool get isRecordingVideo => _controller.value.isRecordingVideo;

  @override
  Future<void> prepareForVideoRecording() {
    return _controller.prepareForVideoRecording();
  }

  @override
  Future<void> startVideoRecording() {
    return _controller.startVideoRecording();
  }

  @override
  Future<String> stopVideoRecording() async {
    final file = await _controller.stopVideoRecording();
    return file.path;
  }

  @override
  Widget buildPreview(BuildContext context) {
    return CameraPreview(_controller);
  }

  @override
  Future<void> dispose() {
    final existingDispose = _disposeFuture;
    if (existingDispose != null) {
      return existingDispose;
    }

    final disposeFuture = _controller.dispose();
    _disposeFuture = disposeFuture;
    return disposeFuture;
  }
}

final class _NoCameraAvailableException implements Exception {
  const _NoCameraAvailableException();
}
