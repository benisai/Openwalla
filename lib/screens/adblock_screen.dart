import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:openwalla/main.dart';
import 'package:openwalla/screens/adblock_reports_screen.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/luci_toast.dart';
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
  OpenwrtAdblockSettings? _savedSettings;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasStartedLoad = false;
  String? _error;
  String? _feedSaveStatus;
  Timer? _feedSaveTimer;

  Future<void> _load() async {
    if (_isSaving || _feedSaveTimer?.isActive == true) return;
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
        _savedSettings = settings;
        _feedSaveStatus = null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load AdBlock settings.';
        _isLoading = false;
      });
    }
  }

  void _updateFeeds(OpenwrtAdblockSettings settings) {
    _feedSaveTimer?.cancel();
    setState(() {
      _settings = settings;
      _feedSaveStatus = 'Saving...';
    });
    _feedSaveTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_save(settings));
    });
  }

  Future<void> _save(
    OpenwrtAdblockSettings settings, {
    bool reports = false,
  }) async {
    if (_isSaving) return;
    _feedSaveTimer?.cancel();
    final savingFeeds = _feedSaveStatus == 'Saving...';
    setState(() {
      _settings = settings;
      _isSaving = true;
    });
    try {
      final state = ref.read(appStateProvider);
      if (reports) {
        await state.setAdblockReportsEnabled(settings);
      } else {
        await state.saveAdblockSettings(settings);
      }
      if (!mounted) return;
      setState(() {
        _savedSettings = settings;
        _isSaving = false;
        if (savingFeeds) _feedSaveStatus = 'Saved';
      });
      if (!savingFeeds) context.showToastSuccess('AdBlock settings saved');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _settings = _savedSettings;
        _isSaving = false;
        if (savingFeeds) _feedSaveStatus = 'Save failed';
      });
      context.showToastError('Could not save AdBlock settings', subtitle: '$e');
    }
  }

  @override
  void dispose() {
    _feedSaveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const LuciAppBar(title: 'AdBlock', showBack: true),
    body: SafeArea(
      top: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            OpenwrtFeatureGate(
              feature: OpenwrtFeature.adblock,
              title: 'AdBlock is not installed',
              message: 'Install the OpenWrt adblock package to manage AdBlock.',
              installLabel: 'Install AdBlock',
              builder: (_) => _buildInstalledContent(),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildInstalledContent() {
    if (!_hasStartedLoad) {
      _hasStartedLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_load());
      });
    }
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Column(
        children: [
          Text(_error!),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      );
    }
    final settings = _settings;
    if (settings == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 2,
          child: _isSaving ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        SwitchListTile.adaptive(
          key: const ValueKey('adblock-enabled'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          secondary: Icon(Icons.shield_outlined, color: colors.primary),
          title: const Text('Block Ads'),
          value: settings.enabled,
          onChanged: _isSaving
              ? null
              : (value) => _save(settings.copyWith(enabled: value)),
        ),
        const Divider(height: 1),
        ExpansionTile(
          key: const PageStorageKey('adblock-feeds'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          leading: Icon(
            Icons.playlist_add_check_rounded,
            color: colors.primary,
          ),
          title: const Text('Feeds'),
          subtitle: Text(
            [
              '${settings.selectedFeeds.length} selected',
              if (_feedSaveStatus != null) _feedSaveStatus!,
            ].join(' - '),
          ),
          shape: const Border(),
          collapsedShape: const Border(),
          children: [
            for (final feed in _adblockFeedOptions)
              CheckboxListTile(
                key: ValueKey('feed-${feed.id}'),
                title: Text(feed.label),
                subtitle: Text(feed.detail),
                value: settings.selectedFeeds.contains(feed.id),
                onChanged: _isSaving
                    ? null
                    : (selected) {
                        final next = [...settings.selectedFeeds];
                        if (selected == true) {
                          next.add(feed.id);
                        } else {
                          next.remove(feed.id);
                        }
                        _updateFeeds(settings.copyWith(selectedFeeds: next));
                      },
              ),
          ],
        ),
        const Divider(height: 1),
        SwitchListTile.adaptive(
          key: const ValueKey('adblock-safesearch'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          secondary: Icon(Icons.search_rounded, color: colors.primary),
          title: const Text('Safe Search'),
          value: settings.safeSearch,
          onChanged: _isSaving
              ? null
              : (value) => _save(settings.copyWith(safeSearch: value)),
        ),
        const Divider(height: 1),
        ListTile(
          key: const ValueKey('adblock-reports'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          leading: Icon(Icons.analytics_outlined, color: colors.primary),
          title: const Text('Reports'),
          onTap: _isSaving || !settings.reportEnabled
              ? null
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdblockReportsScreen(),
                    ),
                  );
                },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch.adaptive(
                key: const ValueKey('adblock-reports-enabled'),
                value: settings.reportEnabled,
                onChanged: _isSaving
                    ? null
                    : (value) => _save(
                        settings.copyWith(reportEnabled: value),
                        reports: true,
                      ),
              ),
              if (settings.reportEnabled)
                const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ],
    );
  }
}
