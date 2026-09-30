import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/client.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/openwrt_feature_gate.dart';
import 'package:url_launcher/url_launcher_string.dart';

class TorScreen extends ConsumerStatefulWidget {
  const TorScreen({super.key});

  @override
  ConsumerState<TorScreen> createState() => _TorScreenState();
}

class _TorScreenState extends ConsumerState<TorScreen> {
  OpenwallaTorSettings _settings = const OpenwallaTorSettings();
  List<Client> _clients = const [];
  bool _started = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final appState = ref.read(appStateProvider);
      final results = await Future.wait([
        appState.fetchTorSettings(context: context),
        appState.fetchClientsForSelectedRouter(),
      ]);
      if (!mounted) return;
      setState(() {
        _settings = results[0] as OpenwallaTorSettings;
        _clients = (results[1] as List<Client>)
            .where((client) => client.macAddress.trim().isNotEmpty)
            .toList();
        _loading = false;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Bad state: ', '');
        _loading = false;
        _saving = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(appStateProvider)
          .saveTorSettings(_settings, context: context);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Tor routing updated.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  Future<void> _checkTor() async {
    final opened = await launchUrlString(
      'https://check.torproject.org/',
      mode: LaunchMode.inAppBrowserView,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the Tor check.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Tor', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              OpenwrtFeatureGate(
                feature: OpenwrtFeature.tor,
                title: 'Tor is not installed',
                message:
                    'Install the Tor client and Openwalla routing manager. Installation starts with no LAN traffic routed.',
                installLabel: 'Install Tor',
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
      return _TorCard(
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
    final routed = _settings.mode != TorRoutingMode.none;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TorCard(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.hub_rounded, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _settings.running ? 'Tor is running' : 'Tor is stopped',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      routed ? _scopeSummary() : 'No traffic routed',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _settings.running
                      ? const Color(0xFF20CF70)
                      : colors.error,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _TorCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Traffic Scope',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              SegmentedButton<TorRoutingMode>(
                segments: const [
                  ButtonSegment(
                    value: TorRoutingMode.none,
                    icon: Icon(Icons.pause_circle_outline_rounded),
                    label: Text('None'),
                  ),
                  ButtonSegment(
                    value: TorRoutingMode.devices,
                    icon: Icon(Icons.devices_rounded),
                    label: Text('Devices'),
                  ),
                  ButtonSegment(
                    value: TorRoutingMode.lan,
                    icon: Icon(Icons.lan_rounded),
                    label: Text('All LAN'),
                  ),
                ],
                selected: {_settings.mode},
                onSelectionChanged: (selection) {
                  setState(() {
                    _settings = OpenwallaTorSettings(
                      mode: selection.first,
                      dnsViaTor: _settings.dnsViaTor,
                      running: _settings.running,
                      deviceMacs: _settings.deviceMacs,
                    );
                  });
                },
              ),
              if (_settings.mode == TorRoutingMode.devices) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 8),
                if (_clients.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No LAN devices are currently available.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  )
                else
                  ..._clients.map(_buildDeviceTile),
              ],
              const Divider(height: 24),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.dns_rounded),
                title: const Text('Route DNS via Tor'),
                subtitle: const Text('Send DNS lookups through Tor DNSPort'),
                value: _settings.dnsViaTor,
                onChanged: _settings.mode == TorRoutingMode.none
                    ? null
                    : (value) {
                        setState(() {
                          _settings = OpenwallaTorSettings(
                            mode: _settings.mode,
                            dnsViaTor: value,
                            running: _settings.running,
                            deviceMacs: _settings.deviceMacs,
                          );
                        });
                      },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_saving ? 'Applying' : 'Apply Routing'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _checkTor,
          icon: const Icon(Icons.verified_user_outlined),
          label: const Text('Check Tor Connection'),
        ),
        const SizedBox(height: 8),
        Text(
          'The check uses this device connection. Select this device or All LAN before testing.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildDeviceTile(Client client) {
    final mac = client.macAddress.toUpperCase().replaceAll('-', ':');
    final selected = _settings.deviceMacs.contains(mac);
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: selected,
      title: Text(client.displayName),
      subtitle: Text('${client.ipAddress}  $mac'),
      secondary: Icon(
        client.connectionType == ConnectionType.wireless
            ? Icons.wifi_rounded
            : Icons.devices_other_rounded,
      ),
      onChanged: (checked) {
        final macs = {..._settings.deviceMacs};
        checked == true ? macs.add(mac) : macs.remove(mac);
        setState(() {
          _settings = OpenwallaTorSettings(
            mode: _settings.mode,
            dnsViaTor: _settings.dnsViaTor,
            running: _settings.running,
            deviceMacs: macs,
          );
        });
      },
    );
  }

  String _scopeSummary() {
    return switch (_settings.mode) {
      TorRoutingMode.none => 'No traffic routed',
      TorRoutingMode.devices =>
        '${_settings.deviceMacs.length} device${_settings.deviceMacs.length == 1 ? '' : 's'} routed',
      TorRoutingMode.lan => 'All LAN TCP traffic routed',
    };
  }
}

class _TorCard extends StatelessWidget {
  final Widget child;

  const _TorCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}
