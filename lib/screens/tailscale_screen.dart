import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/openwrt_feature_gate.dart';
import 'package:url_launcher/url_launcher_string.dart';

class TailscaleScreen extends ConsumerStatefulWidget {
  const TailscaleScreen({super.key});

  @override
  ConsumerState<TailscaleScreen> createState() => _TailscaleScreenState();
}

class _TailscaleScreenState extends ConsumerState<TailscaleScreen> {
  final _subnetController = TextEditingController();
  OpenwallaTailscaleSettings _settings = const OpenwallaTailscaleSettings();
  bool _started = false;
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _subnetController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await ref
          .read(appStateProvider)
          .fetchTailscaleSettings(context: context);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _subnetController.text = settings.lanSubnet;
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

  Future<void> _connect() async {
    setState(() => _working = true);
    try {
      final output = await ref
          .read(appStateProvider)
          .startTailscaleLogin(context: context);
      final match = RegExp(r'AUTH_URL=(https://\S+)').firstMatch(output);
      final url = match?.group(1);
      if (url != null) {
        final opened = await launchUrlString(
          url,
          mode: LaunchMode.inAppBrowserView,
        );
        if (!opened) throw StateError('Unable to open the Tailscale sign-in');
      } else if (!output.contains('Running')) {
        throw StateError(
          output.trim().isEmpty ? 'No sign-in URL returned' : output,
        );
      }
      await _load();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _save() async {
    setState(() => _working = true);
    try {
      final updated = _settings.copyWith(
        lanSubnet: _subnetController.text.trim(),
      );
      await ref
          .read(appStateProvider)
          .saveTailscaleSettings(updated, context: context);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tailscale settings updated.')),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Tailscale?'),
        content: const Text(
          'The router will leave the active mesh connection until you connect it again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    setState(() => _working = true);
    try {
      await ref.read(appStateProvider).disconnectTailscale(context: context);
      await _load();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Tailscale', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              OpenwrtFeatureGate(
                feature: OpenwrtFeature.tailscale,
                title: 'Tailscale is not installed',
                message:
                    'Install Tailscale and its Openwalla routing controls. No LAN routes are advertised by default.',
                warning:
                    'Tailscale is a large package and needs about 20 MB or more of free router storage. Installation will stop if there is not enough free space.',
                installLabel: 'Install Tailscale',
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
      return _Panel(
        child: Column(
          children: [
            Text(_error!, textAlign: TextAlign.center),
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
        _Panel(
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.device_hub_rounded,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _settings.authenticated
                              ? (_settings.hostname.isEmpty
                                    ? 'Connected to Tailscale'
                                    : _settings.hostname)
                              : 'Sign in required',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          _settings.ipAddress.isEmpty
                              ? _settings.backendState
                              : _settings.ipAddress,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _settings.authenticated
                          ? const Color(0xFF20CF70)
                          : colors.outline,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: _settings.authenticated
                    ? OutlinedButton.icon(
                        onPressed: _working ? null : _disconnect,
                        icon: const Icon(Icons.link_off_rounded),
                        label: const Text('Disconnect'),
                      )
                    : FilledButton.icon(
                        onPressed: _working ? null : _connect,
                        icon: const Icon(Icons.login_rounded),
                        label: Text(_working ? 'Waiting' : 'Connect Tailscale'),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Routing',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Advertise LAN'),
                subtitle: const Text(
                  'Allow approved tailnet devices to reach this LAN',
                ),
                value: _settings.advertiseLan,
                onChanged: _working
                    ? null
                    : (value) => setState(
                        () =>
                            _settings = _settings.copyWith(advertiseLan: value),
                      ),
              ),
              if (_settings.advertiseLan) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _subnetController,
                  enabled: !_working,
                  decoration: const InputDecoration(
                    labelText: 'LAN subnet',
                    hintText: '192.168.1.0/24',
                    prefixIcon: Icon(Icons.lan_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Advertised routes must also be approved in the Tailscale admin console.',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
              const Divider(height: 28),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Accept tailnet routes'),
                subtitle: const Text(
                  'Use subnet routes advertised by other Tailscale nodes',
                ),
                value: _settings.acceptRoutes,
                onChanged: _working
                    ? null
                    : (value) => setState(
                        () =>
                            _settings = _settings.copyWith(acceptRoutes: value),
                      ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Offer as exit node'),
                subtitle: const Text(
                  'Let approved tailnet devices use this router for internet access',
                ),
                value: _settings.advertiseExitNode,
                onChanged: _working
                    ? null
                    : (value) => setState(
                        () => _settings = _settings.copyWith(
                          advertiseExitNode: value,
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: !_settings.authenticated || _working ? null : _save,
                icon: _working
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_working ? 'Applying' : 'Apply Routing'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}
