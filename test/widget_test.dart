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

    expect(find.text('Ярми'), findsOneWidget);
    expect(find.text('Настоящая история'), findsOneWidget);
    expect(find.byKey(FakeYarmyCameraController.previewKey), findsOneWidget);
    expect(find.text('Удерживайте, чтобы снять историю'), findsOneWidget);
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
    final gesture = await tester.startGesture(tester.getCenter(recordButton));
    await tester.pump();

    expect(cameraController.startRecordingCallCount, 1);

    await gesture.up();
    await tester.pump();

    expect(cameraController.stopRecordingCallCount, 1);
  });

  testWidgets('does not restart recording after capture', (tester) async {
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

    expect(find.text('Видео снято. Предпросмотр будет дальше'), findsOneWidget);

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

class FakeYarmyCameraController extends YarmyCameraController {
  FakeYarmyCameraController({CameraCaptureState? state})
    : _state = state ?? const CameraCaptureState.ready();

  static const previewKey = Key('fake-camera-preview');

  final CameraCaptureState _state;
  final ValueNotifier<CameraRecordingProgress> _recordingProgress =
      ValueNotifier(const CameraRecordingProgress());
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

  void updateRecordingProgress(Duration duration) {
    _recordingProgress.value = CameraRecordingProgress(duration: duration);
  }
}
