import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum OpenwallaToastType { loading, success, error, warning, info }

class OpenwallaToast {
  OpenwallaToast._();

  static final Map<String, OverlayEntry> _entries = {};

  static void showLoading(
    BuildContext context, {
    required String key,
    required String message,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      key: key,
      message: message,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
      type: OpenwallaToastType.loading,
      duration: const Duration(seconds: 45),
    );
  }

  static void showSuccess(
    BuildContext context, {
    required String key,
    required String message,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(
      context,
      key: key,
      message: message,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
      type: OpenwallaToastType.success,
      duration: duration,
    );
  }

  static void showError(
    BuildContext context, {
    required String key,
    required String message,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 6),
  }) {
    _show(
      context,
      key: key,
      message: message,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
      type: OpenwallaToastType.error,
      duration: duration,
    );
  }

  static void showWarning(
    BuildContext context, {
    required String key,
    required String message,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 5),
  }) {
    _show(
      context,
      key: key,
      message: message,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
      type: OpenwallaToastType.warning,
      duration: duration,
    );
  }

  static void showInfo(
    BuildContext context, {
    required String key,
    required String message,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(
      context,
      key: key,
      message: message,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
      type: OpenwallaToastType.info,
      duration: duration,
    );
  }

  static void _show(
    BuildContext context, {
    required String key,
    required String message,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
    required OpenwallaToastType type,
    required Duration duration,
  }) {
    _remove(key);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _OpenwallaToastCard(
        message: message,
        subtitle: subtitle,
        actionLabel: actionLabel,
        onAction: onAction,
        type: type,
        duration: duration,
        onDismiss: () {
          if (_entries[key] == entry) _remove(key);
        },
      ),
    );
    _entries[key] = entry;
    overlay.insert(entry);
  }

  static void _remove(String key) {
    final entry = _entries.remove(key);
    if (entry?.mounted == true) entry!.remove();
  }
}

class _OpenwallaToastCard extends StatefulWidget {
  const _OpenwallaToastCard({
    required this.message,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    required this.type,
    required this.duration,
    required this.onDismiss,
  });

  final String message;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final OpenwallaToastType type;
  final Duration duration;
  final VoidCallback onDismiss;

  @override
  State<_OpenwallaToastCard> createState() => _OpenwallaToastCardState();
}

class _OpenwallaToastCardState extends State<_OpenwallaToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    if (widget.type != OpenwallaToastType.loading) {
      _progressController.reverse(from: 1);
    }
    switch (widget.type) {
      case OpenwallaToastType.error:
        HapticFeedback.heavyImpact();
        break;
      case OpenwallaToastType.warning:
        HapticFeedback.mediumImpact();
        break;
      case OpenwallaToastType.loading:
      case OpenwallaToastType.success:
      case OpenwallaToastType.info:
        HapticFeedback.lightImpact();
        break;
    }
    _dismissTimer = Timer(widget.duration, widget.onDismiss);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = switch (widget.type) {
      OpenwallaToastType.loading => colorScheme.primary,
      OpenwallaToastType.success => const Color(0xFF22C55E),
      OpenwallaToastType.error => colorScheme.error,
      OpenwallaToastType.warning => const Color(0xFFF59E0B),
      OpenwallaToastType.info => const Color(0xFF38BDF8),
    };
    final icon = switch (widget.type) {
      OpenwallaToastType.loading => null,
      OpenwallaToastType.success => Icons.check_rounded,
      OpenwallaToastType.error => Icons.error_outline_rounded,
      OpenwallaToastType.warning => Icons.warning_amber_rounded,
      OpenwallaToastType.info => Icons.info_outline_rounded,
    };

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, -12 * (1 - value)),
                child: child,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.48)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                              child: icon == null
                                  ? SizedBox(
                                      width: 17,
                                      height: 17,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: accent,
                                      ),
                                    )
                                  : Icon(icon, size: 19, color: accent),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.message,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurface,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (widget.subtitle?.trim().isNotEmpty ==
                                      true) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.subtitle!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (widget.actionLabel?.trim().isNotEmpty == true &&
                                widget.onAction != null)
                              TextButton(
                                onPressed: () {
                                  widget.onAction!();
                                  widget.onDismiss();
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: accent,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                child: Text(widget.actionLabel!),
                              ),
                            IconButton(
                              tooltip: 'Dismiss',
                              onPressed: widget.onDismiss,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.type != OpenwallaToastType.loading)
                        AnimatedBuilder(
                          animation: _progressController,
                          builder: (context, child) => LinearProgressIndicator(
                            value: _progressController.value,
                            minHeight: 3,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(accent),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
