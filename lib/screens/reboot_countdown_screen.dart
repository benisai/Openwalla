import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/design/luci_design_system.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/login_screen.dart';

class RebootCountdownDialog extends ConsumerStatefulWidget {
  const RebootCountdownDialog({
    super.key,
    this.duration = 120,
    this.maxAttempts = 1,
    this.sendRebootCommand = false,
    this.returnToLoginAfterRecovery = false,
  });

  final int duration;
  final int maxAttempts;
  final bool sendRebootCommand;
  final bool returnToLoginAfterRecovery;

  @override
  ConsumerState<RebootCountdownDialog> createState() =>
      _RebootCountdownDialogState();
}

class _RebootCountdownDialogState extends ConsumerState<RebootCountdownDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _attempt = 1;
  bool _checking = false;
  bool _sendingReboot = false;
  bool _sendFailed = false;
  bool _probeInFlight = false;
  Timer? _probeStartTimer;
  Timer? _probeTimer;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: Duration(seconds: widget.duration),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && !_checking) {
            _cancelRecoveryProbes();
            unawaited(_tryReconnect());
          }
        });
    if (widget.sendRebootCommand) {
      unawaited(_sendRebootAndStart());
    } else {
      _startCountdown();
    }
  }

  @override
  void dispose() {
    _cancelRecoveryProbes();
    _controller.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _controller.forward();
    if (widget.returnToLoginAfterRecovery || widget.duration <= 60) return;
    _probeStartTimer = Timer(const Duration(seconds: 60), () {
      unawaited(_probeForRecovery());
      _probeTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        unawaited(_probeForRecovery());
      });
    });
  }

  void _cancelRecoveryProbes() {
    _probeStartTimer?.cancel();
    _probeStartTimer = null;
    _probeTimer?.cancel();
    _probeTimer = null;
  }

  void _restartCountdown() {
    setState(() {
      _checking = false;
      _sendFailed = false;
    });
    _controller
      ..duration = Duration(seconds: widget.duration)
      ..reset()
      ..forward();
    _cancelRecoveryProbes();
    if (!widget.returnToLoginAfterRecovery && widget.duration > 60) {
      _probeStartTimer = Timer(const Duration(seconds: 60), () {
        unawaited(_probeForRecovery());
        _probeTimer = Timer.periodic(const Duration(seconds: 5), (_) {
          unawaited(_probeForRecovery());
        });
      });
    }
  }

  Future<void> _sendRebootAndStart() async {
    setState(() {
      _sendingReboot = true;
      _sendFailed = false;
    });
    final sent = await ref.read(appStateProvider).reboot(context: context);
    if (!mounted) return;
    if (!sent) {
      ref.read(appStateProvider).finishRebootRecovery();
      setState(() {
        _sendingReboot = false;
        _sendFailed = true;
      });
      return;
    }
    setState(() {
      _sendingReboot = false;
    });
    _startCountdown();
  }

  Future<void> _probeForRecovery() async {
    if (!mounted || _probeInFlight || _controller.isCompleted) return;
    _probeInFlight = true;
    setState(() => _checking = true);
    final appState = ref.read(appStateProvider);
    await appState.retryDashboardConnection();
    if (!mounted) return;
    final reconnected =
        appState.dashboardData != null && appState.dashboardError == null;
    if (reconnected) {
      await _completeRecovery();
    } else {
      setState(() => _checking = false);
      if (_controller.isCompleted) {
        _probeInFlight = false;
        await _tryReconnect();
        return;
      }
    }
    _probeInFlight = false;
  }

  Future<void> _completeRecovery() async {
    _cancelRecoveryProbes();
    _controller.stop();
    final appState = ref.read(appStateProvider);
    appState.finishRebootRecovery();
    appState.requestTab(0);
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.pop();
    unawaited(navigator.pushNamedAndRemoveUntil('/', (_) => false));
  }

  Future<void> _tryReconnect() async {
    setState(() {
      _checking = true;
    });

    final appState = ref.read(appStateProvider);
    if (widget.returnToLoginAfterRecovery) {
      if (_attempt < widget.maxAttempts) {
        _attempt++;
        _restartCountdown();
        return;
      }
      await _returnToLogin();
      return;
    }

    await appState.retryDashboardConnection();
    if (!mounted) return;

    final reconnected =
        appState.dashboardData != null && appState.dashboardError == null;
    if (reconnected) {
      await _completeRecovery();
      return;
    }

    if (_attempt < widget.maxAttempts) {
      _attempt++;
      _restartCountdown();
      return;
    }

    await _returnToLogin();
  }

  Future<void> _returnToLogin() async {
    _cancelRecoveryProbes();
    final appState = ref.read(appStateProvider);
    appState.finishRebootRecovery();
    await appState.logout();
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.pop();
    unawaited(
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      ),
    );
  }

  String _formatRemaining(double controllerValue) {
    final remaining = (widget.duration * (1 - controllerValue)).clamp(
      0.0,
      widget.duration.toDouble(),
    );
    final minutes = remaining ~/ 60;
    final seconds = remaining.floor() % 60;
    final tenths = ((remaining - remaining.floor()) * 10).ceil().clamp(0, 9);
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.$tenths';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog.fullscreen(
      backgroundColor: Colors.black.withValues(alpha: 0.62),
      child: Center(
        child: Container(
          width: math.min(MediaQuery.sizeOf(context).width - 36, 380),
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.32),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final progress = (_sendingReboot || _sendFailed)
                  ? 1.0
                  : _controller.value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 236,
                    height: 236,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size.square(236),
                          painter: _CountdownRingPainter(
                            progress: progress,
                            activeColor: colorScheme.primary,
                            tickColor: colorScheme.primary.withValues(
                              alpha: 0.45,
                            ),
                            trackColor: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.58),
                          ),
                        ),
                        if (_checking || _sendingReboot || _sendFailed)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_sendFailed)
                                SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 4,
                                    color: colorScheme.primary,
                                  ),
                                )
                              else
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 48,
                                  color: colorScheme.error,
                                ),
                              const SizedBox(height: 14),
                              Text(
                                _sendFailed
                                    ? 'Failed'
                                    : _sendingReboot
                                    ? 'Starting'
                                    : 'Checking',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          )
                        else
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatRemaining(_controller.value),
                                style: theme.textTheme.displaySmall?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Rebooting',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: _CountdownStat(
                          label: 'Recovery',
                          value: widget.maxAttempts == 1
                              ? '1 pass'
                              : '$_attempt / ${widget.maxAttempts}',
                        ),
                      ),
                      Expanded(
                        child: _CountdownStat(
                          label: 'Progress',
                          value: _sendingReboot
                              ? 'Ready'
                              : '${(progress * 100).round()}%',
                        ),
                      ),
                      Expanded(
                        child: _CountdownStat(
                          label: 'Remaining',
                          value: _sendFailed
                              ? '-'
                              : _sendingReboot
                              ? 'Starting'
                              : _checking
                              ? 'Checking'
                              : '${(widget.duration * (1 - progress)).ceil()}s',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _sendFailed
                        ? 'Openwalla could not send the reboot command. You can close this and try again.'
                        : _sendingReboot
                        ? 'Sending reboot command to the router.'
                        : _checking
                        ? 'The router may be ready. Trying to reconnect now.'
                        : widget.returnToLoginAfterRecovery
                        ? 'Openwalla will return to login when the reset timer finishes.'
                        : _controller.value >= (60 / widget.duration)
                        ? 'Openwalla checks the router every 5 seconds and will continue as soon as it is ready.'
                        : 'Openwalla will begin checking the router after 60 seconds.',
                    textAlign: TextAlign.center,
                    style: LuciTextStyles.cardSubtitle(
                      context,
                    ).copyWith(height: 1.35),
                  ),
                  if (_sendFailed) ...[
                    const SizedBox(height: 18),
                    OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context, rootNavigator: true).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CountdownStat extends StatelessWidget {
  final String label;
  final String value;

  const _CountdownStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color tickColor;
  final Color trackColor;

  const _CountdownRingPainter({
    required this.progress,
    required this.activeColor,
    required this.tickColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const startAngle = -math.pi / 2;
    final remainingProgress = (1 - progress).clamp(0.0, 1.0);
    final sweepAngle = -math.pi * 2 * remainingProgress;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    final tickPaint = Paint()
      ..color = tickColor
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 60; i++) {
      final angle = startAngle + (i / 60) * math.pi * 2;
      final isMajor = i % 5 == 0;
      final inner = radius - (isMajor ? 19 : 12);
      final outer = radius - 2;
      final p1 = center + Offset(math.cos(angle), math.sin(angle)) * inner;
      final p2 = center + Offset(math.cos(angle), math.sin(angle)) * outer;
      canvas.drawLine(p1, p2, tickPaint);
    }

    final activePaint = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + math.pi * 2,
        colors: [activeColor.withValues(alpha: 0.72), activeColor],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, startAngle, sweepAngle, false, activePaint);
  }

  @override
  bool shouldRepaint(covariant _CountdownRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.tickColor != tickColor ||
        oldDelegate.trackColor != trackColor;
  }
}
