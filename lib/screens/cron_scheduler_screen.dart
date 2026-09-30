import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/cron_job.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class CronSchedulerScreen extends ConsumerStatefulWidget {
  const CronSchedulerScreen({super.key});

  @override
  ConsumerState<CronSchedulerScreen> createState() =>
      _CronSchedulerScreenState();
}

class _CronSchedulerScreenState extends ConsumerState<CronSchedulerScreen> {
  CronDocument? _document;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final content = await ref
          .read(appStateProvider)
          .fetchRootCrontab(context: context);
      if (!mounted) return;
      setState(() => _document = CronDocument.parse(content));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _save(String content) async {
    setState(() => _saving = true);
    final saved = await ref
        .read(appStateProvider)
        .saveRootCrontab(content, context: context);
    if (!mounted) return false;
    setState(() => _saving = false);
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scheduled tasks could not be saved.')),
      );
      return false;
    }
    setState(() => _document = CronDocument.parse(content));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Scheduled tasks updated.')));
    return true;
  }

  Future<void> _openEditor([CronJob? job]) async {
    final result = await showModalBottomSheet<_CronEditorResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CronEditorSheet(job: job),
    );
    if (result == null || !mounted || _document == null) return;
    switch (result.action) {
      case _CronEditorAction.save:
        final updated = result.job!;
        await _save(
          job == null
              ? _document!.append(updated)
              : _document!.replace(job, updated),
        );
      case _CronEditorAction.delete:
        if (job != null) await _save(_document!.delete(job));
    }
  }

  Future<void> _toggle(CronJob job, bool enabled) async {
    if (_document == null) return;
    await _save(_document!.replace(job, job.copyWith(isEnabled: enabled)));
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _document?.jobs ?? const <CronJob>[];
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Scheduler',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Refresh scheduled tasks',
            onPressed: _saving ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 100),
          children: [
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'System Scheduled Cron Jobs',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _openEditor(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Task'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              _MessageCard(
                icon: Icons.error_outline_rounded,
                title: 'Unable to load scheduled tasks',
                message: _error!,
                actionLabel: 'Try Again',
                onAction: _load,
              )
            else if (jobs.isEmpty)
              _MessageCard(
                icon: Icons.schedule_rounded,
                title: 'No scheduled tasks',
                message:
                    'Create a task to run a router command on a recurring schedule.',
                actionLabel: 'Create First Task',
                onAction: () => _openEditor(),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    for (var index = 0; index < jobs.length; index++) ...[
                      if (index > 0)
                        const Divider(height: 1, indent: 16, endIndent: 16),
                      _CronJobTile(
                        job: jobs[index],
                        busy: _saving,
                        onToggle: (value) => _toggle(jobs[index], value),
                        onEdit: () => _openEditor(jobs[index]),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CronJobTile extends StatelessWidget {
  const _CronJobTile({
    required this.job,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
  });

  final CronJob job;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 10, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (job.isEnabled ? colors.primary : colors.onSurfaceVariant)
                  .withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.schedule_rounded,
              color: job.isEnabled ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.command,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    decoration: job.isEnabled
                        ? null
                        : TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  CronSchedule.describe(job.expression),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  job.expression,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            children: [
              Switch.adaptive(
                value: job.isEnabled,
                onChanged: busy ? null : onToggle,
              ),
              IconButton(
                tooltip: 'Edit task',
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _CronEditorAction { save, delete }

class _CronEditorResult {
  const _CronEditorResult(this.action, [this.job]);

  final _CronEditorAction action;
  final CronJob? job;
}

class _CronEditorSheet extends StatefulWidget {
  const _CronEditorSheet({this.job});

  final CronJob? job;

  @override
  State<_CronEditorSheet> createState() => _CronEditorSheetState();
}

class _CronEditorSheetState extends State<_CronEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _expressionController;
  late final TextEditingController _commandController;
  late bool _enabled;
  late String _preset;

  @override
  void initState() {
    super.initState();
    _expressionController = TextEditingController(
      text: widget.job?.expression ?? '0 4 * * *',
    );
    _commandController = TextEditingController(text: widget.job?.command ?? '');
    _enabled = widget.job?.isEnabled ?? true;
    _preset = _matchingPreset(_expressionController.text);
  }

  String _matchingPreset(String expression) {
    for (final preset in cronPresets) {
      if (preset.expression == expression) return preset.label;
    }
    return 'Custom Expression';
  }

  @override
  void dispose() {
    _expressionController.dispose();
    _commandController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _CronEditorResult(
        _CronEditorAction.save,
        CronJob(
          expression: _expressionController.text.trim(),
          command: _commandController.text.trim(),
          isEnabled: _enabled,
          sourceLineIndex: widget.job?.sourceLineIndex ?? -1,
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Scheduled Task?'),
        content: Text(
          'Delete “${widget.job!.command}”? This command will no longer run.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(
        context,
      ).pop(const _CronEditorResult(_CronEditorAction.delete));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final editing = widget.job != null;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              color: colors.onSurfaceVariant.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
            child: Row(
              children: [
                Icon(
                  editing
                      ? Icons.edit_calendar_rounded
                      : Icons.add_alarm_rounded,
                  color: colors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    editing ? 'Edit Scheduled Task' : 'Add New Scheduled Task',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottomInset),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _preset,
                      decoration: const InputDecoration(
                        labelText: 'Schedule Preset',
                        prefixIcon: Icon(Icons.speed_rounded),
                        border: OutlineInputBorder(),
                      ),
                      items: cronPresets
                          .map(
                            (preset) => DropdownMenuItem(
                              value: preset.label,
                              child: Text(preset.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _preset = value;
                          final preset = cronPresets.firstWhere(
                            (item) => item.label == value,
                          );
                          if (preset.expression.isNotEmpty) {
                            _expressionController.text = preset.expression;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _expressionController,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'Cron Expression (5 fields)',
                        prefixIcon: Icon(Icons.schedule_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => CronSchedule.validate(value ?? ''),
                      onChanged: (value) => setState(() {
                        _preset = _matchingPreset(value.trim());
                      }),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              CronSchedule.describe(
                                _expressionController.text.trim(),
                              ),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _commandController,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'Command to Execute',
                        prefixIcon: Icon(Icons.terminal_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final command = value?.trim() ?? '';
                        if (command.isEmpty) return 'Enter a command';
                        if (command.contains('\n') || command.contains('\r')) {
                          return 'Commands cannot contain new lines';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CommandChip(
                          'Reboot Router',
                          '/sbin/reboot',
                          _commandController,
                        ),
                        _CommandChip(
                          'Network Monitor',
                          '/usr/bin/openwalla-network-monitor --once',
                          _commandController,
                        ),
                        _CommandChip(
                          'Reload Wi-Fi',
                          '/sbin/wifi reload',
                          _commandController,
                        ),
                        _CommandChip(
                          'Restart Network',
                          '/etc/init.d/network restart',
                          _commandController,
                        ),
                        _CommandChip(
                          'Restart DDNS',
                          '/etc/init.d/ddns restart',
                          _commandController,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Task Active State',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _enabled
                            ? 'Task will run on this schedule'
                            : 'Task is disabled',
                      ),
                      value: _enabled,
                      onChanged: (value) => setState(() => _enabled = value),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        if (editing) ...[
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colors.error,
                                side: BorderSide(color: colors.error),
                              ),
                              onPressed: _delete,
                              child: const Text('Delete'),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: FilledButton(
                            onPressed: _save,
                            child: Text(editing ? 'Save' : 'Add'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandChip extends StatelessWidget {
  const _CommandChip(this.label, this.command, this.controller);

  final String label;
  final String command;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.add_rounded, size: 16),
      label: Text(label),
      onPressed: () => controller.text = command,
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
