import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/dashboard_preferences.dart';
import 'package:openwalla/screens/router_components_screen.dart';
import 'package:openwalla/screens/ssh_terminal_screen.dart';
import 'package:openwalla/utils/router_setup_commands.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/ssh_console_sheet.dart';

enum _SetupProfile { basic, standard, advanced, everything, custom, remove }

extension on _SetupProfile {
  String get title => switch (this) {
    _SetupProfile.basic => 'Basic Install',
    _SetupProfile.standard => 'Standard Install',
    _SetupProfile.advanced => 'Advanced Install',
    _SetupProfile.custom => 'Custom Install',
    _SetupProfile.everything => 'Everything',
    _SetupProfile.remove => 'Remove Installed Apps',
  };

  String get description => switch (this) {
    _SetupProfile.basic =>
      'Core packages and helpers required for Openwalla to function.',
    _SetupProfile.standard =>
      'Basic plus AdBlock, Parental Controls, Quarantine, Smart Queue, DDNS, and WireGuard.',
    _SetupProfile.advanced =>
      'Basic and Standard plus Policy-Based Routing (PBR).',
    _SetupProfile.custom =>
      'Choose the exact Openwalla components to install or redeploy.',
    _SetupProfile.everything =>
      'All bundled router features, including Netify Detailed Flow.',
    _SetupProfile.remove =>
      'Choose installed Openwalla components to remove from the router.',
  };

  IconData get icon => switch (this) {
    _SetupProfile.basic => Icons.foundation_rounded,
    _SetupProfile.standard => Icons.auto_awesome_rounded,
    _SetupProfile.advanced => Icons.tune_rounded,
    _SetupProfile.custom => Icons.checklist_rounded,
    _SetupProfile.everything => Icons.apps_rounded,
    _SetupProfile.remove => Icons.delete_sweep_outlined,
  };
}

class RouterSetupScreen extends ConsumerStatefulWidget {
  final bool netifyOnly;

  const RouterSetupScreen({super.key, this.netifyOnly = false});

  @override
  ConsumerState<RouterSetupScreen> createState() => _RouterSetupScreenState();
}

class _RouterSetupScreenState extends ConsumerState<RouterSetupScreen> {
  static const _rawSetupBase =
      'https://raw.githubusercontent.com/benisai/openwalla-apk/main/openwrt-setup';

  static const _basicFeatures = ['monitoring'];
  static const _standardFeatures = [
    ..._basicFeatures,
    'adblock',
    'blocking',
    'scheduler',
    'quarantine',
    'qos',
    'ddns',
    'wireguard',
  ];

  int _wizardStep = 0;
  _SetupProfile? _selectedProfile;
  bool _isInstalling = false;
  bool _isUninstalling = false;
  bool _showDetails = false;
  bool _setupComplete = false;
  String? _lastOutput;
  final Set<String> _customInstallFeatures = {};
  final Set<String> _uninstallFeatures = {};

  List<String> get _selectedFeatures {
    if (widget.netifyOnly) return const ['netify'];
    return switch (_selectedProfile) {
      _SetupProfile.basic => _basicFeatures,
      _SetupProfile.standard => _standardFeatures,
      _SetupProfile.advanced => [..._standardFeatures, 'pbr'],
      _SetupProfile.custom =>
        _CustomInstallComponentsCard.items
            .where((item) => _customInstallFeatures.contains(item.feature))
            .map((item) => item.feature)
            .toList(growable: false),
      _SetupProfile.everything => [..._standardFeatures, 'pbr', 'netify'],
      _ => const [],
    };
  }

  String get _setupCommand {
    final features = _selectedFeatures.join(' ');
    final preparation = [
      openwallaInternetPreflightShellBlock,
      'export OPENWALLA_RAW_BASE=$_rawSetupBase',
      'export OPENWALLA_ROOT=/tmp/openwalla-app-setup',
      'fetch() { if command -v wget >/dev/null 2>&1; then wget -qO "\$2" "\$1"; else curl -fsSL "\$1" -o "\$2"; fi; }',
      'cd /tmp',
      'rm -rf "\$OPENWALLA_ROOT"',
      'rm -f setup-openwrt-router.sh',
      'fetch "\$OPENWALLA_RAW_BASE/setup-openwrt-router.sh" "setup-openwrt-router.sh"',
      'chmod 0755 setup-openwrt-router.sh',
    ].join(' && ');
    return '$preparation && { '
        'echo "[openwalla-app] Installer started."; '
        'sh ./setup-openwrt-router.sh --force $features & OPENWALLA_SETUP_PID=\$!; '
        'while kill -0 "\$OPENWALLA_SETUP_PID" 2>/dev/null; do '
        'sleep 15; '
        'if kill -0 "\$OPENWALLA_SETUP_PID" 2>/dev/null; then '
        'echo "[openwalla-app] Installation is still running..."; '
        'fi; '
        'done; '
        'wait "\$OPENWALLA_SETUP_PID"; '
        '}';
  }

  String get _uninstallCommand {
    final features = _uninstallFeatures.join(' ');
    if (features.trim().isEmpty) return '';
    return [
      openwallaInternetPreflightShellBlock,
      'export OPENWALLA_RAW_BASE=$_rawSetupBase',
      'export OPENWALLA_ROOT=/tmp/openwalla-app-setup',
      'fetch() { if command -v wget >/dev/null 2>&1; then wget -qO "\$2" "\$1"; else curl -fsSL "\$1" -o "\$2"; fi; }',
      'cd /tmp',
      'rm -rf "\$OPENWALLA_ROOT"',
      'rm -f setup-openwrt-router.sh',
      'fetch "\$OPENWALLA_RAW_BASE/setup-openwrt-router.sh" "setup-openwrt-router.sh"',
      'chmod 0755 setup-openwrt-router.sh',
      'sh ./setup-openwrt-router.sh uninstall $features',
    ].join(' && ');
  }

  Future<void> _copyCommand() async {
    final command = _setupCommand;
    if (command.isEmpty) {
      _showSnack('Choose at least one setup option first.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: command));
    if (!mounted) return;
    _showSnack('Router setup command copied.');
  }

  Future<void> _runSetup() async {
    final command = _setupCommand;
    if (command.isEmpty) {
      _showSnack('Choose at least one setup option first.');
      return;
    }

    setState(() {
      _isInstalling = true;
      _setupComplete = false;
      _lastOutput =
          'Connecting to router over SSH...\nRunning Openwalla setup command...\n\nConsole output will appear here as the install runs.';
    });
    final console = SshConsoleController(
      initialOutput: _lastOutput!,
      running: true,
    );
    var consoleVisible = false;
    if (mounted) {
      consoleVisible = true;
      unawaited(
        showSshConsoleSheet(
          context: context,
          controller: console,
          title: 'Openwalla Router Setup',
        ).whenComplete(() {
          consoleVisible = false;
          console.dispose();
        }),
      );
    }

    try {
      final appState = ref.read(appStateProvider);
      final outputBuffer = StringBuffer();
      final output = await appState.runRouterSetupCommandViaSsh(
        command,
        onOutput: (chunk) {
          outputBuffer.write(chunk);
          console.setOutput(outputBuffer.toString().trimRight());
          if (!mounted) return;
          setState(() {
            _lastOutput = outputBuffer.toString().trimRight();
          });
        },
      );
      if (!output.contains('[openwalla-setup] Setup complete.')) {
        throw StateError(
          'The SSH command ended before the router confirmed setup completion.',
        );
      }
      await _enableDashboardCardsForInstalledFeatures();
      if (!mounted) return;
      console.setOutput(
        '${output.trimRight()}\n\nRefreshing the router connection...',
      );
      appState.clearStatisticsPreload();
      await appState.retryDashboardConnection(context: context);
      if (!mounted) return;
      setState(() {
        _lastOutput = output.trim().isEmpty
            ? 'Setup finished. The router did not return console output.'
            : output.trim();
        _setupComplete = true;
      });
      console.setOutput(_lastOutput!);
      console.complete();
      if (consoleVisible && mounted) {
        Navigator.of(context).pop();
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
      if (!mounted) return;
      await _showSetupSuccessDialog();
    } catch (e) {
      if (!mounted) return;
      final failureMessage =
          'Router setup did not complete. Review the connection check and installer output below.\n\n$e';
      console.setOutput(failureMessage);
      setState(() {
        _lastOutput = failureMessage;
        _showDetails = true;
        _setupComplete = false;
      });
      _showSnack('Router setup did not complete.');
    } finally {
      console.complete();
      if (mounted) setState(() => _isInstalling = false);
    }
  }

  Future<void> _showSetupSuccessDialog() async {
    final profileName = _selectedProfile?.title ?? 'Router setup';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF20CF70),
            size: 42,
          ),
          title: const Text('Setup Successful'),
          content: Text(
            '$profileName completed successfully. Openwalla is ready to use.',
          ),
          actions: [
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.dashboard_rounded),
              label: const Text('Go to Dashboard'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    ref.read(appStateProvider).requestedTab = 0;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _runUninstall() async {
    final command = _uninstallCommand;
    if (command.isEmpty) {
      _showSnack('Choose at least one component to remove.');
      return;
    }

    setState(() {
      _isUninstalling = true;
      _lastOutput =
          'Connecting to router over SSH...\nRemoving selected Openwalla components...\n\nConsole output will appear here as the uninstall runs.';
    });
    final console = SshConsoleController(
      initialOutput: _lastOutput!,
      running: true,
    );
    if (mounted) {
      unawaited(
        showSshConsoleSheet(
          context: context,
          controller: console,
          title: 'Remove Openwalla Components',
        ).whenComplete(console.dispose),
      );
    }

    try {
      final outputBuffer = StringBuffer();
      final output = await ref
          .read(appStateProvider)
          .runRouterSetupCommandViaSsh(
            command,
            onOutput: (chunk) {
              outputBuffer.write(chunk);
              console.setOutput(outputBuffer.toString().trimRight());
              if (!mounted) return;
              setState(() {
                _lastOutput = outputBuffer.toString().trimRight();
              });
            },
          );
      if (!mounted) return;
      setState(() {
        _lastOutput = output.trim().isEmpty
            ? 'Uninstall finished. The router did not return console output.'
            : output.trim();
      });
      console.setOutput(_lastOutput!);
      _showSnack('Selected components removed.');
    } catch (e) {
      if (!mounted) return;
      console.setOutput('SSH uninstall failed.\n\n$e');
      setState(() {
        _lastOutput = 'SSH uninstall failed.\n\n$e';
        _showDetails = true;
      });
      _showSnack('Could not remove selected components.');
    } finally {
      console.complete();
      if (mounted) setState(() => _isUninstalling = false);
    }
  }

  Future<void> _enableDashboardCardsForInstalledFeatures() async {
    final appState = ref.read(appStateProvider);
    final selectedFeatures = _selectedFeatures;
    final isCustomInstall = _selectedProfile == _SetupProfile.custom;
    final installsFlows = selectedFeatures.any(
      (feature) => feature == 'conntrack' || feature == 'netify',
    );
    final prefs = widget.netifyOnly
        ? appState.dashboardPreferences.copyWith(
            showFlowsCard: true,
            flowMode: DashboardFlowMode.detailed,
          )
        : appState.dashboardPreferences.copyWith(
            showNetworkPerformanceCard:
                !isCustomInstall || selectedFeatures.contains('network-monitor')
                ? true
                : appState.dashboardPreferences.showNetworkPerformanceCard,
            showFlowsCard: installsFlows
                ? true
                : appState.dashboardPreferences.showFlowsCard,
            showStatisticsTab:
                !isCustomInstall || selectedFeatures.contains('usage')
                ? true
                : appState.dashboardPreferences.showStatisticsTab,
            flowMode: selectedFeatures.contains('netify')
                ? DashboardFlowMode.detailed
                : selectedFeatures.contains('conntrack')
                ? DashboardFlowMode.simple
                : appState.dashboardPreferences.flowMode,
          );

    await appState.saveDashboardPreferences(prefs);
  }

  void _showSnack(String message, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? const Color(0xFF20CF70) : null,
      ),
    );
  }

  void _previousStep() {
    if (_wizardStep > 0) setState(() => _wizardStep -= 1);
  }

  @override
  Widget build(BuildContext context) {
    final command = _setupCommand;
    final isRemovePage = _selectedProfile == _SetupProfile.remove;
    final canInstall = _selectedFeatures.isNotEmpty;

    return Scaffold(
      appBar: const LuciAppBar(title: 'Router Setup', showBack: true),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            if (_wizardStep > 0) ...[
              _WizardProgress(currentStep: _wizardStep, totalSteps: 2),
              const SizedBox(height: 16),
            ],
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(
                key: ValueKey(_wizardStep),
                child: _buildWizardStep(),
              ),
            ),
            if (widget.netifyOnly && _wizardStep == 0) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _isInstalling
                    ? null
                    : () => setState(() => _wizardStep = 1),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Review Install'),
              ),
            ],
            if (_wizardStep > 0) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isInstalling || _isUninstalling
                          ? null
                          : _previousStep,
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Back'),
                    ),
                  ),
                  if (!isRemovePage) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isInstalling || !canInstall
                            ? null
                            : _runSetup,
                        icon: _isInstalling
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_done_rounded),
                        label: Text(
                          _isInstalling ? 'Installing' : 'Install via SSH',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (_wizardStep == _lastWizardStep && !isRemovePage) ...[
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: _isInstalling || !canInstall ? null : _copyCommand,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy SSH Command'),
                ),
              ),
            ],
            if (_wizardStep == _lastWizardStep && !isRemovePage) ...[
              if (_setupComplete) ...[
                const SizedBox(height: 16),
                const _SetupCompleteBanner(),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showDetails = !_showDetails),
                  icon: Icon(
                    _showDetails
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                  label: Text(_showDetails ? 'Hide Details' : 'Show Details'),
                ),
              ),
              if (_showDetails) ...[
                const SizedBox(height: 8),
                _CommandPreview(command: command),
              ],
              if (_lastOutput != null) ...[
                const SizedBox(height: 16),
                SshConsolePreview(
                  output: _lastOutput!,
                  isRunning: _isInstalling || _isUninstalling,
                ),
              ],
            ],
            if (!widget.netifyOnly) ...[
              const SizedBox(height: 20),
              Text(
                'Router Tools',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: ListTile.divideTiles(
                    context: context,
                    tiles: [
                      ListTile(
                        leading: const Icon(Icons.system_update_alt_rounded),
                        title: const Text('Router Components'),
                        subtitle: const Text(
                          'Verify and update installed helper files',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const RouterComponentsScreen(),
                          ),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.terminal_rounded),
                        title: const Text('SSH Terminal'),
                        subtitle: const Text(
                          'Open a shell with saved router credentials',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SshTerminalScreen(),
                          ),
                        ),
                      ),
                    ],
                  ).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWizardStep() {
    if (widget.netifyOnly) {
      return _wizardStep == 0
          ? _WizardIntroCard(
              title: 'Install Detailed Flow Support',
              subtitle:
                  'This focused setup installs Netify, sqlite support, and the Openwalla Netify collector needed for Detailed Flow data. For best results, use a router with at least 512 MB RAM and a 4-core CPU.',
              icon: Icons.account_tree_rounded,
            )
          : _SetupPermissionCard(
              isInstalling: _isInstalling,
              extraSoftware: 0,
              featureCount: 1,
              onToggleDetails: () => setState(() => _showDetails = true),
            );
    }

    if (_wizardStep == 0) {
      return _SetupProfilePicker(
        enabled: !_isInstalling && !_isUninstalling,
        onSelected: (profile) {
          setState(() {
            _selectedProfile = profile;
            _wizardStep = 1;
            _setupComplete = false;
            _lastOutput = null;
          });
        },
      );
    }

    if (_selectedProfile == _SetupProfile.remove) {
      return _UninstallComponentsCard(
        selectedFeatures: _uninstallFeatures,
        enabled: !_isInstalling && !_isUninstalling,
        onChanged: (feature, selected) {
          setState(() {
            if (selected) {
              _uninstallFeatures.add(feature);
            } else {
              _uninstallFeatures.remove(feature);
            }
          });
        },
        onRun: _runUninstall,
      );
    }

    if (_selectedProfile == _SetupProfile.custom) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CustomInstallComponentsCard(
            selectedFeatures: _customInstallFeatures,
            enabled: !_isInstalling && !_isUninstalling,
            onChanged: (feature, selected) {
              setState(() {
                if (selected) {
                  if (feature == 'netify') {
                    _customInstallFeatures.remove('conntrack');
                  } else if (feature == 'conntrack') {
                    _customInstallFeatures.remove('netify');
                  }
                  _customInstallFeatures.add(feature);
                } else {
                  _customInstallFeatures.remove(feature);
                }
              });
            },
          ),
          if (_customInstallFeatures.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SetupPermissionCard(
              isInstalling: _isInstalling,
              extraSoftware: 0,
              featureCount: _customInstallFeatures.length,
              onToggleDetails: () => setState(() => _showDetails = true),
            ),
          ],
        ],
      );
    }

    final profile = _selectedProfile!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SetupFeatureCard(
          icon: profile.icon,
          title: profile.title,
          subtitle: profile.description,
          child: _InstallerList(items: _installLabels(profile)),
        ),
        const SizedBox(height: 12),
        _SetupPermissionCard(
          isInstalling: _isInstalling,
          extraSoftware: (_selectedFeatures.length - _basicFeatures.length)
              .clamp(0, _selectedFeatures.length),
          featureCount: _selectedFeatures.length,
          onToggleDetails: () => setState(() => _showDetails = true),
        ),
      ],
    );
  }

  List<String> _installLabels(_SetupProfile profile) {
    const basic = [
      'OpenWrt RPC and command dependencies',
      'Network, DNS, and speed monitoring',
      'Statistics and device inventory',
      'Notifications and persistent state',
    ];
    return switch (profile) {
      _SetupProfile.basic => basic,
      _SetupProfile.standard => [
        ...basic,
        'AdBlock',
        'Parental Controls',
        'Device Quarantine',
        'Smart Queue (SQM)',
        'Dynamic DNS (DDNS)',
        'WireGuard tools and LuCI protocol support',
      ],
      _SetupProfile.advanced => [
        ..._installLabels(_SetupProfile.standard),
        'Policy-Based Routing (PBR)',
      ],
      _SetupProfile.custom =>
        _CustomInstallComponentsCard.items
            .where((item) => _customInstallFeatures.contains(item.feature))
            .map((item) => item.title)
            .toList(growable: false),
      _SetupProfile.everything => [
        ..._installLabels(_SetupProfile.standard),
        'Policy-Based Routing (PBR)',
        'Netify deep-packet inspection service',
        'Detailed Flow SQLite collector',
        'Hybrid relational and JSON flow database',
      ],
      _SetupProfile.remove => const [],
    };
  }

  int get _lastWizardStep => 1;
}

class _SetupProfilePicker extends StatelessWidget {
  final bool enabled;
  final ValueChanged<_SetupProfile> onSelected;

  const _SetupProfilePicker({required this.enabled, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose a setup option',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Review exactly what will be installed before making changes to the router.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        ..._SetupProfile.values.map(
          (profile) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                enabled: enabled,
                contentPadding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                leading: Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: profile == _SetupProfile.remove
                        ? colors.error.withValues(alpha: 0.10)
                        : colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    profile.icon,
                    color: profile == _SetupProfile.remove
                        ? colors.error
                        : colors.primary,
                  ),
                ),
                title: Text(
                  profile.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(profile.description),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: enabled ? () => onSelected(profile) : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SetupPermissionCard extends StatelessWidget {
  final bool isInstalling;
  final int extraSoftware;
  final int featureCount;
  final VoidCallback onToggleDetails;

  const _SetupPermissionCard({
    required this.isInstalling,
    required this.extraSoftware,
    required this.featureCount,
    required this.onToggleDetails,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const actionBlue = Color(0xFF2563EB);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: actionBlue.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: actionBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Router access required',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Openwalla needs permission to install the selected packages and helper scripts on your router.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest.withValues(
                  alpha: 0.42,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.18),
                ),
              ),
              child: const Column(
                children: [
                  _PermissionLine(
                    icon: Icons.terminal_rounded,
                    text: 'Connect over SSH with the saved router login.',
                  ),
                  SizedBox(height: 10),
                  _PermissionLine(
                    icon: Icons.inventory_2_outlined,
                    text: 'Install standard OpenWrt application packages.',
                  ),
                  SizedBox(height: 10),
                  _PermissionLine(
                    icon: Icons.extension_outlined,
                    text: 'Install selected optional software packages.',
                  ),
                  SizedBox(height: 10),
                  _PermissionLine(
                    icon: Icons.monitor_heart_outlined,
                    text: 'Install selected Openwalla feature bundles.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Selected: $extraSoftware extra software option${extraSoftware == 1 ? '' : 's'} and $featureCount Openwalla feature bundle${featureCount == 1 ? '' : 's'}.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                Text(
                  'Want to inspect the SSH fallback?',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextButton(
                  onPressed: onToggleDetails,
                  child: const Text('Show details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WizardProgress extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _WizardProgress({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(totalSteps, (index) {
        final active = index <= currentStep;
        return Expanded(
          child: Container(
            height: 5,
            margin: EdgeInsets.only(right: index == totalSteps - 1 ? 0 : 6),
            decoration: BoxDecoration(
              color: active
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }
}

class _WizardIntroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _WizardIntroCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: colorScheme.primary, size: 28),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstallerList extends StatelessWidget {
  final List<String> items;

  const _InstallerList({required this.items});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (item) => Chip(
              avatar: Icon(
                Icons.check_circle_outline_rounded,
                size: 17,
                color: colorScheme.primary,
              ),
              label: Text(item),
            ),
          )
          .toList(),
    );
  }
}

class _SetupCompleteBanner extends StatelessWidget {
  const _SetupCompleteBanner();

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF20CF70);
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: green.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Setup Complete',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomInstallComponentsCard extends StatelessWidget {
  final Set<String> selectedFeatures;
  final bool enabled;
  final void Function(String feature, bool selected) onChanged;

  static const items = [
    (
      feature: 'standard',
      title: 'Core Packages',
      subtitle: 'OpenWrt RPC, SQLite, conntrack, and command dependencies.',
      icon: Icons.foundation_rounded,
    ),
    (
      feature: 'usage',
      title: 'Statistics',
      subtitle: 'vnStat and nlbwmon usage support.',
      icon: Icons.bar_chart_rounded,
    ),
    (
      feature: 'network-monitor',
      title: 'Network Monitor',
      subtitle: 'Latency, outage, and Ethernet link monitoring.',
      icon: Icons.monitor_heart_outlined,
    ),
    (
      feature: 'dns',
      title: 'DNS Test',
      subtitle: 'DNS health monitoring service.',
      icon: Icons.dns_rounded,
    ),
    (
      feature: 'speedtest',
      title: 'Speed Test',
      subtitle: 'Scheduled network speed tests.',
      icon: Icons.speed_rounded,
    ),
    (
      feature: 'notifications',
      title: 'Notifications',
      subtitle: 'Router notification database helper.',
      icon: Icons.notifications_rounded,
    ),
    (
      feature: 'devices',
      title: 'Devices',
      subtitle: 'Device inventory and quarantine-aware collector.',
      icon: Icons.devices_rounded,
    ),
    (
      feature: 'device-speed',
      title: 'Live Device Speed',
      subtitle: 'Per-device live throughput helper.',
      icon: Icons.swap_vert_rounded,
    ),
    (
      feature: 'bandwidth',
      title: 'Device Bandwidth',
      subtitle: 'Per-device historical usage collector.',
      icon: Icons.data_usage_rounded,
    ),
    (
      feature: 'blocking',
      title: 'Internet Blocking',
      subtitle: 'Manual device pause and blocking helper.',
      icon: Icons.block_rounded,
    ),
    (
      feature: 'scheduler',
      title: 'Parental Controls',
      subtitle: 'Device profiles, schedules, and access limits.',
      icon: Icons.schedule_rounded,
    ),
    (
      feature: 'quarantine',
      title: 'Device Quarantine',
      subtitle: 'New-device detection and automatic isolation.',
      icon: Icons.gpp_bad_rounded,
    ),
    (
      feature: 'state-sync',
      title: 'Backup State Sync',
      subtitle: 'Persistent Openwalla router-state backups.',
      icon: Icons.backup_rounded,
    ),
    (
      feature: 'conntrack',
      title: 'Simple Flow',
      subtitle: 'Lightweight conntrack flow collector.',
      icon: Icons.route_rounded,
    ),
    (
      feature: 'netify',
      title: 'Detailed Flow',
      subtitle: 'Netify deep inspection and detailed flow collector.',
      icon: Icons.account_tree_rounded,
    ),
    (
      feature: 'adblock',
      title: 'AdBlock',
      subtitle: 'OpenWrt domain-blocking service.',
      icon: Icons.shield_rounded,
    ),
    (
      feature: 'qos',
      title: 'Smart Queue',
      subtitle: 'SQM latency and bufferbloat controls.',
      icon: Icons.tune_rounded,
    ),
    (
      feature: 'ddns',
      title: 'Dynamic DNS',
      subtitle: 'OpenWrt DDNS packages and service.',
      icon: Icons.public_rounded,
    ),
    (
      feature: 'wireguard',
      title: 'WireGuard',
      subtitle: 'WireGuard tools and LuCI protocol support.',
      icon: Icons.vpn_key_rounded,
    ),
    (
      feature: 'pbr',
      title: 'Policy-Based Routing',
      subtitle: 'Route selected traffic through specific interfaces.',
      icon: Icons.alt_route_rounded,
    ),
    (
      feature: 'banip',
      title: 'banIP',
      subtitle: 'IP blocklists and country blocking.',
      icon: Icons.gpp_bad_outlined,
    ),
    (
      feature: 'tor',
      title: 'Tor',
      subtitle: 'Tor transparent proxy support.',
      icon: Icons.security_rounded,
    ),
    (
      feature: 'tailscale',
      title: 'Tailscale',
      subtitle: 'Tailscale mesh VPN and subnet routing.',
      icon: Icons.hub_rounded,
    ),
    (
      feature: 'mwan3',
      title: 'Multi-WAN',
      subtitle: 'WAN failover and load balancing.',
      icon: Icons.call_split_rounded,
    ),
  ];

  const _CustomInstallComponentsCard({
    required this.selectedFeatures,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Choose Components',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Text(
                'Select only what you want to install or redeploy. Simple Flow and Detailed Flow cannot be installed together.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ...items.map(
              (item) => CheckboxListTile(
                value: selectedFeatures.contains(item.feature),
                onChanged: enabled
                    ? (value) => onChanged(item.feature, value ?? false)
                    : null,
                controlAffinity: ListTileControlAffinity.trailing,
                secondary: Icon(item.icon, color: colorScheme.primary),
                title: Text(item.title),
                subtitle: Text(item.subtitle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UninstallComponentsCard extends StatelessWidget {
  final Set<String> selectedFeatures;
  final bool enabled;
  final void Function(String feature, bool selected) onChanged;
  final VoidCallback onRun;

  static const _items = [
    (
      feature: 'usage',
      title: 'Statistics',
      subtitle: 'vnstat/vnstat2 and nlbwmon packages.',
      icon: Icons.bar_chart_rounded,
    ),
    (
      feature: 'network-monitor',
      title: 'Network Monitor',
      subtitle: 'Latency, outage, and Ethernet link monitoring.',
      icon: Icons.monitor_heart_outlined,
    ),
    (
      feature: 'dns',
      title: 'DNS Test',
      subtitle: 'DNS monitor helper and service.',
      icon: Icons.dns_rounded,
    ),
    (
      feature: 'speedtest',
      title: 'Speed Test',
      subtitle: 'Speedtest helper and cron job.',
      icon: Icons.speed_rounded,
    ),
    (
      feature: 'devices',
      title: 'Devices',
      subtitle: 'Device inventory collector.',
      icon: Icons.devices_rounded,
    ),
    (
      feature: 'bandwidth',
      title: 'Device Bandwidth',
      subtitle: 'Per-device usage collector.',
      icon: Icons.swap_vert_rounded,
    ),
    (
      feature: 'scheduler',
      title: 'Parental Controls',
      subtitle:
          'Router-side profiles, schedules, limits, and activity database.',
      icon: Icons.schedule_rounded,
    ),
    (
      feature: 'blocking',
      title: 'Internet Blocking',
      subtitle: 'Manual parental block helper.',
      icon: Icons.block_rounded,
    ),
    (
      feature: 'quarantine',
      title: 'Device Quarantine',
      subtitle: 'New-device detection and automatic isolation service.',
      icon: Icons.gpp_bad_rounded,
    ),
    (
      feature: 'notifications',
      title: 'Notifications',
      subtitle: 'Notification database helper.',
      icon: Icons.notifications_rounded,
    ),
    (
      feature: 'netify',
      title: 'Detailed Flow',
      subtitle: 'Netify package and collector.',
      icon: Icons.account_tree_rounded,
    ),
    (
      feature: 'conntrack',
      title: 'Simple Flow',
      subtitle: 'Conntrack flow collector.',
      icon: Icons.route_rounded,
    ),
    (
      feature: 'adblock',
      title: 'AdBlock',
      subtitle: 'OpenWrt adblock package.',
      icon: Icons.shield_rounded,
    ),
    (
      feature: 'ddns',
      title: 'Dynamic DNS',
      subtitle: 'OpenWrt DDNS packages and service.',
      icon: Icons.public_rounded,
    ),
    (
      feature: 'qos',
      title: 'Smart Queue',
      subtitle: 'SQM package support.',
      icon: Icons.tune_rounded,
    ),
    (
      feature: 'pbr',
      title: 'Policy-Based Routing',
      subtitle: 'OpenWrt PBR package support.',
      icon: Icons.alt_route_rounded,
    ),
    (
      feature: 'banip',
      title: 'banIP',
      subtitle: 'OpenWrt IP blocklist support.',
      icon: Icons.gpp_bad_outlined,
    ),
    (
      feature: 'wireguard',
      title: 'WireGuard',
      subtitle: 'WireGuard tools and LuCI protocol support.',
      icon: Icons.vpn_key_rounded,
    ),
    (
      feature: 'tor',
      title: 'Tor',
      subtitle: 'Tor transparent proxy support.',
      icon: Icons.security_rounded,
    ),
    (
      feature: 'tailscale',
      title: 'Tailscale',
      subtitle: 'Tailscale mesh VPN support.',
      icon: Icons.hub_rounded,
    ),
  ];

  const _UninstallComponentsCard({
    required this.selectedFeatures,
    required this.enabled,
    required this.onChanged,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        leading: Icon(Icons.delete_sweep_outlined, color: colorScheme.primary),
        title: Text(
          'Remove Installed Components',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        subtitle: Text(
          'Select Openwalla sub-apps to remove from this router.',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        children: [
          ..._items.map(
            (item) => CheckboxListTile(
              value: selectedFeatures.contains(item.feature),
              onChanged: enabled
                  ? (value) => onChanged(item.feature, value ?? false)
                  : null,
              controlAffinity: ListTileControlAffinity.trailing,
              secondary: Icon(item.icon, color: colorScheme.primary),
              title: Text(item.title),
              subtitle: Text(item.subtitle),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: enabled && selectedFeatures.isNotEmpty ? onRun : null,
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(
              selectedFeatures.isEmpty
                  ? 'Select Components'
                  : 'Remove Selected',
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PermissionLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const actionBlue = Color(0xFF2563EB);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: actionBlue, size: 17),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
              height: 1.28,
            ),
          ),
        ),
      ],
    );
  }
}

class _SetupFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? child;

  const _SetupFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (child != null) ...[const SizedBox(height: 8), child!],
          ],
        ),
      ),
    );
  }
}

class _CommandPreview extends StatelessWidget {
  final String command;

  const _CommandPreview({required this.command});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'SSH Command',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            SelectableText(
              command.isEmpty ? 'Choose at least one setup option.' : command,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
