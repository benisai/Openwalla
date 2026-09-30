import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/design/luci_design_system.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/luci_toast.dart';

class NetworkPerformanceSettingsScreen extends ConsumerStatefulWidget {
  const NetworkPerformanceSettingsScreen({super.key});

  @override
  ConsumerState<NetworkPerformanceSettingsScreen> createState() =>
      _NetworkPerformanceSettingsScreenState();
}

class _NetworkPerformanceSettingsScreenState
    extends ConsumerState<NetworkPerformanceSettingsScreen> {
  final _pingTargetController = TextEditingController(text: '1.1.1.1');
  final _pingThresholdController = TextEditingController(text: '100');
  final _dnsHostnameController = TextEditingController(text: 'openwrt.org');
  bool _speedtestEnabled = true;
  bool _isLoading = true;
  bool _isSaving = false;
  TimeOfDay _speedtestTime = const TimeOfDay(hour: 3, minute: 15);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  @override
  void dispose() {
    _pingTargetController.dispose();
    _pingThresholdController.dispose();
    _dnsHostnameController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final appState = ref.read(appStateProvider);
    final results = await Future.wait([
      appState.fetchNetworkMonitorSettings(context: context),
      appState.fetchDnsMonitorSettings(context: context),
      appState.fetchSpeedtestMonitorSettings(context: context),
    ]);
    if (!mounted) return;

    final ping = results[0] as NetworkMonitorSettings;
    final dns = results[1] as DnsMonitorSettings;
    final speedtest = results[2] as SpeedtestMonitorSettings;
    setState(() {
      _pingTargetController.text = ping.target;
      _pingThresholdController.text = ping.thresholdMs.toString();
      _dnsHostnameController.text = dns.hostname;
      _speedtestEnabled = speedtest.enabled;
      _speedtestTime = TimeOfDay(
        hour: speedtest.runHour,
        minute: speedtest.runMinute,
      );
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final pingTarget = _pingTargetController.text.trim();
    final threshold = int.tryParse(_pingThresholdController.text.trim());
    final dnsHostname = _dnsHostnameController.text.trim();

    if (pingTarget.isEmpty || threshold == null || threshold <= 0) {
      _showSnack('Enter a ping target and threshold greater than 0ms.');
      return;
    }
    if (dnsHostname.isEmpty) {
      _showSnack('Enter a DNS hostname to monitor.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final appState = ref.read(appStateProvider);
      await appState.saveNetworkMonitorSettings(
        NetworkMonitorSettings(target: pingTarget, thresholdMs: threshold),
      );
      await appState.saveDnsMonitorSettings(
        DnsMonitorSettings(hostname: dnsHostname),
      );
      await appState.saveSpeedtestMonitorSettings(
        SpeedtestMonitorSettings(
          enabled: _speedtestEnabled,
          runDate: null,
          runHour: _speedtestTime.hour,
          runMinute: _speedtestTime.minute,
        ),
      );
      if (!mounted) return;
      _showSnack('Network performance settings saved.');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to save settings: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String message) {
    if (message.startsWith('Failed') || message.startsWith('Enter')) {
      context.showToastError(message, actionKey: 'performance-settings');
    } else {
      context.showToastSuccess(message, actionKey: 'performance-settings');
    }
  }

  Future<void> _selectSpeedtestTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _speedtestTime,
    );
    if (pickedTime != null && mounted) {
      setState(() => _speedtestTime = pickedTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Performance Settings', showBack: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SettingsCard(
                  title: 'Ping Test',
                  icon: Icons.network_ping_rounded,
                  children: [
                    TextField(
                      controller: _pingTargetController,
                      decoration: const InputDecoration(
                        labelText: 'Target',
                        hintText: '1.1.1.1',
                        prefixIcon: Icon(Icons.public_rounded),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      enabled: !_isSaving,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _pingThresholdController,
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
                const SizedBox(height: 12),
                _SettingsCard(
                  title: 'DNS Test',
                  icon: Icons.dns_rounded,
                  children: [
                    TextField(
                      controller: _dnsHostnameController,
                      decoration: const InputDecoration(
                        labelText: 'Hostname',
                        hintText: 'openwrt.org',
                        prefixIcon: Icon(Icons.travel_explore_rounded),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      enabled: !_isSaving,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  title: 'Speedtest',
                  icon: Icons.speed_rounded,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Scheduled Speedtest'),
                      subtitle: Text(
                        _speedtestEnabled ? 'Enabled' : 'Disabled',
                      ),
                      value: _speedtestEnabled,
                      onChanged: _isSaving
                          ? null
                          : (value) =>
                                setState(() => _speedtestEnabled = value),
                    ),
                    const Divider(height: 24),
                    _PickerTile(
                      icon: Icons.schedule_rounded,
                      title: 'Every day at',
                      value: _speedtestTime.format(context),
                      onTap: _isSaving ? null : _selectSpeedtestTime,
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

class _SettingsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary),
                const SizedBox(width: 10),
                Text(title, style: LuciTextStyles.cardTitle(context)),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
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
