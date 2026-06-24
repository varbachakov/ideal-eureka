enum CameraCaptureStatus {
  initializing,
  ready,
  permissionDenied,
  unavailable,
  failed,
}

class CameraCaptureState {
  const CameraCaptureState({
    required this.status,
    required this.title,
    required this.message,
  });

  const CameraCaptureState.initializing()
    : status = CameraCaptureStatus.initializing,
      title = 'Открываем камеру',
      message = 'Подготавливаем съемку настоящей истории.';

  const CameraCaptureState.ready()
    : status = CameraCaptureStatus.ready,
      title = 'Камера готова',
      message = 'Можно снять настоящую историю до 60 секунд.';

  const CameraCaptureState.permissionDenied({
    this.title = 'Нет доступа к камере',
    this.message =
        'Разрешите доступ к камере и микрофону, чтобы снять историю.',
  }) : status = CameraCaptureStatus.permissionDenied;

  const CameraCaptureState.unavailable({
    this.title = 'Камера не найдена',
    this.message = 'На устройстве нет доступной камеры.',
  }) : status = CameraCaptureStatus.unavailable;

  const CameraCaptureState.failed({
    this.title = 'Камера не открылась',
    this.message = 'Попробуйте открыть камеру еще раз.',
  }) : status = CameraCaptureStatus.failed;

  final CameraCaptureStatus status;
  final String title;
  final String message;

  bool get isReady => status == CameraCaptureStatus.ready;
  bool get canRetry =>
      status == CameraCaptureStatus.permissionDenied ||
      status == CameraCaptureStatus.failed;
}
