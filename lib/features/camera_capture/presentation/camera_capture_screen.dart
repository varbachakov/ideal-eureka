import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/foundation.dart';
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
        if (!_controller.state.isCaptured) {
          _controller.initialize();
        }
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
            child: state.hasCameraPreview
                ? _LiveCameraPreview(controller: _controller)
                : const _CameraLoadingBackdrop(),
          ),
          Positioned.fill(
            child: SafeArea(
              child: CameraCaptureOverlay(
                state: state,
                recordingProgress: _controller.recordingProgress,
                onRetry: _controller.initialize,
                onStartRecording: _controller.startRecording,
                onStopRecording: _controller.stopRecording,
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
    return RepaintBoundary(
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: SizedBox.expand(child: controller.buildPreview(context)),
        ),
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
    required this.recordingProgress,
    required this.onRetry,
    required this.onStartRecording,
    required this.onStopRecording,
  });

  final CameraCaptureState state;
  final ValueListenable<CameraRecordingProgress> recordingProgress;
  final VoidCallback onRetry;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;

  @override
  Widget build(BuildContext context) {
    final shouldShowPanel =
        !state.hasCameraPreview || state.status == CameraCaptureStatus.captured;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CameraTopBar(state: state, recordingProgress: recordingProgress),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: shouldShowPanel
                    ? CameraStatusPanel(state: state, onRetry: onRetry)
                          .animate()
                          .fadeIn(duration: 220.ms)
                          .moveY(begin: 8, end: 0, duration: 220.ms)
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          CameraBottomControls(
            state: state,
            recordingProgress: recordingProgress,
            onStartRecording: onStartRecording,
            onStopRecording: onStopRecording,
          ),
        ],
      ),
    );
  }
}

class _CameraTopBar extends StatelessWidget {
  const _CameraTopBar({required this.state, required this.recordingProgress});

  final CameraCaptureState state;
  final ValueListenable<CameraRecordingProgress> recordingProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Text(
          'Ярми',
          style: theme.textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        AnimatedSwitcher(
          duration: 180.ms,
          child: state.isRecording
              ? _RecordingTimerPill(
                  key: const ValueKey('recording-timer'),
                  recordingProgress: recordingProgress,
                )
              : const _StoryModePill(key: ValueKey('story-mode')),
        ),
      ],
    );
  }
}

class _StoryModePill extends StatelessWidget {
  const _StoryModePill({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Настоящая история',
        style: theme.textTheme.labelMedium?.copyWith(color: Colors.white),
      ),
    );
  }
}

class _RecordingTimerPill extends StatelessWidget {
  const _RecordingTimerPill({super.key, required this.recordingProgress});

  final ValueListenable<CameraRecordingProgress> recordingProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE5484D),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _RecordingPulseDot(),
          const SizedBox(width: 8),
          ValueListenableBuilder<CameraRecordingProgress>(
            valueListenable: recordingProgress,
            builder: (context, progress, _) {
              return Text(
                _formatDuration(progress.duration),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RecordingPulseDot extends StatelessWidget {
  const _RecordingPulseDot();

  @override
  Widget build(BuildContext context) {
    return Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
        )
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .fade(begin: 0.35, end: 1, duration: 520.ms);
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
      CameraCaptureStatus.recording => Icons.fiber_manual_record,
      CameraCaptureStatus.captured => Icons.check_circle_outline,
      CameraCaptureStatus.permissionDenied => Icons.no_photography_outlined,
      CameraCaptureStatus.unavailable => Icons.videocam_off_outlined,
      CameraCaptureStatus.failed => Icons.error_outline,
    };
  }
}

class CameraBottomControls extends StatelessWidget {
  const CameraBottomControls({
    super.key,
    required this.state,
    required this.recordingProgress,
    required this.onStartRecording,
    required this.onStopRecording,
  });

  final CameraCaptureState state;
  final ValueListenable<CameraRecordingProgress> recordingProgress;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = state.canRecord || state.isRecording;

    return Column(
      children: [
        Text(
          _labelForState(state),
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.74),
          ),
        ),
        const SizedBox(height: 14),
        ValueListenableBuilder<CameraRecordingProgress>(
          valueListenable: recordingProgress,
          builder: (context, progress, _) {
            return RecordButton(
              isRecording: state.isRecording,
              recordingProgress: progress,
              isEnabled: isEnabled,
              semanticsLabel: _recordButtonSemanticsLabel(state),
              onPressStart: onStartRecording,
              onPressEnd: onStopRecording,
            );
          },
        ),
      ],
    );
  }

  String _labelForState(CameraCaptureState state) {
    return switch (state.status) {
      CameraCaptureStatus.recording => 'Отпустите, чтобы остановить запись',
      CameraCaptureStatus.captured => 'Видео снято. Предпросмотр будет дальше',
      CameraCaptureStatus.ready => 'Удерживайте, чтобы снять историю',
      _ => 'Камера пока недоступна',
    };
  }

  String _recordButtonSemanticsLabel(CameraCaptureState state) {
    return switch (state.status) {
      CameraCaptureStatus.recording => 'Остановить запись',
      CameraCaptureStatus.captured => 'Видео уже снято',
      CameraCaptureStatus.ready => 'Начать запись',
      _ => 'Запись недоступна',
    };
  }
}

class RecordButton extends StatelessWidget {
  const RecordButton({
    super.key,
    required this.isRecording,
    required this.recordingProgress,
    required this.isEnabled,
    required this.semanticsLabel,
    required this.onPressStart,
    required this.onPressEnd,
  });

  final bool isRecording;
  final CameraRecordingProgress recordingProgress;
  final bool isEnabled;
  final String semanticsLabel;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;

  @override
  Widget build(BuildContext context) {
    final progressTarget = isRecording
        ? _projectedProgressTarget(recordingProgress)
        : 0.0;
    final progressAnimationDuration = isRecording
        ? _progressAnimationDuration(recordingProgress)
        : 120.ms;

    return Center(
      child: Semantics(
        button: true,
        enabled: isEnabled,
        label: semanticsLabel,
        onTap: isEnabled ? (isRecording ? onPressEnd : onPressStart) : null,
        child:
            Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: isEnabled
                      ? (_) {
                          if (!isRecording) {
                            onPressStart();
                          }
                        }
                      : null,
                  onPointerUp: isEnabled ? (_) => onPressEnd() : null,
                  onPointerCancel: isEnabled ? (_) => onPressEnd() : null,
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: progressTarget),
                          duration: progressAnimationDuration,
                          curve: Curves.linear,
                          builder: (context, animatedProgress, _) {
                            return ExcludeSemantics(
                              child: SizedBox(
                                width: 96,
                                height: 96,
                                child: CircularProgressIndicator(
                                  value: animatedProgress,
                                  strokeWidth: 4,
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.86,
                                  ),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        Color(0xFFE5484D),
                                      ),
                                ),
                              ),
                            );
                          },
                        ),
                        Container(
                          width: 78,
                          height: 78,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.24),
                          ),
                          child: Center(
                            child: AnimatedContainer(
                              duration: 160.ms,
                              width: isRecording ? 28 : 56,
                              height: isRecording ? 28 : 56,
                              decoration: BoxDecoration(
                                color: isEnabled
                                    ? const Color(0xFFE5484D)
                                    : Colors.white.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(
                                  isRecording ? 8 : 999,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .animate(target: isRecording ? 1 : 0)
                .scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.06, 1.06),
                  duration: 420.ms,
                ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

double _projectedProgressTarget(CameraRecordingProgress progress) {
  final maxDuration = progress.maxDuration;
  if (maxDuration.inMilliseconds <= 0) {
    return 0;
  }

  final projectedDuration = progress.duration + const Duration(seconds: 1);
  final cappedDuration = projectedDuration > maxDuration
      ? maxDuration
      : projectedDuration;

  return CameraRecordingProgress(
    duration: cappedDuration,
    maxDuration: maxDuration,
  ).fraction;
}

Duration _progressAnimationDuration(CameraRecordingProgress progress) {
  final remainingDuration = progress.maxDuration - progress.duration;
  if (remainingDuration <= Duration.zero) {
    return Duration.zero;
  }

  const tickDuration = Duration(seconds: 1);
  return remainingDuration < tickDuration ? remainingDuration : tickDuration;
}
