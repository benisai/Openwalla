import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/openwrt_feature_gate.dart';

const List<_AdblockFeedOption> _adblockFeedOptions = [
  _AdblockFeedOption('adguard', 'AdGuard', 'L, general'),
  _AdblockFeedOption('adguard_tracking', 'AdGuard Tracking', 'L, tracking'),
  _AdblockFeedOption('certpl', 'CERT Polska', 'L, phishing'),
  _AdblockFeedOption('1hosts', '1Hosts', 'VAR, compilation'),
  _AdblockFeedOption('android_tracking', 'Android Tracking', 'S, tracking'),
  _AdblockFeedOption('andryou', 'Andryou', 'L, compilation'),
  _AdblockFeedOption('anti_ad', 'Anti-AD', 'L, compilation'),
  _AdblockFeedOption('anudeep', 'Anudeep', 'M, compilation'),
  _AdblockFeedOption('bitcoin', 'Bitcoin', 'S, mining'),
  _AdblockFeedOption('cpbl', 'CPBL', 'XL, compilation'),
  _AdblockFeedOption('disconnect', 'Disconnect', 'S, general'),
  _AdblockFeedOption('doh_blocklist', 'DoH Blocklist', 'S, doh server'),
  _AdblockFeedOption('firetv_tracking', 'Fire TV Tracking', 'S, tracking'),
  _AdblockFeedOption('hagezi', 'Hagezi', 'VAR, compilation'),
  _AdblockFeedOption('hblock', 'HBlock', 'XL, compilation'),
  _AdblockFeedOption('oisd_small', 'OISD Small', 'L, general'),
  _AdblockFeedOption('phishing_army', 'Phishing Army', 'S, phishing'),
  _AdblockFeedOption('smarttv_tracking', 'Smart TV Tracking', 'S, tracking'),
  _AdblockFeedOption('stevenblack', 'StevenBlack', 'VAR, compilation'),
  _AdblockFeedOption('winspy', 'WinSpy', 'S, telemetry'),
  _AdblockFeedOption('yoyo', 'Yoyo', 'S, general'),
];

class _AdblockFeedOption {
  final String id;
  final String label;
  final String detail;

  const _AdblockFeedOption(this.id, this.label, this.detail);
}

class AdblockScreen extends ConsumerStatefulWidget {
  const AdblockScreen({super.key});

  @override
  ConsumerState<AdblockScreen> createState() => _AdblockScreenState();
}

class _AdblockScreenState extends ConsumerState<AdblockScreen> {
  OpenwrtAdblockSettings? _settings;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasStartedLoad = false;
  String? _error;
  String? _feedSaveStatus;
  Timer? _feedSaveTimer;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final settings = await ref
          .read(appStateProvider)
          .fetchAdblockSettings(context: context);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _isLoading = false;
        _isSaving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load AdBlock settings.';
        _isLoading = false;
      });
    }
  }

  void _update(OpenwrtAdblockSettings settings) {
    setState(() => _settings = settings);
  }

  void _updateFeeds(OpenwrtAdblockSettings settings) {
    _feedSaveTimer?.cancel();
    setState(() {
      _settings = settings;
      _feedSaveStatus = 'Saving...';
    });
    _feedSaveTimer = Timer(const Duration(milliseconds: 500), () async {
      await _saveFeedSelection(settings);
    });
  }

  Future<void> _saveFeedSelection(OpenwrtAdblockSettings settings) async {
    if (!mounted) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(appStateProvider).saveAdblockSettings(settings);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _isSaving = false;
        _feedSaveStatus = 'Saved automatically';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _feedSaveStatus = 'Save failed';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save feeds: $e')));
    }
  }

  Future<void> _save() async {
    _feedSaveTimer?.cancel();
    final settings = _settings;
    if (settings == null) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(appStateProvider).saveAdblockSettings(settings);
      if (!mounted) return;
      setState(() => _feedSaveStatus = 'Changes saved');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('AdBlock settings saved.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save AdBlock: $e')));
      setState(() => _isSaving = false);
    }
  }

  Future<void> _runAction(String action) async {
    _feedSaveTimer?.cancel();
    setState(() => _isSaving = true);
    try {
      await ref.read(appStateProvider).runAdblockServiceAction(action);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('AdBlock $action requested.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to run AdBlock action: $e')),
      );
      setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _feedSaveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = _settings;

    return Scaffold(
      appBar: const LuciAppBar(title: 'AdBlock', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                'DNS-Based AdBlock',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Manage OpenWrt adblock service settings and runtime actions.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 18),
              OpenwrtFeatureGate(
                feature: OpenwrtFeature.adblock,
                title: 'AdBlock is not installed',
                message:
                    'Install the OpenWrt adblock package before managing DNS blocklists and AdBlock service actions.',
                installLabel: 'Install AdBlock',
                builder: (_) => _buildInstalledContent(settings),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstalledContent(OpenwrtAdblockSettings? settings) {
    if (!_hasStartedLoad) {
      _hasStartedLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return _AdblockEmptyCard(message: _error!, onRefresh: _load);
    }
    if (settings == null) return const SizedBox.shrink();
    return _AdblockEditor(
      settings: settings,
      isSaving: _isSaving,
      feedSaveStatus: _feedSaveStatus,
      onChanged: _update,
      onFeedsChanged: _updateFeeds,
      onSave: _save,
      onAction: _runAction,
    );
  }
}

class _AdblockEditor extends StatelessWidget {
  final OpenwrtAdblockSettings settings;
  final bool isSaving;
  final String? feedSaveStatus;
  final ValueChanged<OpenwrtAdblockSettings> onChanged;
  final ValueChanged<OpenwrtAdblockSettings> onFeedsChanged;
  final VoidCallback onSave;
  final ValueChanged<String> onAction;

  const _AdblockEditor({
    required this.settings,
    required this.isSaving,
    required this.feedSaveStatus,
    required this.onChanged,
    required this.onFeedsChanged,
    required this.onSave,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = settings.installed
        ? colorScheme.primary
        : colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AdblockSectionCard(
          title: 'Feeds',
          icon: Icons.playlist_add_check_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${settings.selectedFeeds.length} selected',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: feedSaveStatus == null
                        ? const SizedBox.shrink()
                        : Row(
                            key: ValueKey(feedSaveStatus),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSaving)
                                const SizedBox.square(
                                  dimension: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                Icon(
                                  feedSaveStatus!.contains('failed')
                                      ? Icons.error_outline_rounded
                                      : Icons.cloud_done_outlined,
                                  size: 17,
                                  color: feedSaveStatus!.contains('failed')
                                      ? colorScheme.error
                                      : colorScheme.primary,
                                ),
                              const SizedBox(width: 6),
                              Text(
                                feedSaveStatus!,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: feedSaveStatus!.contains('failed')
                                          ? colorScheme.error
                                          : colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Changes save automatically. Larger feeds use more router memory.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 560 ? 2 : 1;
                  final width = columns == 2
                      ? (constraints.maxWidth - 10) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: _adblockFeedOptions.map((feed) {
                      final selected = settings.selectedFeeds.contains(feed.id);
                      return SizedBox(
                        width: width,
                        child: _AdblockFeedTile(
                          feed: feed,
                          selected: selected,
                          enabled: !isSaving,
                          onTap: () {
                            final next = [...settings.selectedFeeds];
                            if (selected) {
                              next.remove(feed.id);
                            } else {
                              next.add(feed.id);
                            }
                            onFeedsChanged(
                              settings.copyWith(selectedFeeds: next),
                            );
                          },
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _AdblockSectionCard(
          title: 'Settings',
          icon: Icons.tune_rounded,
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable SafeSearch'),
                subtitle: const Text(
                  'Apply safe search rules where supported.',
                ),
                value: settings.safeSearch,
                onChanged: isSaving
                    ? null
                    : (value) =>
                          onChanged(settings.copyWith(safeSearch: value)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: settings.triggerInterface,
                enabled: !isSaving,
                decoration: const InputDecoration(
                  labelText: 'Startup trigger interface',
                  hintText: 'wan',
                ),
                onChanged: (value) =>
                    onChanged(settings.copyWith(triggerInterface: value)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: isSaving ? null : onSave,
                icon: isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(isSaving ? 'Applying' : 'Apply Settings'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _AdblockSectionCard(
          title: 'Service Controls',
          icon: Icons.settings_power_rounded,
          initiallyExpanded: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.block_rounded, color: statusColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          settings.installed
                              ? 'AdBlock installed'
                              : 'Not installed',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          settings.serviceStatus,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable AdBlock service'),
                value: settings.enabled,
                onChanged: isSaving
                    ? null
                    : (value) => onChanged(settings.copyWith(enabled: value)),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: isSaving ? null : onSave,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Apply Service State'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ActionChipButton(
                    label: 'Start',
                    enabled: !isSaving,
                    onTap: () => onAction('start'),
                  ),
                  _ActionChipButton(
                    label: 'Stop',
                    enabled: !isSaving,
                    onTap: () => onAction('stop'),
                  ),
                  _ActionChipButton(
                    label: 'Reload',
                    enabled: !isSaving,
                    onTap: () => onAction('reload'),
                  ),
                  _ActionChipButton(
                    label: 'Restart',
                    enabled: !isSaving,
                    onTap: () => onAction('restart'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdblockFeedTile extends StatelessWidget {
  const _AdblockFeedTile({
    required this.feed,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final _AdblockFeedOption feed;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final detailParts = feed.detail.split(',');
    final size = detailParts.first.trim();
    final category = detailParts.length > 1
        ? detailParts.sublist(1).join(',').trim()
        : '';

    return Material(
      color: selected
          ? colors.primaryContainer.withValues(alpha: 0.55)
          : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 62),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? colors.primary
                  : colors.outlineVariant.withValues(alpha: 0.6),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? colors.primary : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? colors.primary : colors.outline,
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        color: colors.onPrimary,
                        size: 18,
                      )
                    : null,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feed.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category.isEmpty ? size : '$category  |  $size',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdblockSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;

  const _AdblockSectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.initiallyExpanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: initiallyExpanded
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: colorScheme.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  child,
                ],
              ),
            )
          : Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                leading: Icon(icon, color: colorScheme.primary, size: 22),
                title: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                children: [child],
              ),
            ),
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionChipButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: enabled ? onTap : null,
      avatar: const Icon(Icons.terminal_rounded, size: 18),
    );
  }
}

class _AdblockEmptyCard extends StatelessWidget {
  final String message;
  final Future<void> Function() onRefresh;

  const _AdblockEmptyCard({required this.message, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}
