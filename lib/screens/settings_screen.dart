import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/luci_toast.dart';
import 'package:openwalla/screens/router_dashboard_settings_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Widget _buildSettingsCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: colorScheme.onPrimaryContainer, size: 24),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
      ),
    );
  }

  void _openSettingsPage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => page));
  }

  void _showReviewerModeResetDialog(BuildContext context, WidgetRef ref) {
    final appState = ref.read(appStateProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Reviewer Mode?'),
        content: const Text(
          'This will disable reviewer mode and return to normal authentication. '
          'You will need to log in with real router credentials.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await appState.setReviewerMode(false);
              await appState.logout();
              if (context.mounted) {
                unawaited(
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/login', (route) => false),
                );
              }
            },
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Settings', showBack: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        children: [
          Builder(
            builder: (context) {
              final appState = ref.watch(appStateProvider);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSettingsCard(
                    context: context,
                    icon: Icons.palette_outlined,
                    title: 'Theme',
                    subtitle:
                        '${_themeModeLabel(appState.themeMode)} • ${appState.themeAccent.label}',
                    onTap: () => _openSettingsPage(
                      context,
                      const _ThemeSettingsScreen(),
                    ),
                  ),
                  _buildSettingsCard(
                    context: context,
                    icon: Icons.dashboard_customize,
                    title: 'Dashboard Settings',
                    subtitle: 'Choose which cards and panels appear',
                    onTap: () => _openSettingsPage(
                      context,
                      const RouterDashboardSettingsScreen(
                        title: 'Dashboard Settings',
                        showThroughput: false,
                        showWirelessInterfaces: false,
                        showWiredInterfaces: false,
                      ),
                    ),
                  ),
                  if (appState.reviewerModeEnabled) ...[
                    const Divider(height: 32),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        'Reviewer Mode',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.info_outline,
                        color: Colors.orange,
                      ),
                      title: const Text('Reviewer Mode Active'),
                      subtitle: Text(
                        'Mock data is being used for demonstration',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: FilledButton.icon(
                        onPressed: () =>
                            _showReviewerModeResetDialog(context, ref),
                        icon: const Icon(Icons.exit_to_app),
                        label: const Text('Exit Reviewer Mode'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onError,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String _themeModeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => 'System default',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };
}

class _ThemeSettingsScreen extends ConsumerWidget {
  const _ThemeSettingsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    return Scaffold(
      appBar: const LuciAppBar(title: 'Theme', showBack: true),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            _SettingsFormCard(
              children: [
                _ThemeOptionTile(
                  icon: Icons.brightness_auto_rounded,
                  title: 'System Default',
                  subtitle: 'Follow your device setting',
                  selected: appState.themeMode == ThemeMode.system,
                  onTap: () => appState.setThemeMode(ThemeMode.system),
                ),
                const Divider(height: 1),
                _ThemeOptionTile(
                  icon: Icons.light_mode_outlined,
                  title: 'Light',
                  subtitle: 'Use the light Openwalla theme',
                  selected: appState.themeMode == ThemeMode.light,
                  onTap: () => appState.setThemeMode(ThemeMode.light),
                ),
                const Divider(height: 1),
                _ThemeOptionTile(
                  icon: Icons.dark_mode_outlined,
                  title: 'Dark',
                  subtitle: 'Use the dark Openwalla theme',
                  selected: appState.themeMode == ThemeMode.dark,
                  onTap: () => appState.setThemeMode(ThemeMode.dark),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsFormCard(
              children: [
                Text(
                  'Accent Color',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose the color used for active controls and highlights.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _ThemeAccentPicker(
                  selected: appState.themeAccent,
                  onSelected: appState.setThemeAccent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        icon,
        color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}

class _ThemeAccentPicker extends StatelessWidget {
  final OpenwallaThemeAccent selected;
  final ValueChanged<OpenwallaThemeAccent> onSelected;

  const _ThemeAccentPicker({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: OpenwallaThemeAccent.values.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.92,
      ),
      itemBuilder: (context, index) {
        final accent = OpenwallaThemeAccent.values[index];
        return _ThemeAccentTile(
          accent: accent,
          selected: selected == accent,
          onTap: () => onSelected(accent),
        );
      },
    );
  }
}

class _ThemeAccentTile extends StatelessWidget {
  final OpenwallaThemeAccent accent;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeAccentTile({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected
                ? accent.color.withValues(alpha: 0.16)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? accent.color
                  : colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.color.withValues(alpha: 0.32),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                accent.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetworkMonitorSettingsScreen extends ConsumerStatefulWidget {
  const _NetworkMonitorSettingsScreen();

  @override
  ConsumerState<_NetworkMonitorSettingsScreen> createState() =>
      _NetworkMonitorSettingsScreenState();
}

class _NetworkMonitorSettingsScreenState
    extends ConsumerState<_NetworkMonitorSettingsScreen> {
  final _targetController = TextEditingController(text: '1.1.1.1');
  final _thresholdController = TextEditingController(text: '100');
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  @override
  void dispose() {
    _targetController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final appState = ref.read(appStateProvider);
    final settings = await appState.fetchNetworkMonitorSettings(
      context: context,
    );
    if (!mounted) return;

    _targetController.text = settings.target;
    _thresholdController.text = settings.thresholdMs.toString();
    setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    final target = _targetController.text.trim();
    final threshold = int.tryParse(_thresholdController.text.trim());

    if (target.isEmpty || threshold == null || threshold <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a target and a threshold greater than 0ms.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .saveNetworkMonitorSettings(
            NetworkMonitorSettings(target: target, thresholdMs: threshold),
            context: context,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network monitor settings saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save network monitor settings: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Network Monitor', showBack: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SettingsFormCard(
                  children: [
                    TextField(
                      controller: _targetController,
                      decoration: const InputDecoration(
                        labelText: 'Target',
                        hintText: '1.1.1.1',
                        prefixIcon: Icon(Icons.public_rounded),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      enabled: !_isSaving,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _thresholdController,
                      decoration: const InputDecoration(
                        labelText: 'Alert Threshold',
                        suffixText: 'ms',
                        prefixIcon: Icon(Icons.notifications_active_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !_isSaving,
                    ),
                  ],
                ),
              ],
            ),
      bottomNavigationBar: _isLoading
          ? null
          : _SettingsSaveBar(
              isSaving: _isSaving,
              onPressed: _isSaving ? null : _saveSettings,
            ),
    );
  }
}

class _DnsTestSettingsScreen extends ConsumerStatefulWidget {
  const _DnsTestSettingsScreen();

  @override
  ConsumerState<_DnsTestSettingsScreen> createState() =>
      _DnsTestSettingsScreenState();
}

class _DnsTestSettingsScreenState
    extends ConsumerState<_DnsTestSettingsScreen> {
  final _hostnameController = TextEditingController(text: 'openwrt.org');
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  @override
  void dispose() {
    _hostnameController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final settings = await ref
        .read(appStateProvider)
        .fetchDnsMonitorSettings(context: context);
    if (!mounted) return;

    _hostnameController.text = settings.hostname;
    setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    final hostname = _hostnameController.text.trim();

    if (hostname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a hostname to monitor.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .saveDnsMonitorSettings(
            DnsMonitorSettings(hostname: hostname),
            context: context,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('DNS test settings saved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save DNS settings: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'DNS Test Settings', showBack: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SettingsFormCard(
                  children: [
                    TextField(
                      controller: _hostnameController,
                      decoration: const InputDecoration(
                        labelText: 'Hostname',
                        hintText: 'openwrt.org',
                        prefixIcon: Icon(Icons.dns_rounded),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      enabled: !_isSaving,
                    ),
                  ],
                ),
              ],
            ),
      bottomNavigationBar: _isLoading
          ? null
          : _SettingsSaveBar(
              isSaving: _isSaving,
              onPressed: _isSaving ? null : _saveSettings,
            ),
    );
  }
}

class _SpeedtestSettingsScreen extends ConsumerStatefulWidget {
  const _SpeedtestSettingsScreen();

  @override
  ConsumerState<_SpeedtestSettingsScreen> createState() =>
      _SpeedtestSettingsScreenState();
}

class _SpeedtestSettingsScreenState
    extends ConsumerState<_SpeedtestSettingsScreen> {
  bool _enabled = true;
  bool _isLoading = true;
  bool _isSaving = false;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 3, minute: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final settings = await ref
        .read(appStateProvider)
        .fetchSpeedtestMonitorSettings(context: context);
    if (!mounted) return;

    setState(() {
      _enabled = settings.enabled;
      _selectedTime = TimeOfDay(
        hour: settings.runHour,
        minute: settings.runMinute,
      );
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    const actionKey = 'speedtest-schedule';
    context.showToastLoading(
      'Saving speedtest schedule...',
      actionKey: actionKey,
    );
    try {
      await ref
          .read(appStateProvider)
          .saveSpeedtestMonitorSettings(
            SpeedtestMonitorSettings(
              enabled: _enabled,
              runDate: null,
              runHour: _selectedTime.hour,
              runMinute: _selectedTime.minute,
            ),
            context: context,
          );
      if (!mounted) return;
      context.showToastSuccess(
        'Speedtest schedule saved',
        subtitle: _enabled
            ? 'Runs every day at ${_selectedTime.format(context)}.'
            : 'Scheduled speedtests are disabled.',
        actionKey: actionKey,
      );
    } catch (e) {
      if (!mounted) return;
      context.showToastError(
        'Speedtest schedule was not saved',
        subtitle: e.toString().replaceFirst('Bad state: ', ''),
        actionKey: actionKey,
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _selectTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );

    if (pickedTime != null && mounted) {
      setState(() => _selectedTime = pickedTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Speedtest Settings', showBack: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SettingsFormCard(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Scheduled Speedtest'),
                      subtitle: Text(_enabled ? 'Enabled' : 'Disabled'),
                      value: _enabled,
                      onChanged: _isSaving
                          ? null
                          : (value) => setState(() => _enabled = value),
                    ),
                    const Divider(height: 24),
                    _PickerTile(
                      icon: Icons.schedule_rounded,
                      title: 'Every day at',
                      value: _selectedTime.format(context),
                      onTap: _isSaving ? null : _selectTime,
                    ),
                  ],
                ),
              ],
            ),
      bottomNavigationBar: _isLoading
          ? null
          : _SettingsSaveBar(
              isSaving: _isSaving,
              onPressed: _isSaving ? null : _saveSettings,
            ),
    );
  }
}

class _MonthlyUsageSettingsScreen extends ConsumerStatefulWidget {
  const _MonthlyUsageSettingsScreen();

  @override
  ConsumerState<_MonthlyUsageSettingsScreen> createState() =>
      _MonthlyUsageSettingsScreenState();
}

class _MonthlyUsageSettingsScreenState
    extends ConsumerState<_MonthlyUsageSettingsScreen> {
  static const _defaultInterface = 'br-lan';
  var _interfaces = const <String>[];
  final _monthlyLimitController = TextEditingController();
  DateTime _startDate = DateTime.now();
  String _selectedInterface = _defaultInterface;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final appState = ref.read(appStateProvider);
    final settings = await appState.fetchMonthlyUsageSettings(context: context);
    if (!mounted) return;
    final interfaces = await appState.fetchVnstatInterfaceNames(
      context: context,
    );
    if (!mounted) return;

    final selectedInterface = _resolveSelectedInterface(
      settings.interfaceName,
      interfaces,
    );

    setState(() {
      _interfaces = interfaces;
      _selectedInterface = selectedInterface;
      final now = DateTime.now();
      final safeDay = settings.monthStartDay.clamp(1, 28);
      _startDate = DateTime(now.year, now.month, safeDay);
      _monthlyLimitController.text = settings.monthlyLimitGb <= 0
          ? ''
          : settings.monthlyLimitGb.toString();
      _isLoading = false;
    });
  }

  String _resolveSelectedInterface(String savedInterface, List<String> names) {
    if (names.contains(savedInterface)) return savedInterface;

    final savedLower = savedInterface.toLowerCase();
    final caseInsensitive = names.where((name) {
      return name.toLowerCase() == savedLower;
    }).firstOrNull;
    if (caseInsensitive != null) return caseInsensitive;

    if (savedLower == 'lan' && names.contains('br-lan')) return 'br-lan';
    if (names.contains(_defaultInterface)) return _defaultInterface;
    return names.isNotEmpty ? names.first : savedInterface;
  }

  Future<void> _saveSettings() async {
    if (_selectedInterface.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('vnStat is not monitoring any interfaces yet.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .saveMonthlyUsageSettings(
            MonthlyUsageSettings(
              monthStartDay: _startDate.day,
              interfaceName: _selectedInterface,
              monthlyLimitGb:
                  int.tryParse(_monthlyLimitController.text.trim()) ?? 0,
            ),
            context: context,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Monthly usage settings saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save monthly usage settings: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _monthlyLimitController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 1),
    );

    if (pickedDate != null && mounted) {
      setState(() => _startDate = pickedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Monthly Usage', showBack: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SettingsFormCard(
                  children: [
                    _PickerTile(
                      icon: Icons.event_available_rounded,
                      title: 'Start Date',
                      value: _formatDate(_startDate),
                      onTap: _isSaving ? null : _selectStartDate,
                    ),
                    const SizedBox(height: 16),
                    if (_interfaces.isEmpty)
                      const _MonthlyUsageNotice(
                        message:
                            'No vnStat-monitored interfaces were found. Install or start vnstat, then refresh this screen.',
                      )
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth < 280
                                ? constraints.maxWidth
                                : 280.0;
                            return SizedBox(
                              width: width,
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedInterface,
                                decoration: const InputDecoration(
                                  labelText: 'vnStat Interface',
                                  prefixIcon: Icon(
                                    Icons.settings_ethernet_rounded,
                                  ),
                                  border: OutlineInputBorder(),
                                ),
                                items: _interfaces
                                    .map(
                                      (interface) => DropdownMenuItem(
                                        value: interface,
                                        child: Text(interface),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _isSaving
                                    ? null
                                    : (value) {
                                        if (value != null) {
                                          setState(
                                            () => _selectedInterface = value,
                                          );
                                        }
                                      },
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _monthlyLimitController,
                      enabled: !_isSaving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Monthly Limit',
                        hintText: '0 for no limit',
                        suffixText: 'GB',
                        prefixIcon: Icon(Icons.data_usage_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
      bottomNavigationBar: _isLoading
          ? null
          : _SettingsSaveBar(
              isSaving: _isSaving,
              onPressed: _isSaving || _interfaces.isEmpty
                  ? null
                  : _saveSettings,
            ),
    );
  }
}

class _MonthlyUsageNotice extends StatelessWidget {
  final String message;

  const _MonthlyUsageNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSaveBar extends StatelessWidget {
  final bool isSaving;
  final VoidCallback? onPressed;

  const _SettingsSaveBar({required this.isSaving, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.42),
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded),
          label: Text(isSaving ? 'Saving' : 'Save'),
        ),
      ),
    );
  }
}

class _SettingsFormCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsFormCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  const _PickerTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: colorScheme.primary),
      title: Text(title),
      subtitle: Text(value),
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
