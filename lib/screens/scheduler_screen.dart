import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/client.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/hide_dashboard_shortcut_button.dart';

class SchedulerScreen extends ConsumerStatefulWidget {
  const SchedulerScreen({super.key});

  @override
  ConsumerState<SchedulerScreen> createState() => _SchedulerScreenState();
}

class _SchedulerScreenState extends ConsumerState<SchedulerScreen> {
  List<OpenwallaDeviceSchedule> _schedules = const [];
  List<Client> _clients = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final appState = ref.read(appStateProvider);
      final results = await Future.wait([
        appState.fetchDeviceSchedules(context: context),
        appState.fetchClientsForSelectedRouter(),
      ]);
      if (!mounted) return;
      setState(() {
        _schedules = results[0] as List<OpenwallaDeviceSchedule>;
        _clients = results[1] as List<Client>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            'Unable to load schedules. Install the Openwalla scheduler from Router Setup.';
        _isLoading = false;
      });
    }
  }

  Future<void> _openEditor([OpenwallaDeviceSchedule? schedule]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) =>
          _ScheduleEditorSheet(schedule: schedule, clients: _clients),
    );
    if (saved == true) await _load();
  }

  Future<void> _pauseSchedule(
    OpenwallaDeviceSchedule schedule,
    Duration duration,
  ) async {
    try {
      await ref
          .read(appStateProvider)
          .pauseDeviceSchedule(schedule, duration, context: context);
      if (!mounted) return;
      final label = duration.inMinutes >= 60
          ? '${duration.inHours} hour${duration.inHours == 1 ? '' : 's'}'
          : '${duration.inMinutes} minutes';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paused ${schedule.name} for $label.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to pause schedule: $e')));
    }
  }

  Future<void> _resumeSchedule(OpenwallaDeviceSchedule schedule) async {
    try {
      await ref
          .read(appStateProvider)
          .resumeDeviceSchedule(schedule, context: context);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Resumed ${schedule.name}.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to resume schedule: $e')));
    }
  }

  Future<void> _showActivityLog() async {
    var activity = await ref
        .read(appStateProvider)
        .fetchScheduleActivity(context: context);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return FractionallySizedBox(
            heightFactor: 0.72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 8, 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Activity Log',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      TextButton(
                        onPressed: activity.isEmpty
                            ? null
                            : () async {
                                await ref
                                    .read(appStateProvider)
                                    .clearScheduleActivity(context: context);
                                if (sheetContext.mounted) {
                                  setSheetState(() => activity = const []);
                                }
                              },
                        child: const Text('Clear'),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: activity.isEmpty
                      ? Center(
                          child: Text(
                            'No profile activity yet.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: activity.length,
                          separatorBuilder: (_, _) => const Divider(height: 20),
                          itemBuilder: (context, index) {
                            final entry = activity[index];
                            final local = entry.timestamp.toLocal();
                            final minute = local.minute.toString().padLeft(
                              2,
                              '0',
                            );
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                _activityIcon(entry.action),
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              title: Text(
                                '${entry.profileName}: ${entry.action}',
                              ),
                              subtitle: Text(
                                '${local.month}/${local.day}/${local.year} '
                                '${local.hour}:$minute'
                                '${entry.detail.isEmpty ? '' : ' · ${entry.detail}'}',
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  IconData _activityIcon(String action) {
    final normalized = action.toLowerCase();
    if (normalized.contains('created')) return Icons.person_add_alt_1_rounded;
    if (normalized.contains('deleted')) return Icons.delete_outline_rounded;
    if (normalized.contains('paused')) {
      return Icons.pause_circle_outline_rounded;
    }
    if (normalized.contains('resumed')) {
      return Icons.play_circle_outline_rounded;
    }
    return Icons.edit_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Parental Controls',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Activity log',
            onPressed: _isLoading ? null : _showActivityLog,
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _ScheduleEmptyCard(
                icon: Icons.event_busy_rounded,
                title: 'Scheduler not ready',
                message: _error!,
                onRefresh: _load,
                showHideShortcut: true,
              )
            else if (_schedules.isEmpty)
              _ScheduleEmptyCard(
                icon: Icons.schedule_rounded,
                title: 'No profiles yet',
                message:
                    'Create a profile, assign devices, and set a block schedule.',
                onRefresh: _load,
              )
            else
              ..._schedules.map(
                (schedule) => _ScheduleCard(
                  schedule: schedule,
                  onTap: () => _openEditor(schedule),
                  onPause: (duration) => _pauseSchedule(schedule, duration),
                  onResume: () => _resumeSchedule(schedule),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Profile'),
            ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final OpenwallaDeviceSchedule schedule;
  final VoidCallback onTap;
  final ValueChanged<Duration> onPause;
  final VoidCallback onResume;

  const _ScheduleCard({
    required this.schedule,
    required this.onTap,
    required this.onPause,
    required this.onResume,
  });

  String _formatPauseUntil() {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(
      schedule.pauseUntil * 1000,
    ).toLocal();
    final hour12 = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final suffix = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = schedule.enabled
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    final isPaused = schedule.isPaused;
    final subtitle = isPaused
        ? 'Paused until ${_formatPauseUntil()}'
        : '${schedule.startTime} to ${schedule.endTime} • ${schedule.macAddresses.length} devices';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: activeColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        _profileIcon(schedule.name),
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          schedule.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: isPaused
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Schedule actions',
                    icon: const Icon(Icons.more_horiz_rounded),
                    onSelected: (value) {
                      switch (value) {
                        case 'pause30':
                          onPause(const Duration(minutes: 30));
                        case 'pause60':
                          onPause(const Duration(hours: 1));
                        case 'pause120':
                          onPause(const Duration(hours: 2));
                        case 'resume':
                          onResume();
                      }
                    },
                    itemBuilder: (context) => [
                      if (isPaused)
                        const PopupMenuItem(
                          value: 'resume',
                          child: Text('Resume now'),
                        ),
                      const PopupMenuItem(
                        value: 'pause30',
                        child: Text('Pause 30 minutes'),
                      ),
                      const PopupMenuItem(
                        value: 'pause60',
                        child: Text('Pause 1 hour'),
                      ),
                      const PopupMenuItem(
                        value: 'pause120',
                        child: Text('Pause 2 hours'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isPaused
                    ? onResume
                    : () => onPause(const Duration(hours: 1)),
                icon: Icon(
                  isPaused
                      ? Icons.play_circle_outline_rounded
                      : Icons.pause_circle_outline_rounded,
                ),
                label: Text(
                  isPaused ? 'Resume Schedule' : 'Pause Schedule for 1 Hour',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _profileIcon(String name) {
    const icons = ['🧒', '👧', '👦', '👩', '👨', '🎮', '⭐', '🏠'];
    return icons[name.codeUnits.fold<int>(0, (sum, value) => sum + value) %
        icons.length];
  }
}

class _ScheduleEmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function() onRefresh;
  final bool showHideShortcut;

  const _ScheduleEmptyCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRefresh,
    this.showHideShortcut = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, color: colorScheme.primary, size: 34),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Check Again'),
            ),
            if (showHideShortcut)
              const HideDashboardShortcutButton(
                shortcutId: 'scheduler',
                shortcutLabel: 'Scheduler',
              ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleEditorSheet extends ConsumerStatefulWidget {
  final OpenwallaDeviceSchedule? schedule;
  final List<Client> clients;

  const _ScheduleEditorSheet({required this.schedule, required this.clients});

  @override
  ConsumerState<_ScheduleEditorSheet> createState() =>
      _ScheduleEditorSheetState();
}

class _ScheduleEditorSheetState extends ConsumerState<_ScheduleEditorSheet> {
  final _nameController = TextEditingController();
  final _startController = TextEditingController();
  final _endController = TextEditingController();
  final _manualMacController = TextEditingController();
  final Set<String> _selectedMacs = {};
  bool _enabled = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final schedule = widget.schedule;
    _nameController.text = schedule?.name ?? '';
    _startController.text = schedule?.startTime ?? '21:00';
    _endController.text = schedule?.endTime ?? '07:00';
    _enabled = schedule?.enabled ?? true;
    _selectedMacs.addAll(
      schedule?.macAddresses.map(_normalizeMac) ?? const <String>[],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _startController.dispose();
    _endController.dispose();
    _manualMacController.dispose();
    super.dispose();
  }

  String _normalizeMac(String mac) =>
      mac.trim().toUpperCase().replaceAll('-', ':');

  bool _validTime(String value) {
    return RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value.trim());
  }

  void _addManualMac() {
    final mac = _normalizeMac(_manualMacController.text);
    if (!RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(mac)) {
      _showError('Enter a valid MAC address.');
      return;
    }
    setState(() {
      _selectedMacs.add(mac);
      _manualMacController.clear();
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Profile name is required.');
      return;
    }
    if (!_validTime(_startController.text) ||
        !_validTime(_endController.text)) {
      _showError('Use 24-hour time like 21:00.');
      return;
    }
    if (_selectedMacs.isEmpty) {
      _showError('Choose at least one device.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .saveDeviceSchedule(
            OpenwallaDeviceSchedule(
              id: widget.schedule?.id ?? 0,
              name: name,
              startTime: _startController.text.trim(),
              endTime: _endController.text.trim(),
              enabled: _enabled,
              macAddresses: _selectedMacs.toList(),
            ),
            context: context,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to save schedule: $e');
      setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    final schedule = widget.schedule;
    if (schedule == null || schedule.isNew) return;
    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .deleteDeviceSchedule(schedule, context: context);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to delete schedule: $e');
      setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final clients =
        widget.clients
            .where((client) => _normalizeMac(client.macAddress).isNotEmpty)
            .toList()
          ..sort(
            (a, b) =>
                a.hostname.toLowerCase().compareTo(b.hostname.toLowerCase()),
          );

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            0,
            18,
            MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      widget.schedule == null
                          ? Icons.person_add_alt_1_rounded
                          : Icons.manage_accounts_rounded,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.schedule == null
                            ? 'New Profile'
                            : 'Edit Profile',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.45),
                    ),
                  ),
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      Icons.shield_outlined,
                      color: colorScheme.primary,
                    ),
                    title: const Text('Profile Guardrails Active'),
                    subtitle: const Text(
                      'The block schedule is enforced for assigned devices.',
                    ),
                    value: _enabled,
                    onChanged: _isSaving
                        ? null
                        : (value) => setState(() => _enabled = value),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  enabled: !_isSaving,
                  decoration: const InputDecoration(
                    labelText: 'Profile Name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Block Schedule',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set the recurring time when assigned devices are blocked.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _startController,
                        enabled: !_isSaving,
                        decoration: const InputDecoration(
                          labelText: 'Start',
                          hintText: '21:00',
                          prefixIcon: Icon(Icons.schedule_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _endController,
                        enabled: !_isSaving,
                        decoration: const InputDecoration(
                          labelText: 'End',
                          hintText: '07:00',
                          prefixIcon: Icon(Icons.alarm_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Assigned Devices',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualMacController,
                        enabled: !_isSaving,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Manual MAC Address',
                          prefixIcon: Icon(Icons.devices_other_rounded),
                        ),
                        onSubmitted: (_) => _addManualMac(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      tooltip: 'Add MAC address',
                      onPressed: _isSaving ? null : _addManualMac,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (clients.isEmpty)
                  Text(
                    'No devices found yet.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  )
                else
                  ...clients.map((client) {
                    final mac = _normalizeMac(client.macAddress);
                    final selected = _selectedMacs.contains(mac);
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(client.hostname),
                      subtitle: Text(mac),
                      value: selected,
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              setState(() {
                                if (value ?? false) {
                                  _selectedMacs.add(mac);
                                } else {
                                  _selectedMacs.remove(mac);
                                }
                              });
                            },
                    );
                  }),
                ..._selectedMacs
                    .where(
                      (mac) => !clients.any(
                        (client) => _normalizeMac(client.macAddress) == mac,
                      ),
                    )
                    .map(
                      (mac) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Manually assigned device'),
                        subtitle: Text(mac),
                        value: true,
                        onChanged: _isSaving
                            ? null
                            : (_) => setState(() => _selectedMacs.remove(mac)),
                      ),
                    ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (widget.schedule != null) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isSaving ? null : _delete,
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Delete'),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          _isSaving
                              ? 'Saving'
                              : widget.schedule == null
                              ? 'Create Profile'
                              : 'Save Profile',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
