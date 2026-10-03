import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';

class HideDashboardShortcutButton extends ConsumerWidget {
  final String shortcutId;
  final String shortcutLabel;
  final bool enabled;

  const HideDashboardShortcutButton({
    super.key,
    required this.shortcutId,
    required this.shortcutLabel,
    this.enabled = true,
  });

  Future<void> _hide(BuildContext context, WidgetRef ref) async {
    final shouldHide = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.visibility_off_rounded),
        title: Text('Hide $shortcutLabel Shortcut?'),
        content: Text(
          'The $shortcutLabel shortcut will be removed from the dashboard. You can enable it again from Settings > Dashboard Settings > Shortcut Panel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hide Shortcut'),
          ),
        ],
      ),
    );
    if (shouldHide != true || !context.mounted) return;

    final appState = ref.read(appStateProvider);
    final preferences = appState.dashboardPreferences
        .copyWithShortcutVisibility(shortcutId, visible: false);
    await appState.saveDashboardPreferences(preferences);
    if (!context.mounted) return;
    appState.requestTab(0);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      onPressed: enabled ? () => _hide(context, ref) : null,
      icon: const Icon(Icons.visibility_off_rounded),
      label: Text('Hide $shortcutLabel Shortcut'),
    );
  }
}
