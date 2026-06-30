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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.initialize();
      }
    });
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

class CameraCaptureOverlay extends StatefulWidget {
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
  State<CameraCaptureOverlay> createState() => _CameraCaptureOverlayState();
}

class _CameraCaptureOverlayState extends State<CameraCaptureOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _frameTicker;
  late final ValueNotifier<CameraRecordingProgress> _frameProgress;

  @override
  void initState() {
    super.initState();
    _frameTicker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _frameTicker.addListener(_handleFrameTick);
    _frameProgress = ValueNotifier(
      _currentFrameProgress(widget.recordingProgress.value),
    );
    widget.recordingProgress.addListener(_handleRecordingProgressChanged);
    _syncFrameTicker();
  }

  @override
  void didUpdateWidget(covariant CameraCaptureOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recordingProgress != widget.recordingProgress) {
      oldWidget.recordingProgress.removeListener(
        _handleRecordingProgressChanged,
      );
      widget.recordingProgress.addListener(_handleRecordingProgressChanged);
    }
    _syncFrameTicker();
    _updateFrameProgress();
  }

  @override
  void dispose() {
    widget.recordingProgress.removeListener(_handleRecordingProgressChanged);
    _frameTicker.dispose();
    _frameProgress.dispose();
    super.dispose();
  }

  void _handleRecordingProgressChanged() {
    _syncFrameTicker();
    _updateFrameProgress();
  }

  void _handleFrameTick() {
    _updateFrameProgress();
  }

  void _syncFrameTicker() {
    final shouldTick =
        widget.state.isRecording &&
        widget.recordingProgress.value.isFrameSynced;

    if (shouldTick && !_frameTicker.isAnimating) {
      _frameTicker.repeat();
      return;
    }

    if (!shouldTick && _frameTicker.isAnimating) {
      _frameTicker.stop();
    }
  }

  void _updateFrameProgress() {
    _frameProgress.value = _currentFrameProgress(
      widget.recordingProgress.value,
    );
  }

  CameraRecordingProgress _currentFrameProgress(
    CameraRecordingProgress progress,
  ) {
    return widget.state.isRecording && progress.isFrameSynced
        ? progress.snapshot()
        : progress;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final shouldShowPanel =
        !state.hasCameraPreview || state.status == CameraCaptureStatus.captured;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RecordingTimerSlot(
            isRecording: state.isRecording,
            progress: _frameProgress,
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: shouldShowPanel
                    ? CameraStatusPanel(state: state, onRetry: widget.onRetry)
                          .animate()
                          .fadeIn(duration: 220.ms)
                          .moveY(begin: 8, end: 0, duration: 220.ms)
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          CameraBottomControls(
            state: state,
            recordingProgress: _frameProgress,
            onStartRecording: widget.onStartRecording,
            onStopRecording: widget.onStopRecording,
          ),
        ],
      ),
    );
  }
}

class _RecordingTimerSlot extends StatelessWidget {
  const _RecordingTimerSlot({
    required this.isRecording,
    required this.progress,
  });

  final bool isRecording;
  final ValueListenable<CameraRecordingProgress> progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Center(
        child: isRecording
            ? ValueListenableBuilder<CameraRecordingProgress>(
                valueListenable: progress,
                builder: (context, progress, _) {
                  return _RecordingTimerBadge(progress: progress);
                },
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _RecordingTimerBadge extends StatelessWidget {
  const _RecordingTimerBadge({required this.progress});

  final CameraRecordingProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE5484D),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          _formatRecordingDuration(progress.duration),
          style: theme.textTheme.labelLarge?.copyWith(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1,
            letterSpacing: 0,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
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
    final isEnabled = state.canRecord || state.isRecording;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RecordButton(
        isRecording: state.isRecording,
        isCaptured: state.isCaptured,
        recordingProgress: recordingProgress,
        isEnabled: isEnabled,
        semanticsLabel: _recordButtonSemanticsLabel(state),
        onPressStart: onStartRecording,
        onPressEnd: onStopRecording,
      ),
    );
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

class RecordButton extends StatefulWidget {
  const RecordButton({
    super.key,
    required this.isRecording,
    required this.isCaptured,
    required this.recordingProgress,
    required this.isEnabled,
    required this.semanticsLabel,
    required this.onPressStart,
    required this.onPressEnd,
  });

  final bool isRecording;
  final bool isCaptured;
  final ValueListenable<CameraRecordingProgress> recordingProgress;
  final bool isEnabled;
  final String semanticsLabel;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton> {
  static const Duration _pressAnimationDuration = Duration(milliseconds: 300);

  bool _isPressEffectActive = false;
  double? _frozenProgress;

  @override
  void didUpdateWidget(covariant RecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isRecording) {
      _frozenProgress = null;
    }
  }

  void _finishPressEffect() {
    if (!_isPressEffectActive) {
      return;
    }

    setState(() {
      _isPressEffectActive = false;
    });
  }

  void _handlePointerDown(PointerDownEvent _) {
    if (!widget.isEnabled) {
      return;
    }

    setState(() {
      _frozenProgress = null;
      _isPressEffectActive = true;
    });
    if (!widget.isRecording) {
      widget.onPressStart();
    }
  }

  void _handlePointerUp(PointerUpEvent _) {
    if (!widget.isEnabled) {
      return;
    }

    _finishTouch();
    widget.onPressEnd();
  }

  void _handlePointerCancel(PointerCancelEvent _) {
    if (!widget.isEnabled) {
      return;
    }

    _finishTouch();
    widget.onPressEnd();
  }

  void _finishTouch() {
    if (!widget.isRecording) {
      return;
    }

    setState(() {
      _frozenProgress = widget.recordingProgress.value.currentFraction;
    });
  }

  void _handleSemanticTap() {
    if (!widget.isEnabled) {
      return;
    }

    if (widget.isRecording) {
      setState(() {
        _frozenProgress = widget.recordingProgress.value.currentFraction;
      });
      widget.onPressEnd();
      return;
    }

    setState(() {
      _frozenProgress = null;
      _isPressEffectActive = true;
    });
    widget.onPressStart();
  }

  @override
  Widget build(BuildContext context) {
    final isRecordStateActive = widget.isRecording || widget.isCaptured;
    final shouldShowProgress = widget.isRecording || widget.isCaptured;
    const innerButtonSize = 68.0;
    final innerButtonColor = isRecordStateActive
        ? const Color(0xFFE5484D)
        : Colors.white;
    final outerRingColor = Colors.black.withValues(alpha: 0.44);

    return Center(
      child: Semantics(
        button: true,
        enabled: widget.isEnabled,
        label: widget.semanticsLabel,
        onTap: widget.isEnabled ? _handleSemanticTap : null,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: widget.isEnabled ? _handlePointerDown : null,
          onPointerUp: widget.isEnabled ? _handlePointerUp : null,
          onPointerCancel: widget.isEnabled ? _handlePointerCancel : null,
          child: SizedBox(
            width: 104,
            height: 104,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ValueListenableBuilder<CameraRecordingProgress>(
                  valueListenable: widget.recordingProgress,
                  builder: (context, progress, _) {
                    return ExcludeSemantics(
                      child: SizedBox(
                        width: 96,
                        height: 96,
                        child: CircularProgressIndicator(
                          value:
                              _frozenProgress ??
                              (isRecordStateActive
                                  ? progress.currentFraction
                                  : 0.0),
                          strokeWidth: shouldShowProgress ? 5 : 0,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFE5484D),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: outerRingColor,
                  ),
                  child: Center(
                    child: AnimatedScale(
                      scale: _isPressEffectActive ? 0.8 : 1,
                      duration: _pressAnimationDuration,
                      curve: Curves.easeOutCubic,
                      onEnd: _isPressEffectActive ? _finishPressEffect : null,
                      child: AnimatedContainer(
                        key: const ValueKey('record-button-core'),
                        duration: _pressAnimationDuration,
                        curve: Curves.easeOutCubic,
                        width: innerButtonSize,
                        height: innerButtonSize,
                        decoration: BoxDecoration(
                          color: widget.isEnabled || widget.isCaptured
                              ? innerButtonColor
                              : Colors.white.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatRecordingDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
