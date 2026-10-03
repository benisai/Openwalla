import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/utils/geo_blocking.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/openwrt_feature_gate.dart';

class GeoBlockingScreen extends ConsumerStatefulWidget {
  const GeoBlockingScreen({super.key});

  @override
  ConsumerState<GeoBlockingScreen> createState() => _GeoBlockingScreenState();
}

class _GeoBlockingScreenState extends ConsumerState<GeoBlockingScreen> {
  final _countriesController = TextEditingController();
  bool _started = false;
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  String _status = '';
  String? _error;

  @override
  void dispose() {
    _countriesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final output = await ref.read(appStateProvider).fetchGeoBlockingStatus();
      if (!mounted) return;
      final cleanStatus = sanitizeGeoBlockingStatus(output);
      final countries = countryCodesFromGeoBlockingStatus(cleanStatus);
      setState(() {
        _status = cleanStatus;
        _enabled = geoBlockingStatusIsEnabled(cleanStatus);
        if (countries != null && _countriesController.text.trim().isEmpty) {
          _countriesController.text = countries;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Bad state: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _configure() async {
    late final String countries;
    try {
      countries = normalizeGeoCountryCodes(_countriesController.text);
    } on GeoBlockingInputException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update blocked countries?'),
        content: Text(
          'Openwalla will block new inbound connections from $countries. Existing established connections remain allowed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(appStateProvider).configureGeoBlockingCountries(countries);
      _countriesController.text = countries;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Blocked countries updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _saving = true);
    try {
      await ref.read(appStateProvider).setGeoBlockingEnabled(enabled);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Geo-blocking ${enabled ? 'enabled' : 'disabled'}.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Geo-Blocking', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              OpenwrtFeatureGate(
                feature: OpenwrtFeature.geoBlocking,
                title: 'Geo-Blocking is not installed',
                message:
                    'Install the bundled geoip-shell source to block inbound connections by country.',
                warning:
                    'Country IP lists use router memory. Large countries may need substantially more RAM.',
                installLabel: 'Install Geo-Blocking',
                builder: (_) => _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return _GeoCard(
        child: Column(
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GeoCard(
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              Icons.public_off_rounded,
              color: _enabled ? colors.primary : colors.onSurfaceVariant,
            ),
            title: Text(
              _enabled ? 'Protection enabled' : 'Protection disabled',
            ),
            subtitle: const Text('Inbound country blacklist'),
            value: _enabled,
            onChanged: _saving ? null : _setEnabled,
          ),
        ),
        const SizedBox(height: 14),
        _GeoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Blocked Countries',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter two-letter country codes separated by spaces or commas.',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _countriesController,
                enabled: !_saving,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Country codes',
                  hintText: 'CN, RU, KP',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _saving ? null : _configure,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.shield_rounded),
                label: const Text('Apply Blacklist'),
              ),
            ],
          ),
        ),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 14),
          _GeoCard(
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              leading: const Icon(Icons.terminal_rounded),
              title: const Text('Router Status'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    _status,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _GeoCard extends StatelessWidget {
  final Widget child;

  const _GeoCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}
