import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/openwrt_feature_gate.dart';

enum _VpnPanel { server, client }

class VpnScreen extends ConsumerStatefulWidget {
  const VpnScreen({super.key});

  @override
  ConsumerState<VpnScreen> createState() => _VpnScreenState();
}

class _VpnScreenState extends ConsumerState<VpnScreen> {
  _VpnPanel _panel = _VpnPanel.server;
  WireGuardServerSettings _settings = WireGuardServerSettings.defaults;
  List<WireGuardServerProfile> _serverProfiles = const [];
  WireGuardClientSettings _clientSettings = WireGuardClientSettings.defaults;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasStartedLoad = false;
  bool _fileImportExpanded = true;
  bool _pasteConfigExpanded = false;
  bool _configFieldsExpanded = false;
  String? _importedFileName;
  String? _routerPublicIp;
  String? _error;

  final _portController = TextEditingController(text: '51820');
  final _vpnAddressController = TextEditingController(text: '10.8.0.1/24');
  final _clientConfigController = TextEditingController();
  final _clientAddressController = TextEditingController();
  final _clientDnsController = TextEditingController();
  final _clientPrivateKeyController = TextEditingController();
  final _clientPeerPublicKeyController = TextEditingController();
  final _clientPresharedKeyController = TextEditingController();
  final _clientEndpointHostController = TextEditingController();
  final _clientEndpointPortController = TextEditingController(text: '51820');
  final _clientAllowedIpsController = TextEditingController(
    text: '0.0.0.0/0, ::/0',
  );
  final _clientKeepaliveController = TextEditingController(text: '25');

  @override
  void initState() {
    super.initState();
    unawaited(_loadRouterPublicIp());
  }

  Future<void> _loadRouterPublicIp({bool forceRefresh = false}) async {
    final publicIp = await ref
        .read(appStateProvider)
        .fetchRouterPublicIp(forceRefresh: forceRefresh);
    if (mounted && publicIp != null) {
      setState(() => _routerPublicIp = publicIp);
    }
  }

  @override
  void dispose() {
    _portController.dispose();
    _vpnAddressController.dispose();
    _clientConfigController.dispose();
    _clientAddressController.dispose();
    _clientDnsController.dispose();
    _clientPrivateKeyController.dispose();
    _clientPeerPublicKeyController.dispose();
    _clientPresharedKeyController.dispose();
    _clientEndpointHostController.dispose();
    _clientEndpointPortController.dispose();
    _clientAllowedIpsController.dispose();
    _clientKeepaliveController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final appState = ref.read(appStateProvider);
      final settings = await appState.fetchWireGuardServerSettings();
      final serverProfiles = settings.configured
          ? await appState.fetchWireGuardServerProfiles(
              interfaceName: settings.interfaceName,
            )
          : const <WireGuardServerProfile>[];
      final clientSettings = await appState.fetchWireGuardClientSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _serverProfiles = serverProfiles;
        _clientSettings = clientSettings;
        _portController.text = settings.listenPort.toString();
        _vpnAddressController.text = settings.vpnAddress;
        _syncClientControllers(clientSettings);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load WireGuard server settings.';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveServer({bool setup = false}) async {
    final port = int.tryParse(_portController.text.trim());
    final vpnAddress = _vpnAddressController.text.trim();

    if (port == null || port < 1 || port > 65535) {
      _showSnack('Enter a UDP port between 1 and 65535.');
      return;
    }
    if (!_looksLikeCidr(vpnAddress)) {
      _showSnack('Enter the VPN address as CIDR, like 10.8.0.1/24.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final updated = WireGuardServerSettings(
        installed: _settings.installed,
        configured: _settings.configured,
        enabled: _settings.enabled,
        interfaceName: _settings.interfaceName,
        listenPort: port,
        vpnAddress: vpnAddress,
        internalIpAddress: '',
        publicKey: _settings.publicKey,
      );
      await ref
          .read(appStateProvider)
          .saveWireGuardServerSettings(updated, context: context);
      if (!mounted) return;
      _showSnack(
        setup
            ? 'WireGuard server set up successfully.'
            : 'WireGuard server settings saved.',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to save WireGuard server: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _createServerProfile() async {
    if (!_settings.configured) {
      _showSnack('Save the WireGuard server before creating a profile.');
      return;
    }
    final serverIp = _vpnAddressController.text.trim().split('/').first;
    final octets = serverIp.split('.');
    final prefix = octets.length == 4 ? octets.take(3).join('.') : '10.8.0';
    final usedAddresses = _serverProfiles
        .map((profile) => profile.address.split('/').first)
        .toSet();
    var host = 2;
    while (usedAddresses.contains('$prefix.$host') && host < 255) {
      host++;
    }
    final suggestedAddress = '$prefix.$host/32';
    final publicIp =
        _routerPublicIp ??
        await ref.read(appStateProvider).fetchRouterPublicIp();
    if (mounted && publicIp != null) {
      setState(() => _routerPublicIp = publicIp);
    }
    if (!mounted) return;
    final result = await showDialog<_NewServerProfile>(
      context: context,
      builder: (context) => _ServerProfileDialog(
        suggestedAddress: suggestedAddress,
        suggestedDns: serverIp,
        suggestedEndpoint: publicIp ?? '',
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .createWireGuardServerProfile(
            interfaceName: _settings.interfaceName,
            name: result.name,
            address: result.address,
            endpoint: result.endpoint,
            dns: result.dns,
            allowedIps: result.allowedIps,
            context: context,
          );
      if (!mounted) return;
      _showSnack('WireGuard profile created.');
      await _load();
    } catch (e) {
      if (mounted) _showSnack('Failed to create profile: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _downloadServerProfile(WireGuardServerProfile profile) async {
    try {
      final safeName = profile.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save WireGuard profile',
        fileName: '$safeName.conf',
        type: FileType.custom,
        allowedExtensions: const ['conf'],
        bytes: utf8.encode(profile.config),
      );
      if (mounted && path != null) _showSnack('WireGuard profile saved.');
    } catch (e) {
      if (mounted) _showSnack('Unable to save profile: $e');
    }
  }

  Future<void> _deleteServerProfile(WireGuardServerProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete profile?'),
        content: Text('${profile.name} will no longer be able to connect.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .deleteWireGuardServerProfile(profile.section, context: context);
      if (!mounted) return;
      setState(() {
        _serverProfiles = _serverProfiles
            .where((item) => item.section != profile.section)
            .toList();
      });
      _showSnack('WireGuard profile deleted.');
    } catch (e) {
      if (mounted) _showSnack('Failed to delete profile: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveClient() async {
    final endpointPort = int.tryParse(
      _clientEndpointPortController.text.trim(),
    );
    final keepalive = int.tryParse(_clientKeepaliveController.text.trim());
    final address = _clientAddressController.text.trim();

    if (address.isEmpty) {
      _showSnack('Import or enter the WireGuard client address.');
      return;
    }
    if (!address
        .split(',')
        .map((value) => value.trim())
        .every(_looksLikeIpCidr)) {
      _showSnack('Enter client addresses as CIDR values, like 10.64.0.2/32.');
      return;
    }
    if (_clientPrivateKeyController.text.trim().isEmpty) {
      _showSnack('WireGuard client private key is required.');
      return;
    }
    if (_clientPeerPublicKeyController.text.trim().isEmpty) {
      _showSnack('WireGuard peer public key is required.');
      return;
    }
    if (_clientEndpointHostController.text.trim().isEmpty) {
      _showSnack('WireGuard endpoint host is required.');
      return;
    }
    if (endpointPort == null || endpointPort < 1 || endpointPort > 65535) {
      _showSnack('Enter an endpoint port between 1 and 65535.');
      return;
    }
    if (keepalive == null || keepalive < 0 || keepalive > 65535) {
      _showSnack('Enter a keepalive value from 0 to 65535.');
      return;
    }

    final updated = WireGuardClientSettings(
      installed: _clientSettings.installed,
      configured: _clientSettings.configured,
      enabled: _clientSettings.enabled,
      interfaceName: _clientSettings.interfaceName,
      address: address,
      dns: _clientDnsController.text.trim(),
      privateKey: _clientPrivateKeyController.text.trim(),
      peerPublicKey: _clientPeerPublicKeyController.text.trim(),
      presharedKey: _clientPresharedKeyController.text.trim(),
      endpointHost: _clientEndpointHostController.text.trim(),
      endpointPort: endpointPort,
      allowedIps: _clientAllowedIpsController.text.trim(),
      persistentKeepalive: keepalive,
      routeAllowedIps: _clientSettings.routeAllowedIps,
    );

    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .saveWireGuardClientSettings(updated, context: context);
      if (!mounted) return;
      _showSnack('WireGuard client settings saved.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to save WireGuard client: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _syncClientControllers(WireGuardClientSettings settings) {
    _clientAddressController.text = settings.address;
    _clientDnsController.text = settings.dns;
    _clientPrivateKeyController.text = settings.privateKey;
    _clientPeerPublicKeyController.text = settings.peerPublicKey;
    _clientPresharedKeyController.text = settings.presharedKey;
    _clientEndpointHostController.text = settings.endpointHost;
    _clientEndpointPortController.text = settings.endpointPort.toString();
    _clientAllowedIpsController.text = settings.allowedIps;
    _clientKeepaliveController.text = settings.persistentKeepalive.toString();
  }

  Future<void> _pickClientConfig() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['conf', 'txt'],
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      if (bytes == null) return;
      final configText = utf8.decode(bytes, allowMalformed: true);
      _clientConfigController.text = configText;
      setState(() => _importedFileName = file?.name);
      _importClientConfig(configText);
    } catch (e) {
      _showSnack('Unable to read WireGuard config: $e');
    }
  }

  void _importClientConfig([String? configText]) {
    final parsed = _ParsedWireGuardConfig.parse(
      configText ?? _clientConfigController.text,
    );
    if (parsed == null) {
      _showSnack('This does not look like a WireGuard client config.');
      return;
    }

    final endpoint = _splitEndpoint(parsed.endpoint);
    setState(() {
      _clientAddressController.text = parsed.address;
      _clientDnsController.text = parsed.dns;
      _clientPrivateKeyController.text = parsed.privateKey;
      _clientPeerPublicKeyController.text = parsed.peerPublicKey;
      _clientPresharedKeyController.text = parsed.presharedKey;
      _clientEndpointHostController.text = endpoint.$1;
      _clientEndpointPortController.text = endpoint.$2.toString();
      _clientAllowedIpsController.text = parsed.allowedIps.isEmpty
          ? '0.0.0.0/0, ::/0'
          : parsed.allowedIps;
      _clientKeepaliveController.text = parsed.persistentKeepalive.isEmpty
          ? '25'
          : parsed.persistentKeepalive;
      _clientSettings = WireGuardClientSettings(
        installed: _clientSettings.installed,
        configured: _clientSettings.configured,
        enabled: _clientSettings.enabled,
        interfaceName: _clientSettings.interfaceName,
        address: _clientAddressController.text,
        dns: _clientDnsController.text,
        privateKey: _clientPrivateKeyController.text,
        peerPublicKey: _clientPeerPublicKeyController.text,
        presharedKey: _clientPresharedKeyController.text,
        endpointHost: _clientEndpointHostController.text,
        endpointPort: int.tryParse(_clientEndpointPortController.text) ?? 51820,
        allowedIps: _clientAllowedIpsController.text,
        persistentKeepalive:
            int.tryParse(_clientKeepaliveController.text) ?? 25,
        routeAllowedIps: _clientSettings.routeAllowedIps,
      );
      _configFieldsExpanded = true;
    });
    _showSnack('WireGuard config imported. Review and save to apply.');
  }

  (String, int) _splitEndpoint(String endpoint) {
    final value = endpoint.trim();
    if (value.startsWith('[')) {
      final end = value.indexOf(']');
      if (end > 0) {
        final host = value.substring(1, end);
        final port = value.length > end + 2 && value[end + 1] == ':'
            ? int.tryParse(value.substring(end + 2)) ?? 51820
            : 51820;
        return (host, port);
      }
    }
    final separator = value.lastIndexOf(':');
    if (separator <= 0) return (value, 51820);
    return (
      value.substring(0, separator),
      int.tryParse(value.substring(separator + 1)) ?? 51820,
    );
  }

  bool _looksLikeIpv4(String value) {
    final parts = value.split('.');
    if (parts.length != 4) return false;
    return parts.every((part) {
      final number = int.tryParse(part);
      return number != null && number >= 0 && number <= 255;
    });
  }

  bool _looksLikeCidr(String value) {
    final parts = value.split('/');
    if (parts.length != 2 || !_looksLikeIpv4(parts[0])) return false;
    final prefix = int.tryParse(parts[1]);
    return prefix != null && prefix >= 1 && prefix <= 32;
  }

  bool _looksLikeIpCidr(String value) {
    final trimmed = value.trim();
    if (trimmed.contains(':')) return trimmed.contains('/');
    return _looksLikeCidr(trimmed);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _updateEnabled(bool enabled) {
    setState(() {
      _settings = WireGuardServerSettings(
        installed: _settings.installed,
        configured: _settings.configured,
        enabled: enabled,
        interfaceName: _settings.interfaceName,
        listenPort: _settings.listenPort,
        vpnAddress: _settings.vpnAddress,
        internalIpAddress: _settings.internalIpAddress,
        publicKey: _settings.publicKey,
      );
    });
  }

  void _updateClientEnabled(bool enabled) {
    setState(() {
      _clientSettings = WireGuardClientSettings(
        installed: _clientSettings.installed,
        configured: _clientSettings.configured,
        enabled: enabled,
        interfaceName: _clientSettings.interfaceName,
        address: _clientSettings.address,
        dns: _clientSettings.dns,
        privateKey: _clientSettings.privateKey,
        peerPublicKey: _clientSettings.peerPublicKey,
        presharedKey: _clientSettings.presharedKey,
        endpointHost: _clientSettings.endpointHost,
        endpointPort: _clientSettings.endpointPort,
        allowedIps: _clientSettings.allowedIps,
        persistentKeepalive: _clientSettings.persistentKeepalive,
        routeAllowedIps: _clientSettings.routeAllowedIps,
      );
    });
  }

  void _updateClientRouteAllowed(bool routeAllowedIps) {
    setState(() {
      _clientSettings = WireGuardClientSettings(
        installed: _clientSettings.installed,
        configured: _clientSettings.configured,
        enabled: _clientSettings.enabled,
        interfaceName: _clientSettings.interfaceName,
        address: _clientSettings.address,
        dns: _clientSettings.dns,
        privateKey: _clientSettings.privateKey,
        peerPublicKey: _clientSettings.peerPublicKey,
        presharedKey: _clientSettings.presharedKey,
        endpointHost: _clientSettings.endpointHost,
        endpointPort: _clientSettings.endpointPort,
        allowedIps: _clientSettings.allowedIps,
        persistentKeepalive: _clientSettings.persistentKeepalive,
        routeAllowedIps: routeAllowedIps,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const LuciAppBar(title: 'VPN', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                'WireGuard VPN',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Configure WireGuard server access on this router.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 16),
              OpenwrtFeatureGate(
                feature: OpenwrtFeature.wireguard,
                title: 'WireGuard is not installed',
                message:
                    'Install WireGuard tools and LuCI protocol support before configuring VPN server or client settings.',
                installLabel: 'Install WireGuard',
                builder: (_) => _buildInstalledContent(colorScheme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstalledContent(ColorScheme colorScheme) {
    if (!_hasStartedLoad) {
      _hasStartedLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    return Column(
      children: [
        SegmentedButton<_VpnPanel>(
          segments: const [
            ButtonSegment(
              value: _VpnPanel.server,
              label: Text('Server'),
              icon: Icon(Icons.dns_rounded),
            ),
            ButtonSegment(
              value: _VpnPanel.client,
              label: Text('Client'),
              icon: Icon(Icons.vpn_lock_rounded),
            ),
          ],
          selected: {_panel},
          onSelectionChanged: (selection) {
            setState(() => _panel = selection.first);
          },
        ),
        const SizedBox(height: 16),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _VpnPanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_error!, style: TextStyle(color: colorScheme.error)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          )
        else if (_panel == _VpnPanel.server)
          _buildServerPanel()
        else
          _buildClientPanel(),
      ],
    );
  }

  Widget _buildServerPanel() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _VpnPanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'WireGuard Server',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  _StatusPill(
                    label: _settings.configured
                        ? 'Configured'
                        : 'Not configured',
                    color: _settings.configured
                        ? const Color(0xFF20CF70)
                        : colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (!_settings.installed)
                _WarningBox(
                  message:
                      'wireguard-tools is not installed. Install it from Router Setup or opkg before saving.',
                ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable Server'),
                subtitle: Text(_settings.interfaceName),
                value: _settings.enabled,
                onChanged: _isSaving ? null : _updateEnabled,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: 'Listen Port',
                  helperText: 'The UDP port exposed on WAN.',
                  prefixIcon: Icon(Icons.settings_ethernet_rounded),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                enabled: !_isSaving,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _vpnAddressController,
                decoration: const InputDecoration(
                  labelText: 'VPN Address',
                  helperText: 'Server tunnel address, for example 10.8.0.1/24.',
                  prefixIcon: Icon(Icons.vpn_key_rounded),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.text,
                enabled: !_isSaving,
              ),
              const SizedBox(height: 14),
              _DetailRow(label: 'Interface', value: _settings.interfaceName),
              _DetailRow(label: 'Firewall zone', value: 'LAN'),
              _DetailRow(
                label: 'WAN access',
                value: 'UDP ${_portController.text.trim()}',
              ),
              _DetailRow(label: 'Public key', value: _settings.publicKey),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : () => _saveServer(),
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Save Server'),
                    ),
                  ),
                  if (!_settings.configured) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isSaving
                            ? null
                            : () => _saveServer(setup: true),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.build_circle_outlined),
                        label: Text(_isSaving ? 'Setting Up' : 'Setup'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _VpnPanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Client Profiles',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _isSaving ? null : _createServerProfile,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Create a separate WireGuard configuration for each user or device.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (_serverProfiles.isEmpty) ...[
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    _settings.configured
                        ? 'No client profiles yet'
                        : 'Save the server to add profiles',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 10),
                for (final profile in _serverProfiles)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: colorScheme.primary.withValues(
                        alpha: 0.12,
                      ),
                      child: Icon(
                        Icons.vpn_key_rounded,
                        color: colorScheme.primary,
                      ),
                    ),
                    title: Text(profile.name),
                    subtitle: Text(profile.address),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Download configuration',
                          onPressed: () => _downloadServerProfile(profile),
                          icon: const Icon(Icons.download_rounded),
                        ),
                        IconButton(
                          tooltip: 'Delete profile',
                          onPressed: _isSaving
                              ? null
                              : () => _deleteServerProfile(profile),
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClientPanel() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _VpnPanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'WireGuard Client',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  _StatusPill(
                    label: _clientSettings.configured
                        ? 'Configured'
                        : 'Not configured',
                    color: _clientSettings.configured
                        ? const Color(0xFF20CF70)
                        : colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Import a provider configuration or enter the tunnel details manually.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!_clientSettings.installed) ...[
                const SizedBox(height: 14),
                _WarningBox(
                  message:
                      'wireguard-tools is not installed. Install WireGuard from Router Setup or opkg before saving.',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _CollapsibleVpnSection(
          title: 'Import Config File',
          subtitle: _importedFileName ?? 'Upload a .conf or .txt file',
          icon: Icons.upload_file_rounded,
          expanded: _fileImportExpanded,
          onToggle: () =>
              setState(() => _fileImportExpanded = !_fileImportExpanded),
          child: _WireGuardUploadTarget(
            fileName: _importedFileName,
            enabled: !_isSaving,
            onTap: _pickClientConfig,
          ),
        ),
        const SizedBox(height: 12),
        _CollapsibleVpnSection(
          title: 'Paste WireGuard Config',
          subtitle: 'Paste the contents of a client configuration',
          icon: Icons.content_paste_rounded,
          expanded: _pasteConfigExpanded,
          onToggle: () =>
              setState(() => _pasteConfigExpanded = !_pasteConfigExpanded),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _clientConfigController,
                decoration: const InputDecoration(
                  labelText: 'WireGuard configuration',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.description_rounded),
                  border: OutlineInputBorder(),
                ),
                minLines: 6,
                maxLines: 12,
                enabled: !_isSaving,
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isSaving ? null : () => _importClientConfig(),
                icon: const Icon(Icons.input_rounded),
                label: const Text('Import Pasted Config'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _CollapsibleVpnSection(
          title: 'Configuration Fields',
          subtitle: 'Review or enter the interface and peer settings',
          icon: Icons.tune_rounded,
          expanded: _configFieldsExpanded,
          onToggle: () =>
              setState(() => _configFieldsExpanded = !_configFieldsExpanded),
          child: _buildClientConfigFields(),
        ),
        const SizedBox(height: 14),
        _WarningBox(
          message:
              'Saving places the Openwalla WireGuard client interface in the WAN firewall zone and does not modify LAN or WAN interfaces.',
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isSaving ? null : _saveClient,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_isSaving ? 'Saving' : 'Save Client'),
          ),
        ),
      ],
    );
  }

  Widget _buildClientConfigFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable Client'),
          subtitle: Text(
            _clientSettings.interfaceName == 'owrt_wg_client'
                ? _clientSettings.interfaceName
                : 'Detected existing client: ${_clientSettings.interfaceName}',
          ),
          value: _clientSettings.enabled,
          onChanged: _isSaving ? null : _updateClientEnabled,
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Route Allowed IPs'),
          subtitle: const Text('Use AllowedIPs from the config as routes.'),
          value: _clientSettings.routeAllowedIps,
          onChanged: _isSaving ? null : _updateClientRouteAllowed,
        ),
        const Divider(height: 28),
        const _VpnSectionLabel(label: 'Interface'),
        const SizedBox(height: 8),
        TextField(
          controller: _clientAddressController,
          decoration: const InputDecoration(
            labelText: 'Address',
            helperText: 'Client tunnel address, for example 10.64.0.2/32.',
            prefixIcon: Icon(Icons.tag_rounded),
            border: OutlineInputBorder(),
          ),
          enabled: !_isSaving,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _clientDnsController,
          decoration: const InputDecoration(
            labelText: 'DNS Servers',
            prefixIcon: Icon(Icons.dns_rounded),
            border: OutlineInputBorder(),
          ),
          enabled: !_isSaving,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _clientPrivateKeyController,
          decoration: const InputDecoration(
            labelText: 'Private Key',
            prefixIcon: Icon(Icons.key_rounded),
            border: OutlineInputBorder(),
          ),
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          enabled: !_isSaving,
        ),
        const Divider(height: 32),
        const _VpnSectionLabel(label: 'Peer'),
        const SizedBox(height: 8),
        TextField(
          controller: _clientPeerPublicKeyController,
          decoration: const InputDecoration(
            labelText: 'Public Key',
            prefixIcon: Icon(Icons.vpn_key_rounded),
            border: OutlineInputBorder(),
          ),
          enabled: !_isSaving,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _clientPresharedKeyController,
          decoration: const InputDecoration(
            labelText: 'Preshared Key',
            prefixIcon: Icon(Icons.lock_rounded),
            border: OutlineInputBorder(),
          ),
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          enabled: !_isSaving,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _clientEndpointHostController,
                decoration: const InputDecoration(
                  labelText: 'Endpoint Host',
                  prefixIcon: Icon(Icons.public_rounded),
                  border: OutlineInputBorder(),
                ),
                enabled: !_isSaving,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _clientEndpointPortController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                enabled: !_isSaving,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _clientAllowedIpsController,
          decoration: const InputDecoration(
            labelText: 'Allowed IPs',
            helperText: 'Common full tunnel: 0.0.0.0/0, ::/0.',
            prefixIcon: Icon(Icons.route_rounded),
            border: OutlineInputBorder(),
          ),
          enabled: !_isSaving,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _clientKeepaliveController,
          decoration: const InputDecoration(
            labelText: 'Persistent Keepalive',
            helperText: 'Usually 25 for provider VPN clients.',
            prefixIcon: Icon(Icons.timer_rounded),
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          enabled: !_isSaving,
        ),
      ],
    );
  }
}

class _NewServerProfile {
  final String name;
  final String address;
  final String endpoint;
  final String dns;
  final String allowedIps;

  const _NewServerProfile({
    required this.name,
    required this.address,
    required this.endpoint,
    required this.dns,
    required this.allowedIps,
  });
}

class _ServerProfileDialog extends StatefulWidget {
  final String suggestedAddress;
  final String suggestedDns;
  final String suggestedEndpoint;

  const _ServerProfileDialog({
    required this.suggestedAddress,
    required this.suggestedDns,
    required this.suggestedEndpoint,
  });

  @override
  State<_ServerProfileDialog> createState() => _ServerProfileDialogState();
}

class _ServerProfileDialogState extends State<_ServerProfileDialog> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _endpoint;
  late final TextEditingController _dns;
  bool _fullTunnel = true;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _address = TextEditingController(text: widget.suggestedAddress);
    _endpoint = TextEditingController(text: widget.suggestedEndpoint);
    _dns = TextEditingController(text: widget.suggestedDns);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _endpoint.dispose();
    _dns.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final address = _address.text.trim();
    final endpoint = _endpoint.text.trim();
    final dns = _dns.text.trim();
    if (name.isEmpty || address.isEmpty || endpoint.isEmpty || dns.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete all profile fields.')),
      );
      return;
    }
    Navigator.pop(
      context,
      _NewServerProfile(
        name: name,
        address: address,
        endpoint: endpoint,
        dns: dns,
        allowedIps: _fullTunnel
            ? '0.0.0.0/0, ::/0'
            : widget.suggestedDns.replaceAll(RegExp(r'\.\d+$'), '.0/24'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Client Profile'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Profile Name',
                prefixIcon: Icon(Icons.person_outline_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _endpoint,
              decoration: const InputDecoration(
                labelText: 'Public Endpoint',
                helperText: 'Public IP address or DDNS hostname.',
                prefixIcon: Icon(Icons.public_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: 'Client VPN Address',
                prefixIcon: Icon(Icons.tag_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dns,
              decoration: const InputDecoration(
                labelText: 'DNS Server',
                prefixIcon: Icon(Icons.dns_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Route All Traffic'),
              subtitle: Text(
                _fullTunnel
                    ? 'Internet and LAN traffic use the VPN.'
                    : 'Only the WireGuard network uses the tunnel.',
              ),
              value: _fullTunnel,
              onChanged: (value) => setState(() => _fullTunnel = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Create'),
        ),
      ],
    );
  }
}

class _CollapsibleVpnSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  const _CollapsibleVpnSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: colors.primary, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: expanded
                ? Column(
                    children: [
                      Divider(
                        height: 1,
                        color: colors.outlineVariant.withValues(alpha: 0.45),
                      ),
                      Padding(padding: const EdgeInsets.all(16), child: child),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _WireGuardUploadTarget extends StatelessWidget {
  final String? fileName;
  final bool enabled;
  final VoidCallback onTap;

  const _WireGuardUploadTarget({
    required this.fileName,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Select a WireGuard config file',
      child: CustomPaint(
        painter: _DashedRoundedBorderPainter(
          color: enabled ? colors.primary : colors.outline,
          radius: 8,
        ),
        child: Material(
          color: colors.primary.withValues(alpha: enabled ? 0.05 : 0.02),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: enabled ? onTap : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 154),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        fileName == null
                            ? Icons.file_upload_outlined
                            : Icons.check_rounded,
                        color: colors.primary,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      fileName ?? 'Select a WireGuard config file',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      fileName == null
                          ? 'Supported file types: .conf, .txt'
                          : 'Imported. Tap to choose a different file.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRoundedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedRoundedBorderPainter({
    required this.color,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const dashLength = 7.0;
    const gapLength = 5.0;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final paint = Paint()
      ..color = color.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            (distance + dashLength).clamp(0, metric.length),
          ),
          paint,
        );
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _ParsedWireGuardConfig {
  final String privateKey;
  final String address;
  final String dns;
  final String peerPublicKey;
  final String presharedKey;
  final String endpoint;
  final String allowedIps;
  final String persistentKeepalive;

  const _ParsedWireGuardConfig({
    required this.privateKey,
    required this.address,
    required this.dns,
    required this.peerPublicKey,
    required this.presharedKey,
    required this.endpoint,
    required this.allowedIps,
    required this.persistentKeepalive,
  });

  static _ParsedWireGuardConfig? parse(String input) {
    final sections = <String, Map<String, String>>{};
    String? section;
    for (final rawLine in const LineSplitter().convert(input)) {
      final line = rawLine.split('#').first.split(';').first.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1).trim().toLowerCase();
        sections.putIfAbsent(section, () => <String, String>{});
        continue;
      }
      final equals = line.indexOf('=');
      if (section == null || equals <= 0) continue;
      final key = line.substring(0, equals).trim().toLowerCase();
      final value = line.substring(equals + 1).trim();
      sections[section]![key] = value;
    }

    final interface = sections['interface'];
    final peer = sections['peer'];
    if (interface == null || peer == null) return null;
    final privateKey = interface['privatekey'] ?? '';
    final address = interface['address'] ?? '';
    final peerPublicKey = peer['publickey'] ?? '';
    final endpoint = peer['endpoint'] ?? '';
    if (privateKey.isEmpty ||
        address.isEmpty ||
        peerPublicKey.isEmpty ||
        endpoint.isEmpty) {
      return null;
    }
    return _ParsedWireGuardConfig(
      privateKey: privateKey,
      address: address,
      dns: interface['dns'] ?? '',
      peerPublicKey: peerPublicKey,
      presharedKey: peer['presharedkey'] ?? '',
      endpoint: endpoint,
      allowedIps: peer['allowedips'] ?? '',
      persistentKeepalive: peer['persistentkeepalive'] ?? '',
    );
  }
}

class _VpnSectionLabel extends StatelessWidget {
  final String label;

  const _VpnSectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
    );
  }
}

class _VpnPanelCard extends StatelessWidget {
  final Widget child;

  const _VpnPanelCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: child,
    );
  }
}

class _WarningBox extends StatelessWidget {
  final String message;

  const _WarningBox({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colorScheme.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 98,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
