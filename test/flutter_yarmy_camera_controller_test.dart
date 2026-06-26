import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_yarmy/features/camera_capture/data/flutter_yarmy_camera_controller.dart';
import 'package:mobile_yarmy/features/camera_capture/domain/camera_capture_state.dart';

void main() {
  test(
    'camera initialization falls back to the next resolution preset',
    () async {
      final failedHighSession = FakeYarmyCameraSession(
        initializeError: CameraException(
          'CameraAccess',
          'No supported surface combination is found for camera device',
        ),
      );
      final mediumSession = FakeYarmyCameraSession();
      final attempts = <ResolutionPreset>[];

      final session = await createYarmyCameraSessionWithFallback(
        camera: _fakeCamera,
        sessionBuilder: ({required camera, required resolutionPreset}) {
          attempts.add(resolutionPreset);
          return switch (resolutionPreset) {
            ResolutionPreset.high => failedHighSession,
            ResolutionPreset.medium => mediumSession,
            _ => throw StateError('Unexpected preset: $resolutionPreset'),
          };
        },
      );

      expect(session, same(mediumSession));
      expect(attempts, [ResolutionPreset.high, ResolutionPreset.medium]);
      expect(failedHighSession.initializeCallCount, 1);
      expect(failedHighSession.disposeCallCount, 1);
      expect(mediumSession.initializeCallCount, 1);
      expect(mediumSession.disposeCallCount, 0);
    },
  );

  test('camera initialization does not retry permission errors', () async {
    final permissionDeniedSession = FakeYarmyCameraSession(
      initializeError: CameraException('CameraAccessDenied', 'denied'),
    );
    final attempts = <ResolutionPreset>[];

    await expectLater(
      createYarmyCameraSessionWithFallback(
        camera: _fakeCamera,
        sessionBuilder: ({required camera, required resolutionPreset}) {
          attempts.add(resolutionPreset);
          return permissionDeniedSession;
        },
      ),
      throwsA(
        isA<CameraException>().having(
          (error) => error.code,
          'code',
          'CameraAccessDenied',
        ),
      ),
    );

    expect(attempts, [ResolutionPreset.high]);
    expect(permissionDeniedSession.initializeCallCount, 1);
    expect(permissionDeniedSession.disposeCallCount, 1);
  });

  test('ignores initialize result that completes after pause', () async {
    final session = FakeYarmyCameraSession();
    final initializeCompleter = Completer<YarmyCameraSession>();
    final controller = FlutterYarmyCameraController(
      cameraSessionFactory: () => initializeCompleter.future,
    );

    final initializeFuture = controller.initialize();
    await Future<void>.delayed(Duration.zero);

    await controller.pause();
    initializeCompleter.complete(session);
    await initializeFuture;

    expect(controller.state.status, CameraCaptureStatus.initializing);
    expect(session.disposeCallCount, 1);

    controller.dispose();
  });

  test('initialize keeps an already ready camera session', () async {
    final session = FakeYarmyCameraSession();
    var factoryCallCount = 0;
    final controller = FlutterYarmyCameraController(
      cameraSessionFactory: () async {
        factoryCallCount++;
        return session;
      },
    );

    await controller.initialize();
    await controller.initialize();

    expect(controller.state.isReady, isTrue);
    expect(factoryCallCount, 1);
    expect(session.disposeCallCount, 0);

    controller.dispose();
  });

  test('start recording is ignored while start is in flight', () async {
    final session = FakeYarmyCameraSession(startCompleter: Completer<void>());
    final controller = FlutterYarmyCameraController(
      cameraSessionFactory: () async => session,
    );

    await controller.initialize();

    final firstStartFuture = controller.startRecording();
    await Future<void>.delayed(Duration.zero);
    final secondStartFuture = controller.startRecording();
    await Future<void>.delayed(Duration.zero);

    expect(session.startRecordingCallCount, 1);

    session.startCompleter!.complete();
    await Future.wait([firstStartFuture, secondStartFuture]);

    expect(controller.state.isRecording, isTrue);
    expect(session.startRecordingCallCount, 1);

    await controller.stopRecording();
    controller.dispose();
  });

  test('stop recording waits for pending start before capture', () async {
    final session = FakeYarmyCameraSession(startCompleter: Completer<void>());
    final controller = FlutterYarmyCameraController(
      cameraSessionFactory: () async => session,
    );

    await controller.initialize();

    final startFuture = controller.startRecording();
    await Future<void>.delayed(Duration.zero);
    final stopFuture = controller.stopRecording();
    await Future<void>.delayed(Duration.zero);

    expect(session.startRecordingCallCount, 1);
    expect(session.stopRecordingCallCount, 0);

    session.startCompleter!.complete();
    await Future.wait([startFuture, stopFuture]);

    expect(session.stopRecordingCallCount, 1);
    expect(controller.state.isCaptured, isTrue);
    expect(controller.state.capturedVideo?.path, 'local/story.mp4');

    controller.dispose();
  });

  test('pause waits for pending start before disposing camera', () async {
    final session = FakeYarmyCameraSession(startCompleter: Completer<void>());
    final controller = FlutterYarmyCameraController(
      cameraSessionFactory: () async => session,
    );

    await controller.initialize();

    final startFuture = controller.startRecording();
    await Future<void>.delayed(Duration.zero);
    final pauseFuture = controller.pause();
    await Future<void>.delayed(Duration.zero);

    expect(session.disposeCallCount, 0);
    expect(session.stopRecordingCallCount, 0);

    session.startCompleter!.complete();
    await Future.wait([startFuture, pauseFuture]);

    expect(session.stopRecordingCallCount, 1);
    expect(session.disposeCallCount, 1);
    expect(controller.state.status, CameraCaptureStatus.captured);

    controller.dispose();
  });

  test('dispose waits for pending start before disposing camera', () async {
    final session = FakeYarmyCameraSession(startCompleter: Completer<void>());
    final controller = FlutterYarmyCameraController(
      cameraSessionFactory: () async => session,
    );

    await controller.initialize();

    final startFuture = controller.startRecording();
    await Future<void>.delayed(Duration.zero);

    controller.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(session.disposeCallCount, 0);
    expect(session.stopRecordingCallCount, 0);

    session.startCompleter!.complete();
    await startFuture;
    await Future<void>.delayed(Duration.zero);

    expect(session.stopRecordingCallCount, 1);
    expect(session.disposeCallCount, 1);
  });

  test(
    'shows friendly message when native camera initialization fails',
    () async {
      final controller = FlutterYarmyCameraController(
        cameraSessionFactory: () async {
          throw CameraException(
            'CameraAccess',
            'java.lang.IllegalArgumentException: No supported surface '
                'combination is found for camera device',
          );
        },
      );

      await controller.initialize();

      expect(controller.state.status, CameraCaptureStatus.failed);
      expect(controller.state.title, 'Камера не открылась');
      expect(controller.state.message, 'Попробуйте открыть камеру еще раз.');
      expect(controller.state.message, isNot(contains('java.lang')));

      controller.dispose();
    },
  );

  test('pause waits for an in-flight stop before disposing camera', () async {
    final session = FakeYarmyCameraSession(stopCompleter: Completer<String>());
    final controller = FlutterYarmyCameraController(
      cameraSessionFactory: () async => session,
    );

    await controller.initialize();
    await controller.startRecording();

    expect(controller.state.isRecording, isTrue);

    final stopFuture = controller.stopRecording();
    await Future<void>.delayed(Duration.zero);

    final pauseFuture = controller.pause();
    await Future<void>.delayed(Duration.zero);

    expect(session.stopRecordingCallCount, 1);
    expect(session.disposeCallCount, 0);

    session.stopCompleter!.complete('local/story.mp4');
    await Future.wait([stopFuture, pauseFuture]);

    expect(controller.state.isCaptured, isTrue);
    expect(controller.state.capturedVideo?.path, 'local/story.mp4');
    expect(session.disposeCallCount, 1);

    controller.dispose();
  });

  test(
    'initialize waits for an in-flight stop before disposing camera',
    () async {
      final session = FakeYarmyCameraSession(
        stopCompleter: Completer<String>(),
      );
      var factoryCallCount = 0;
      final controller = FlutterYarmyCameraController(
        cameraSessionFactory: () async {
          factoryCallCount++;
          return session;
        },
      );

      await controller.initialize();
      await controller.startRecording();

      final stopFuture = controller.stopRecording();
      await Future<void>.delayed(Duration.zero);

      final initializeFuture = controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(session.stopRecordingCallCount, 1);
      expect(session.disposeCallCount, 0);
      expect(factoryCallCount, 1);

      session.stopCompleter!.complete('local/story.mp4');
      await Future.wait([stopFuture, initializeFuture]);

      expect(controller.state.isCaptured, isTrue);
      expect(controller.state.capturedVideo?.path, 'local/story.mp4');
      expect(session.disposeCallCount, 1);
      expect(factoryCallCount, 1);

      controller.dispose();
    },
  );

  test('stop failure disposes camera session and keeps failed state', () async {
    final session = FakeYarmyCameraSession(stopError: Exception('stop failed'));
    final controller = FlutterYarmyCameraController(
      cameraSessionFactory: () async => session,
    );

    await controller.initialize();
    await controller.startRecording();
    await controller.stopRecording();

    expect(controller.state.status, CameraCaptureStatus.failed);
    expect(session.disposeCallCount, 1);
    expect(controller.recordingProgress.value.duration, Duration.zero);

    controller.dispose();
  });

  test('disposes camera session after capture', () async {
    final session = FakeYarmyCameraSession();
    final controller = FlutterYarmyCameraController(
      cameraSessionFactory: () async => session,
    );

    await controller.initialize();
    await controller.startRecording();
    await controller.stopRecording();

    expect(controller.state.isCaptured, isTrue);
    expect(session.disposeCallCount, 1);

    controller.dispose();
  });

  test(
    'recording progress updates without camera state notifications',
    () async {
      final session = FakeYarmyCameraSession();
      final controller = FlutterYarmyCameraController(
        cameraSessionFactory: () async => session,
      );

      await controller.initialize();

      var stateNotificationCount = 0;
      var progressNotificationCount = 0;
      controller.addListener(() {
        stateNotificationCount++;
      });
      controller.recordingProgress.addListener(() {
        progressNotificationCount++;
      });

      await controller.startRecording();
      expect(stateNotificationCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(progressNotificationCount, greaterThanOrEqualTo(1));
      expect(controller.recordingProgress.value.duration, isNot(Duration.zero));
      expect(stateNotificationCount, 1);

      await controller.stopRecording();
      controller.dispose();
    },
  );

  test('stop resets recording progress after capture', () async {
    final session = FakeYarmyCameraSession();
    final controller = FlutterYarmyCameraController(
      cameraSessionFactory: () async => session,
    );

    await controller.initialize();
    await controller.startRecording();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(controller.recordingProgress.value.duration, isNot(Duration.zero));

    await controller.stopRecording();

    expect(controller.state.isCaptured, isTrue);
    expect(controller.recordingProgress.value.duration, Duration.zero);

    controller.dispose();
  });

  test('repeated initialize and pause disposes each session once', () async {
    final sessions = <FakeYarmyCameraSession>[];
    final controller = FlutterYarmyCameraController(
      cameraSessionFactory: () async {
        final session = FakeYarmyCameraSession();
        sessions.add(session);
        return session;
      },
    );

    await controller.initialize();
    await controller.pause();
    await controller.initialize();
    await controller.pause();

    expect(sessions, hasLength(2));
    expect(sessions.map((session) => session.disposeCallCount), [1, 1]);

    controller.dispose();
  });

  test(
    'pause captures recording when start finishes after pause begins',
    () async {
      final session = FakeYarmyCameraSession(startCompleter: Completer<void>());
      final controller = FlutterYarmyCameraController(
        cameraSessionFactory: () async => session,
      );

      await controller.initialize();
      final startFuture = controller.startRecording();
      await Future<void>.delayed(Duration.zero);

      final pauseFuture = controller.pause();
      await Future<void>.delayed(Duration.zero);

      expect(session.stopRecordingCallCount, 0);
      expect(session.disposeCallCount, 0);

      session.startCompleter!.complete();
      await Future.wait([startFuture, pauseFuture]);

      expect(session.stopRecordingCallCount, 1);
      expect(session.disposeCallCount, 1);
      expect(controller.state.isCaptured, isTrue);

      controller.dispose();
    },
  );
}

const _fakeCamera = CameraDescription(
  name: '0',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

final class FakeYarmyCameraSession implements YarmyCameraSession {
  FakeYarmyCameraSession({
    this.initializeError,
    this.startCompleter,
    this.stopCompleter,
    this.stopError,
  });

  final Object? initializeError;
  final Completer<void>? startCompleter;
  final Completer<String>? stopCompleter;
  final Object? stopError;

  @override
  bool isInitialized = true;

  @override
  bool isRecordingVideo = false;

  int disposeCallCount = 0;
  int initializeCallCount = 0;
  int startRecordingCallCount = 0;
  int stopRecordingCallCount = 0;
  bool isDisposed = false;

  @override
  Future<void> initialize() async {
    initializeCallCount++;
    final error = initializeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> prepareForVideoRecording() async {}

  @override
  Future<void> startVideoRecording() async {
    startRecordingCallCount++;
    if (startCompleter != null) {
      await startCompleter!.future;
    }
    if (isDisposed) {
      throw StateError('Cannot start a disposed session.');
    }
    isRecordingVideo = true;
  }

  @override
  Future<String> stopVideoRecording() async {
    stopRecordingCallCount++;
    final error = stopError;
    if (error != null) {
      throw error;
    }

    if (stopCompleter != null) {
      final path = await stopCompleter!.future;
      isRecordingVideo = false;
      return path;
    }

    isRecordingVideo = false;
    return 'local/story.mp4';
  }

  @override
  Widget buildPreview(BuildContext context) {
    return const SizedBox.shrink();
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
    disposeCallCount++;
  }
}
