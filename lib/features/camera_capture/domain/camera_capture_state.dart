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

abstract interface class CameraRecordingClock {
  Duration get elapsed;
  bool get isRunning;
}

class CameraRecordingProgress {
  const CameraRecordingProgress({
    this.duration = Duration.zero,
    this.maxDuration = const Duration(seconds: 60),
    this.clock,
  });

  final Duration duration;
  final Duration maxDuration;
  final CameraRecordingClock? clock;

  double get fraction {
    return fractionForDuration(duration);
  }

  bool get isFrameSynced {
    return clock?.isRunning ?? false;
  }

  Duration get currentDuration {
    final clock = this.clock;
    if (clock == null) {
      return _clampDuration(duration);
    }

    return _clampDuration(clock.elapsed);
  }

  double get currentFraction {
    return fractionForDuration(currentDuration);
  }

  double fractionForDuration(Duration duration) {
    if (maxDuration.inMilliseconds <= 0) {
      return 0;
    }

    final value = duration.inMilliseconds / maxDuration.inMilliseconds;
    return value.clamp(0, 1).toDouble();
  }

  CameraRecordingProgress snapshot() {
    return CameraRecordingProgress(
      duration: currentDuration,
      maxDuration: maxDuration,
    );
  }

  Duration _clampDuration(Duration duration) {
    if (duration < Duration.zero) {
      return Duration.zero;
    }

    if (duration > maxDuration) {
      return maxDuration;
    }

    return duration;
  }
}

class CameraCaptureState {
  const CameraCaptureState({
    required this.status,
    required this.title,
    required this.message,
    this.capturedVideo,
  });

  const CameraCaptureState.initializing()
    : status = CameraCaptureStatus.initializing,
      title = 'Открываем камеру',
      message = 'Подготавливаем съемку настоящей истории.',
      capturedVideo = null;

  const CameraCaptureState.ready()
    : status = CameraCaptureStatus.ready,
      title = 'Камера готова',
      message = 'Можно снять настоящую историю до 60 секунд.',
      capturedVideo = null;

  const CameraCaptureState.recording()
    : status = CameraCaptureStatus.recording,
      title = 'Идет запись',
      message = 'Снимайте настоящий момент одним дублем.',
      capturedVideo = null;

  CameraCaptureState.captured({required CapturedVideo video})
    : status = CameraCaptureStatus.captured,
      title = 'История снята',
      message =
          'Видео сохранено локально. Предпросмотр будет следующим этапом.',
      capturedVideo = video;

  const CameraCaptureState.permissionDenied({
    this.title = 'Нет доступа к камере',
    this.message =
        'Разрешите доступ к камере и микрофону, чтобы снять историю.',
  }) : status = CameraCaptureStatus.permissionDenied,
       capturedVideo = null;

  const CameraCaptureState.unavailable({
    this.title = 'Камера не найдена',
    this.message = 'На устройстве нет доступной камеры.',
  }) : status = CameraCaptureStatus.unavailable,
       capturedVideo = null;

  const CameraCaptureState.failed({
    this.title = 'Камера не открылась',
    this.message = 'Попробуйте открыть камеру еще раз.',
  }) : status = CameraCaptureStatus.failed,
       capturedVideo = null;

  final CameraCaptureStatus status;
  final String title;
  final String message;
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
}
