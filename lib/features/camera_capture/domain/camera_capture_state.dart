enum CameraCaptureStatus {
  initializing,
  ready,
  recording,
  captured,
  permissionDenied,
  unavailable,
  failed,
}

class CapturedVideo {
  const CapturedVideo({required this.path, required this.duration});

  final String path;
  final Duration duration;
}

class CameraRecordingProgress {
  const CameraRecordingProgress({
    this.duration = Duration.zero,
    this.maxDuration = const Duration(seconds: 60),
  });

  final Duration duration;
  final Duration maxDuration;

  double get fraction {
    if (maxDuration.inMilliseconds <= 0) {
      return 0;
    }

    final value = duration.inMilliseconds / maxDuration.inMilliseconds;
    return value.clamp(0, 1);
  }
}

class CameraCaptureState {
  const CameraCaptureState({
    required this.status,
    required this.title,
    required this.message,
    this.recordingDuration = Duration.zero,
    this.maxRecordingDuration = const Duration(seconds: 60),
    this.capturedVideo,
  });

  const CameraCaptureState.initializing()
    : status = CameraCaptureStatus.initializing,
      title = 'Открываем камеру',
      message = 'Подготавливаем съемку настоящей истории.',
      recordingDuration = Duration.zero,
      maxRecordingDuration = const Duration(seconds: 60),
      capturedVideo = null;

  const CameraCaptureState.ready()
    : status = CameraCaptureStatus.ready,
      title = 'Камера готова',
      message = 'Можно снять настоящую историю до 60 секунд.',
      recordingDuration = Duration.zero,
      maxRecordingDuration = const Duration(seconds: 60),
      capturedVideo = null;

  const CameraCaptureState.recording({
    required this.recordingDuration,
    this.maxRecordingDuration = const Duration(seconds: 60),
  }) : status = CameraCaptureStatus.recording,
       title = 'Идет запись',
       message = 'Снимайте настоящий момент одним дублем.',
       capturedVideo = null;

  CameraCaptureState.captured({
    required CapturedVideo video,
    this.maxRecordingDuration = const Duration(seconds: 60),
  }) : status = CameraCaptureStatus.captured,
       title = 'История снята',
       message =
           'Видео сохранено локально. Предпросмотр будет следующим этапом.',
       recordingDuration = video.duration,
       capturedVideo = video;

  const CameraCaptureState.permissionDenied({
    this.title = 'Нет доступа к камере',
    this.message =
        'Разрешите доступ к камере и микрофону, чтобы снять историю.',
    this.maxRecordingDuration = const Duration(seconds: 60),
  }) : status = CameraCaptureStatus.permissionDenied,
       recordingDuration = Duration.zero,
       capturedVideo = null;

  const CameraCaptureState.unavailable({
    this.title = 'Камера не найдена',
    this.message = 'На устройстве нет доступной камеры.',
    this.maxRecordingDuration = const Duration(seconds: 60),
  }) : status = CameraCaptureStatus.unavailable,
       recordingDuration = Duration.zero,
       capturedVideo = null;

  const CameraCaptureState.failed({
    this.title = 'Камера не открылась',
    this.message = 'Попробуйте открыть камеру еще раз.',
    this.maxRecordingDuration = const Duration(seconds: 60),
  }) : status = CameraCaptureStatus.failed,
       recordingDuration = Duration.zero,
       capturedVideo = null;

  final CameraCaptureStatus status;
  final String title;
  final String message;
  final Duration recordingDuration;
  final Duration maxRecordingDuration;
  final CapturedVideo? capturedVideo;

  bool get isReady => status == CameraCaptureStatus.ready;
  bool get isRecording => status == CameraCaptureStatus.recording;
  bool get isCaptured => status == CameraCaptureStatus.captured;
  bool get canRecord => status == CameraCaptureStatus.ready;
  bool get hasCameraPreview =>
      status == CameraCaptureStatus.ready ||
      status == CameraCaptureStatus.recording;
  bool get canRetry =>
      status == CameraCaptureStatus.permissionDenied ||
      status == CameraCaptureStatus.failed;
  double get recordingProgress {
    if (maxRecordingDuration.inMilliseconds <= 0) {
      return 0;
    }

    final progress =
        recordingDuration.inMilliseconds / maxRecordingDuration.inMilliseconds;
    return progress.clamp(0, 1);
  }
}
