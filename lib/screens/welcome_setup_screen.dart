import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/dashboard_preferences.dart';
import 'package:openwalla/widgets/ssh_console_sheet.dart';

class WelcomeSetupScreen extends ConsumerStatefulWidget {
  const WelcomeSetupScreen({super.key});

  @override
  ConsumerState<WelcomeSetupScreen> createState() => _WelcomeSetupScreenState();
}

class _WelcomeSetupScreenState extends ConsumerState<WelcomeSetupScreen> {
  bool _installing = false;
  bool _complete = false;
  String? _error;

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _error = null;
    });

    final console = SshConsoleController(
      initialOutput:
          'Connecting to the router over SSH...\nInstalling core Openwalla components...',
      running: true,
    );
    unawaited(
      showSshConsoleSheet(
        context: context,
        controller: console,
        title: 'Openwalla Setup',
      ).whenComplete(console.dispose),
    );

    try {
      final output = StringBuffer();
      final appState = ref.read(appStateProvider);
      final result = await appState.installOpenwallaSetupFeatures(
        const ['monitoring'],
        onOutput: (chunk) {
          output.write(chunk);
          console.setOutput(output.toString().trimRight());
        },
      );
      console.setOutput(
        result.trim().isEmpty ? 'Openwalla setup complete.' : result.trim(),
      );
      await appState.saveDashboardPreferences(
        appState.dashboardPreferences.copyWith(
          showNetworkPerformanceCard: true,
          showStatisticsTab: true,
          flowMode: DashboardFlowMode.detailed,
        ),
      );
      await appState.markWelcomeSetupSeen();
      if (!mounted) return;
      setState(() {
        _installing = false;
        _complete = true;
      });
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF20CF70),
            size: 44,
          ),
          title: const Text('Setup complete'),
          content: const Text(
            'The core Openwalla components are installed and the router is ready.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      console.complete();
    } catch (error) {
      console.setOutput('Setup failed.\n\n$error');
      console.complete();
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _continue({bool remember = false}) async {
    if (remember) {
      await ref.read(appStateProvider).markWelcomeSetupSeen();
    }
    if (!mounted) return;
    unawaited(Navigator.of(context).pushReplacementNamed('/'));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    Image.asset(
                      'assets/branding/openwalla-mark.png',
                      width: 88,
                      height: 88,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _complete ? 'Router is ready' : 'Welcome to Openwalla',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _complete
                          ? 'The core Openwalla components were installed successfully.'
                          : 'Openwalla needs a small set of components on your router before monitoring and device features can work.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: const Column(
                        children: [
                          _SetupFeature(
                            icon: Icons.monitor_heart_outlined,
                            title: 'Network monitoring',
                            subtitle: 'Latency, outages, and Ethernet events',
                          ),
                          Divider(height: 28),
                          _SetupFeature(
                            icon: Icons.devices_other_rounded,
                            title: 'Device inventory',
                            subtitle: 'Connected devices and activity data',
                          ),
                          Divider(height: 28),
                          _SetupFeature(
                            icon: Icons.storage_rounded,
                            title: 'Persistent app data',
                            subtitle:
                                'Keeps Openwalla history across router restarts',
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colors.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Setup could not finish. Check the SSH output and try again.',
                          style: TextStyle(color: colors.onErrorContainer),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _installing
                            ? null
                            : _complete
                            ? () => _continue()
                            : _install,
                        icon: _installing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _complete
                                    ? Icons.arrow_forward_rounded
                                    : Icons.download_rounded,
                              ),
                        label: Text(
                          _installing
                              ? 'Installing'
                              : _complete
                              ? 'Continue'
                              : 'Set Up Router',
                        ),
                      ),
                    ),
                    if (!_complete)
                      TextButton(
                        onPressed: _installing
                            ? null
                            : () => _continue(remember: true),
                        child: const Text('Set up later'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SetupFeature extends StatelessWidget {
  const _SetupFeature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: colors.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: colors.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
