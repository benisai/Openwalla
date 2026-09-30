import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/design/luci_design_system.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class UsageSettingsScreen extends ConsumerStatefulWidget {
  const UsageSettingsScreen({super.key});

  @override
  ConsumerState<UsageSettingsScreen> createState() =>
      _UsageSettingsScreenState();
}

class _UsageSettingsScreenState extends ConsumerState<UsageSettingsScreen> {
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
    final now = DateTime.now();
    final safeDay = settings.monthStartDay.clamp(1, 28);

    setState(() {
      _interfaces = interfaces;
      _selectedInterface = selectedInterface;
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
    for (final name in names) {
      if (name.toLowerCase() == savedLower) return name;
    }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Usage settings saved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save usage settings: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
      appBar: const LuciAppBar(title: 'Usage Settings', showBack: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.query_stats_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'vnStat Usage Source',
                              style: LuciTextStyles.cardTitle(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _PickerTile(
                          icon: Icons.event_available_rounded,
                          title: 'Monthly Start Date',
                          value: _formatDate(_startDate),
                          onTap: _isSaving ? null : _selectStartDate,
                        ),
                        const SizedBox(height: 14),
                        if (_interfaces.isEmpty)
                          const _UsageSettingsNotice(
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
                                              setState(() {
                                                _selectedInterface = value;
                                              });
                                            }
                                          },
                                  ),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 14),
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
                  ),
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

class _UsageSettingsNotice extends StatelessWidget {
  final String message;

  const _UsageSettingsNotice({required this.message});

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

String _formatDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
