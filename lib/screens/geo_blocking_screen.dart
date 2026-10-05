import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/data/geo_countries.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/utils/geo_blocking.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/openwrt_feature_gate.dart';
import 'package:openwalla/widgets/ssh_console_sheet.dart';

class GeoBlockingScreen extends ConsumerStatefulWidget {
  const GeoBlockingScreen({super.key});

  @override
  ConsumerState<GeoBlockingScreen> createState() => _GeoBlockingScreenState();
}

class _GeoBlockingScreenState extends ConsumerState<GeoBlockingScreen> {
  Set<String> _selectedCountryCodes = {};
  bool _started = false;
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  String _status = '';
  String? _error;

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
        if (countries != null && _selectedCountryCodes.isEmpty) {
          _selectedCountryCodes = countries.split(' ').toSet();
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
      countries = normalizeGeoCountryCodes(_selectedCountryCodes.join(' '));
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
          'Openwalla will block inbound and outbound connections involving $countries. Existing established connections remain allowed.',
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
    final console = SshConsoleController(
      initialOutput:
          'Connecting to router...\nInitializing GeoIP country lists...\n',
      running: true,
    );
    unawaited(
      showSshConsoleSheet(
        context: context,
        controller: console,
        title: 'Applying Geo-Blocking',
      ).whenComplete(console.dispose),
    );
    try {
      final outputBuffer = StringBuffer();
      await ref
          .read(appStateProvider)
          .configureGeoBlockingCountries(
            countries,
            onOutput: (chunk) {
              outputBuffer.write(chunk);
              console.setOutput(outputBuffer.toString().trimRight());
            },
          );
      _selectedCountryCodes = countries.split(' ').toSet();
      await _load();
      if (!mounted) return;
      if (outputBuffer.isEmpty) {
        console.setOutput('GeoIP configuration completed.');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Blocked countries updated.')),
      );
    } catch (error) {
      console.setOutput(
        'GeoIP configuration failed.\n\n'
        '${error.toString().replaceFirst('Bad state: ', '')}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    } finally {
      console.complete();
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

  Future<void> _chooseCountries() async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _GeoCountryPicker(initialSelection: _selectedCountryCodes),
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedCountryCodes = selected);
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
                    'Install the bundled geoip-shell source to block inbound and outbound connections by country.',
                warning:
                    'Country IP lists use router memory. Large countries may need substantially more RAM.',
                installLabel: 'Install Geo-Blocking',
                installOptions: const [
                  OpenwrtFeatureInstallOption(
                    feature: 'geoip-nftables',
                    label: 'nftables',
                    description:
                        'geoip-shell_0.8.5-r1.apk for standard firewall4 OpenWrt.',
                    icon: Icons.security_rounded,
                  ),
                  OpenwrtFeatureInstallOption(
                    feature: 'geoip-iptables',
                    label: 'iptables',
                    description:
                        'geoip-shell-iptables_0.8.5-r1.apk for legacy firewalls.',
                    icon: Icons.shield_outlined,
                  ),
                ],
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
            subtitle: const Text('Inbound and outbound country blacklist'),
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
                'Choose the countries to block in both directions.',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _saving ? null : _chooseCountries,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Countries',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedCountryCodes.isEmpty
                              ? 'Select countries'
                              : '${_selectedCountryCodes.length} selected',
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down_rounded),
                    ],
                  ),
                ),
              ),
              if (_selectedCountryCodes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ..._selectedCountries
                        .take(8)
                        .map(
                          (country) => InputChip(
                            label: Text('${country.name} (${country.code})'),
                            onDeleted: _saving
                                ? null
                                : () => setState(
                                    () => _selectedCountryCodes.remove(
                                      country.code,
                                    ),
                                  ),
                          ),
                        ),
                    if (_selectedCountryCodes.length > 8)
                      Chip(
                        label: Text(
                          '+${_selectedCountryCodes.length - 8} more',
                        ),
                      ),
                  ],
                ),
              ],
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

  List<GeoCountry> get _selectedCountries => geoCountries
      .where((country) => _selectedCountryCodes.contains(country.code))
      .toList();
}

class _GeoCountryPicker extends StatefulWidget {
  final Set<String> initialSelection;

  const _GeoCountryPicker({required this.initialSelection});

  @override
  State<_GeoCountryPicker> createState() => _GeoCountryPickerState();
}

class _GeoCountryPickerState extends State<_GeoCountryPicker> {
  final _searchController = TextEditingController();
  late Set<String> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialSelection};
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GeoCountry> get _filteredCountries {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return geoCountries;
    return geoCountries
        .where(
          (country) =>
              country.name.toLowerCase().contains(query) ||
              country.code.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final countries = _filteredCountries;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.88,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Blocked Countries',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => setState(_selected.clear),
                  child: const Text('Clear'),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search country or code',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: countries.isEmpty
                ? const Center(child: Text('No countries found.'))
                : ListView.builder(
                    itemCount: countries.length,
                    itemBuilder: (context, index) {
                      final country = countries[index];
                      final selected = _selected.contains(country.code);
                      return CheckboxListTile(
                        value: selected,
                        title: Text(country.name),
                        secondary: SizedBox(
                          width: 36,
                          child: Text(
                            country.code,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selected.add(country.code);
                            } else {
                              _selected.remove(country.code);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(_selected),
                icon: const Icon(Icons.check_rounded),
                label: Text(
                  _selected.isEmpty ? 'Done' : 'Done (${_selected.length})',
                ),
              ),
            ),
          ),
        ],
      ),
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
