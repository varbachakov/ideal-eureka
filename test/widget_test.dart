import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_yarmy/app/yarmy_app.dart';
import 'package:mobile_yarmy/features/camera_capture/domain/camera_capture_state.dart';
import 'package:mobile_yarmy/features/camera_capture/domain/yarmy_camera_controller.dart';
import 'package:mobile_yarmy/features/camera_capture/presentation/camera_capture_screen.dart';

void main() {
  testWidgets('shows camera preview shell as the first screen', (tester) async {
    await tester.pumpWidget(
      YarmyApp(
        home: CameraCaptureScreen(controller: FakeYarmyCameraController()),
      ),
    );

    expect(find.text('Yarmy'), findsOneWidget);
    expect(find.text('Настоящая история'), findsOneWidget);
    expect(find.byKey(FakeYarmyCameraController.previewKey), findsOneWidget);
    expect(find.text('Запись появится на следующем этапе'), findsOneWidget);
  });
}

class FakeYarmyCameraController extends YarmyCameraController {
  static const previewKey = Key('fake-camera-preview');

  @override
  CameraCaptureState get state => const CameraCaptureState.ready();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> pause() async {}

  @override
  Widget buildPreview(BuildContext context) {
    return const ColoredBox(key: previewKey, color: Colors.black);
  }
}
