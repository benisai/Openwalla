import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/reboot_countdown_screen.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class ResetRouterScreen extends ConsumerStatefulWidget {
  const ResetRouterScreen({super.key});

  @override
  ConsumerState<ResetRouterScreen> createState() => _ResetRouterScreenState();
}

class _ResetRouterScreenState extends ConsumerState<ResetRouterScreen> {
  bool _resetting = false;

  Future<void> _reset() async {
    final colors = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Router?'),
        content: const Text(
          'This permanently erases custom settings, passwords, and installed packages, then restores the firmware defaults. The router will restart automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset Router'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resetting = true);
    final started = await ref
        .read(appStateProvider)
        .factoryReset(context: context);
    if (!mounted) return;
    setState(() => _resetting = false);
    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Router reset could not be started.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const RebootCountdownDialog(
        duration: 120,
        maxAttempts: 1,
        returnToLoginAfterRecovery: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const LuciAppBar(title: 'Reset Router', showBack: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.error.withValues(alpha: 0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 42,
                  color: colors.error,
                ),
                const SizedBox(height: 14),
                Text(
                  'Restore Firmware Defaults',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'All router configuration, passwords, and installed packages will be removed. Create a router configuration backup first if you may need these settings again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  ),
                  onPressed: _resetting ? null : _reset,
                  icon: _resetting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_forever_outlined),
                  label: Text(_resetting ? 'Starting Reset' : 'Reset Router'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
