import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_yarmy/app/yarmy_app.dart';
import 'package:mobile_yarmy/features/camera_capture/domain/camera_capture_state.dart';
import 'package:mobile_yarmy/features/camera_capture/domain/yarmy_camera_controller.dart';
import 'package:mobile_yarmy/features/camera_capture/presentation/camera_capture_screen.dart';

void main() {
  testWidgets('shows camera preview shell as the first screen', (tester) async {
    final cameraController = FakeYarmyCameraController();

    await tester.pumpWidget(
      YarmyApp(home: CameraCaptureScreen(controller: cameraController)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ярми'), findsNothing);
    expect(find.text('Настоящая история'), findsNothing);
    expect(find.byKey(FakeYarmyCameraController.previewKey), findsOneWidget);
    expect(find.bySemanticsLabel('Начать запись'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Начать запись')),
      matchesSemantics(
        label: 'Начать запись',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('records while the record button is pressed', (tester) async {
    final cameraController = FakeYarmyCameraController();

    await tester.pumpWidget(
      YarmyApp(home: CameraCaptureScreen(controller: cameraController)),
    );
    await tester.pumpAndSettle();

    final recordButton = find.bySemanticsLabel('Начать запись');
    final recordButtonCore = find.byKey(const ValueKey('record-button-core'));

    expect(tester.getSize(recordButtonCore), const Size(68, 68));
    expect(_recordButtonCoreColor(tester), Colors.white);

    final gesture = await tester.startGesture(tester.getCenter(recordButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));

    expect(cameraController.startRecordingCallCount, 1);
    expect(tester.getSize(recordButtonCore), const Size(68, 68));
    expect(_recordButtonCoreColor(tester), Colors.white);
    final pressScale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(pressScale.scale, 0.8);
    expect(pressScale.duration, const Duration(milliseconds: 300));

    cameraController.updateState(const CameraCaptureState.recording());
    await tester.pump();

    final recordingCore = tester.widget<AnimatedContainer>(recordButtonCore);
    expect(_recordButtonCoreColor(tester), const Color(0xFFE5484D));
    expect(recordingCore.duration, const Duration(milliseconds: 300));

    await gesture.up();
    await tester.pump();

    expect(cameraController.stopRecordingCallCount, 1);
    expect(tester.getSize(recordButtonCore), const Size(68, 68));
  });

  testWidgets('freezes progress ring when recording stop is requested', (
    tester,
  ) async {
    final cameraController = FakeYarmyCameraController(
      state: const CameraCaptureState.recording(),
      recordingProgress: const CameraRecordingProgress(
        duration: Duration(seconds: 10),
      ),
    );

    await tester.pumpWidget(
      YarmyApp(home: CameraCaptureScreen(controller: cameraController)),
    );
    await tester.pumpAndSettle();

    final recordButton = find.bySemanticsLabel('Остановить запись');
    final gesture = await tester.startGesture(tester.getCenter(recordButton));
    await gesture.up();
    await tester.pump();

    cameraController.updateRecordingProgress(const Duration(seconds: 12));
    await tester.pump();

    final progressIndicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(progressIndicator.value, closeTo(10 / 60, 0.001));
    expect(cameraController.stopRecordingCallCount, 1);

    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('progress ring follows recording clock every frame', (
    tester,
  ) async {
    final clock = FakeCameraRecordingClock(
      elapsed: const Duration(seconds: 12),
    );
    final cameraController = FakeYarmyCameraController(
      state: const CameraCaptureState.recording(),
      recordingProgress: CameraRecordingProgress(clock: clock),
    );

    await tester.pumpWidget(
      YarmyApp(home: CameraCaptureScreen(controller: cameraController)),
    );
    await tester.pump();

    final initialProgress = tester
        .widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        )
        .value;

    clock.elapsed = const Duration(milliseconds: 12500);
    await tester.pump(const Duration(milliseconds: 500));

    final nextProgress = tester
        .widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        )
        .value;

    expect(initialProgress, closeTo(12 / 60, 0.02));
    expect(nextProgress, greaterThan(initialProgress!));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows recording timer at the top center', (tester) async {
    final cameraController = FakeYarmyCameraController(
      state: const CameraCaptureState.recording(),
    );

    await tester.pumpWidget(
      YarmyApp(home: CameraCaptureScreen(controller: cameraController)),
    );
    await tester.pumpAndSettle();

    expect(find.text('00:00'), findsOneWidget);

    cameraController.updateRecordingProgress(const Duration(seconds: 7));
    await tester.pump();

    expect(find.text('00:07'), findsOneWidget);
  });

  testWidgets('does not restart recording after capture', (tester) async {
    final cameraController = FakeYarmyCameraController(
      state: CameraCaptureState.captured(
        video: const CapturedVideo(
          path: 'local/story.mp4',
          duration: Duration(seconds: 8),
        ),
      ),
      recordingProgress: const CameraRecordingProgress(
        duration: Duration(seconds: 8),
      ),
    );

    await tester.pumpWidget(
      YarmyApp(home: CameraCaptureScreen(controller: cameraController)),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Видео уже снято'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Видео уже снято')),
      matchesSemantics(
        label: 'Видео уже снято',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    final progressIndicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(progressIndicator.value, closeTo(8 / 60, 0.001));
    expect(progressIndicator.strokeWidth, 5);
    expect(_recordButtonCoreColor(tester), const Color(0xFFE5484D));

    final recordButton = find.bySemanticsLabel('Видео уже снято');
    final gesture = await tester.startGesture(tester.getCenter(recordButton));
    await gesture.up();
    await tester.pump();

    expect(cameraController.startRecordingCallCount, 0);
  });

  testWidgets('keeps captured state on app resume', (tester) async {
    final cameraController = FakeYarmyCameraController(
      state: CameraCaptureState.captured(
        video: const CapturedVideo(
          path: 'local/story.mp4',
          duration: Duration(seconds: 8),
        ),
      ),
    );

    await tester.pumpWidget(
      YarmyApp(home: CameraCaptureScreen(controller: cameraController)),
    );
    await tester.pumpAndSettle();
    cameraController.initializeCallCount = 0;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(cameraController.initializeCallCount, 0);
  });

  testWidgets('recording progress does not rebuild camera preview', (
    tester,
  ) async {
    final cameraController = FakeYarmyCameraController();

    await tester.pumpWidget(
      YarmyApp(home: CameraCaptureScreen(controller: cameraController)),
    );
    await tester.pumpAndSettle();

    expect(cameraController.buildPreviewCallCount, 1);

    cameraController.updateRecordingProgress(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(cameraController.buildPreviewCallCount, 1);
  });
}

Color? _recordButtonCoreColor(WidgetTester tester) {
  final core = tester.widget<AnimatedContainer>(
    find.byKey(const ValueKey('record-button-core')),
  );
  return (core.decoration as BoxDecoration?)?.color;
}

class FakeYarmyCameraController extends YarmyCameraController {
  FakeYarmyCameraController({
    CameraCaptureState? state,
    CameraRecordingProgress recordingProgress = const CameraRecordingProgress(),
  }) : _state = state ?? const CameraCaptureState.ready(),
       _recordingProgress = ValueNotifier(recordingProgress);

  static const previewKey = Key('fake-camera-preview');

  CameraCaptureState _state;
  final ValueNotifier<CameraRecordingProgress> _recordingProgress;
  int initializeCallCount = 0;
  int pauseCallCount = 0;
  int startRecordingCallCount = 0;
  int stopRecordingCallCount = 0;
  int buildPreviewCallCount = 0;

  @override
  CameraCaptureState get state => _state;

  @override
  ValueListenable<CameraRecordingProgress> get recordingProgress =>
      _recordingProgress;

  @override
  Future<void> initialize() async {
    initializeCallCount++;
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
  }

  @override
  Future<void> startRecording() async {
    startRecordingCallCount++;
  }

  @override
  Future<void> stopRecording() async {
    stopRecordingCallCount++;
  }

  @override
  Widget buildPreview(BuildContext context) {
    buildPreviewCallCount++;
    return const ColoredBox(key: previewKey, color: Colors.black);
  }

  void updateRecordingProgress(
    Duration duration, {
    CameraRecordingClock? clock,
  }) {
    _recordingProgress.value = CameraRecordingProgress(
      duration: duration,
      clock: clock,
    );
  }

  void updateState(CameraCaptureState state) {
    _state = state;
    notifyListeners();
  }
}

final class FakeCameraRecordingClock implements CameraRecordingClock {
  FakeCameraRecordingClock({required this.elapsed, this.isRunning = true});

  @override
  Duration elapsed;

  @override
  bool isRunning;
}
