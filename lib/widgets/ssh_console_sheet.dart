import 'package:flutter/material.dart';

class SshConsoleController {
  final ValueNotifier<String> output;
  final ValueNotifier<bool> isRunning;
  bool _disposed = false;

  SshConsoleController({String initialOutput = '', bool running = false})
    : output = ValueNotifier<String>(initialOutput),
      isRunning = ValueNotifier<bool>(running);

  void append(String chunk) {
    if (_disposed) return;
    output.value = '${output.value}$chunk';
  }

  void setOutput(String value) {
    if (_disposed) return;
    output.value = value;
  }

  void complete() {
    if (_disposed) return;
    isRunning.value = false;
  }

  void dispose() {
    _disposed = true;
    output.dispose();
    isRunning.dispose();
  }
}

Future<void> showSshConsoleSheet({
  required BuildContext context,
  required SshConsoleController controller,
  String title = 'SSH Console',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) =>
        _SshConsoleSheet(controller: controller, title: title),
  );
}

class SshConsolePreview extends StatelessWidget {
  final String output;
  final bool isRunning;

  const SshConsolePreview({
    super.key,
    required this.output,
    required this.isRunning,
  });

  @override
  Widget build(BuildContext context) {
    return _SshConsolePanel(
      title: isRunning ? 'SSH Console Running' : 'SSH Console Output',
      output: output,
      isRunning: isRunning,
      maxHeight: 260,
    );
  }
}

class _SshConsoleSheet extends StatelessWidget {
  final SshConsoleController controller;
  final String title;

  const _SshConsoleSheet({required this.controller, required this.title});

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.78;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ValueListenableBuilder<bool>(
          valueListenable: controller.isRunning,
          builder: (context, isRunning, _) {
            return ValueListenableBuilder<String>(
              valueListenable: controller.output,
              builder: (context, output, _) {
                return PopScope(
                  canPop: !isRunning,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.terminal_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isRunning ? '$title Running' : title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _SshConsolePanel(
                          title: null,
                          output: output,
                          isRunning: isRunning,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: isRunning
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: isRunning
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.close_rounded),
                        label: Text(isRunning ? 'Waiting' : 'Close'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SshConsolePanel extends StatefulWidget {
  final String? title;
  final String output;
  final bool isRunning;
  final double? maxHeight;

  const _SshConsolePanel({
    required this.title,
    required this.output,
    required this.isRunning,
    this.maxHeight,
  });

  @override
  State<_SshConsolePanel> createState() => _SshConsolePanelState();
}

class _SshConsolePanelState extends State<_SshConsolePanel> {
  final _verticalController = ScrollController();
  final _horizontalController = ScrollController();

  @override
  void didUpdateWidget(covariant _SshConsolePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.output == widget.output) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_verticalController.hasClients) return;
      _verticalController.animateTo(
        _verticalController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final console = Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Scrollbar(
        controller: _verticalController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _verticalController,
          scrollDirection: Axis.vertical,
          child: Scrollbar(
            controller: _horizontalController,
            thumbVisibility: true,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                widget.output.trimRight().isEmpty
                    ? 'Waiting for output...'
                    : widget.output,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.title != null) ...[
              Text(
                widget.title!,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
            ],
            if (widget.isRunning) ...[
              LinearProgressIndicator(
                minHeight: 3,
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(height: 10),
            ],
            if (widget.maxHeight == null)
              Expanded(child: console)
            else
              SizedBox(height: widget.maxHeight, child: console),
          ],
        ),
      ),
    );
  }
}
