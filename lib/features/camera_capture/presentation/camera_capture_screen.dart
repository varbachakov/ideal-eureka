import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/material.dart';

import '../data/flutter_yarmy_camera_controller.dart';
import '../domain/camera_capture_state.dart';
import '../domain/yarmy_camera_controller.dart';

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key, this.controller});

  final YarmyCameraController? controller;

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  late final YarmyCameraController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? FlutterYarmyCameraController();
    _controller.addListener(_handleCameraStateChanged);
    _controller.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _controller.initialize();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_handleCameraStateChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleCameraStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: state.isReady
                ? _LiveCameraPreview(controller: _controller)
                : const _CameraLoadingBackdrop(),
          ),
          Positioned.fill(
            child: SafeArea(
              child: CameraCaptureOverlay(
                state: state,
                onRetry: _controller.initialize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveCameraPreview extends StatelessWidget {
  const _LiveCameraPreview({required this.controller});

  final YarmyCameraController controller;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: SizedBox.expand(child: controller.buildPreview(context)),
      ),
    );
  }
}

class _CameraLoadingBackdrop extends StatelessWidget {
  const _CameraLoadingBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF222833), Color(0xFF101216)],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

class CameraCaptureOverlay extends StatelessWidget {
  const CameraCaptureOverlay({
    super.key,
    required this.state,
    required this.onRetry,
  });

  final CameraCaptureState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CameraTopBar(),
          const Spacer(),
          if (!state.isReady)
            CameraStatusPanel(state: state, onRetry: onRetry)
                .animate()
                .fadeIn(duration: 220.ms)
                .moveY(begin: 8, end: 0, duration: 220.ms),
          const Spacer(),
          const _CameraBottomControls(),
        ],
      ),
    );
  }
}

class _CameraTopBar extends StatelessWidget {
  const _CameraTopBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Text(
          'Yarmy',
          style: theme.textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Настоящая история',
            style: theme.textTheme.labelMedium?.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class CameraStatusPanel extends StatelessWidget {
  const CameraStatusPanel({
    super.key,
    required this.state,
    required this.onRetry,
  });

  final CameraCaptureState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconForStatus(state.status),
              size: 52,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              state.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              state.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.76),
              ),
            ),
            if (state.canRetry) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onRetry, child: const Text('Повторить')),
            ],
          ],
        ),
      ),
    );
  }

  IconData _iconForStatus(CameraCaptureStatus status) {
    return switch (status) {
      CameraCaptureStatus.initializing => Icons.videocam_outlined,
      CameraCaptureStatus.ready => Icons.videocam,
      CameraCaptureStatus.permissionDenied => Icons.no_photography_outlined,
      CameraCaptureStatus.unavailable => Icons.videocam_off_outlined,
      CameraCaptureStatus.failed => Icons.error_outline,
    };
  }
}

class _CameraBottomControls extends StatelessWidget {
  const _CameraBottomControls();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          'Запись появится на следующем этапе',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.74),
          ),
        ),
        const SizedBox(height: 14),
        const _RecordButtonPlaceholder(),
      ],
    );
  }
}

class _RecordButtonPlaceholder extends StatelessWidget {
  const _RecordButtonPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: 'Кнопка записи будет доступна позже',
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.86),
              width: 4,
            ),
            color: Colors.black.withValues(alpha: 0.2),
          ),
          child: Center(
            child: Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE5484D),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
