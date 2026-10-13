import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:openwalla/services/tunnel_monitor_service.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/luci_toast.dart';
import 'package:url_launcher/url_launcher_string.dart';

class TunnelSettingsScreen extends StatefulWidget {
  final String routerId;
  final TunnelMonitorService? service;
  final Future<TunnelMonitorSettings> Function()? loadInitialSettings;

  const TunnelSettingsScreen({
    super.key,
    required this.routerId,
    this.service,
    this.loadInitialSettings,
  });

  @override
  State<TunnelSettingsScreen> createState() => _TunnelSettingsScreenState();
}

class _TunnelSettingsScreenState extends State<TunnelSettingsScreen> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _form = GlobalKey<FormState>();
  late final TunnelMonitorService _service;
  TunnelMonitorSettings? _saved;
  TunnelMonitorStatus? _status;
  CancelToken? _request;
  bool _loading = true;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  DateTime? _checkedAt;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? TunnelMonitorService();
    _load();
  }

  Future<void> _load() async {
    try {
      var saved = await _service.load(widget.routerId);
      if (saved.serverUrl.isEmpty && widget.loadInitialSettings != null) {
        saved = await widget.loadInitialSettings!();
      }
      if (!mounted) return;
      _url.text = saved.serverUrl;
      _token.text = saved.apiToken;
      setState(() {
        _saved = saved;
        _loading = false;
      });
      if (saved.serverUrl.isNotEmpty) await _refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      context.showToastError('Could not load Tunnel settings');
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final settings = TunnelMonitorSettings(
        serverUrl: _url.text.trim(),
        apiToken: _token.text.trim(),
      );
      await _service.save(widget.routerId, settings);
      if (!mounted) return;
      setState(() {
        _saved = settings;
        _busy = false;
      });
      context.showToastSuccess('Tunnel settings saved');
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      context.showToastError('Could not save Tunnel settings');
    }
  }

  Future<void> _refresh() async {
    final settings = _saved;
    if (_busy || settings == null || settings.serverUrl.isEmpty) return;
    final request = CancelToken();
    _request = request;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await _service.fetch(settings, cancelToken: request);
      if (!mounted) return;
      setState(() {
        _status = status;
        _checkedAt = DateTime.now();
      });
    } catch (error) {
      if (!mounted || request.isCancelled) return;
      final message =
          error is DioException &&
              const [401, 403].contains(error.response?.statusCode)
          ? 'Access denied. Check the server API token.'
          : error is FormatException
          ? error.message
          : 'Could not reach Openwalla Server. Check its URL and connection.';
      setState(() {
        _status = null;
        _checkedAt = null;
        _error = message;
      });
      context.showToastError('Tunnel status unavailable', subtitle: message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _request?.cancel();
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  void _showTunnelInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.info_outline_rounded),
        title: const Text('About the Tunnel'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The router opens an encrypted, key-authenticated outbound SSH '
                'connection to your Openwalla Server gateway. It forwards LuCI '
                'and router SSH through that connection, without opening inbound '
                'ports on the router.\n\n'
                'For remote access, running the gateway on an external server, '
                'such as a VPS, is recommended but optional. A suitable '
                'self-hosted server works too, as long as the router can reach it.\n\n'
                'Server API shows whether the app can contact Openwalla Server. '
                'LuCI and SSH show whether the server can reach the configured '
                'tunnel ports. Reachable does not confirm a successful login or '
                'an active user session.\n\n'
                'This page monitors the tunnel; it does not install or start it. '
                'The optional server gateway and router tunnel service must be '
                'set up separately.\n\n'
                'The server URL and API token are shared with flow settings. '
                'Local router or Openwalla Server flow collection remains a '
                'separate choice. Use HTTPS for server access outside your '
                'trusted LAN, and keep forwarded LuCI and SSH ports private.',
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _openTunnelReadme,
                child: const Text(
                  'Openwalla Server README',
                  style: TextStyle(decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _openTunnelReadme() async {
    try {
      final opened = await launchUrlString(
        'https://github.com/benisai/Openwalla/blob/main/openwalla-server/README.md#optional-reverse-tunnel',
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        context.showToastError('Could not open the setup guide');
      }
    } catch (_) {
      if (mounted) context.showToastError('Could not open the setup guide');
    }
  }

  Widget _endpoint(String title, bool? available, {String? detail}) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        available == true ? Icons.check_circle_outline : Icons.link_off_rounded,
        color: available == null
            ? scheme.onSurfaceVariant
            : available
            ? Colors.teal
            : scheme.error,
      ),
      title: Text(title),
      subtitle: detail == null ? null : Text(detail),
      trailing: Text(
        available == null
            ? 'Not checked'
            : available
            ? 'Reachable'
            : 'Unavailable',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Tunnel',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Refresh tunnel status',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading || _busy || _saved?.serverUrl.isNotEmpty != true
                ? null
                : _refresh,
          ),
          IconButton(
            tooltip: 'About the tunnel',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: _showTunnelInfo,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  Text(
                    'Openwalla Server',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 20),
                  Form(
                    key: _form,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _url,
                          enabled: !_busy,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Server URL',
                            hintText: 'http://server-ip:2020',
                            prefixIcon: Icon(Icons.dns_outlined),
                          ),
                          validator: (value) {
                            try {
                              TunnelMonitorSettings(
                                serverUrl: value ?? '',
                              ).statusUri;
                              return null;
                            } on FormatException catch (e) {
                              return e.message;
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _token,
                          enabled: !_busy,
                          obscureText: _obscure,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            labelText: 'API token (optional)',
                            prefixIcon: const Icon(Icons.key_outlined),
                            suffixIcon: IconButton(
                              tooltip: _obscure ? 'Show token' : 'Hide token',
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Save & Connect'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    'Tunnel Status',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  _endpoint(
                    'Server API',
                    status != null
                        ? true
                        : _error != null
                        ? false
                        : null,
                  ),
                  _endpoint(
                    'LuCI',
                    status?.luciAvailable,
                    detail: status == null
                        ? null
                        : '${status.host}:${status.luciPort}',
                  ),
                  _endpoint(
                    'SSH',
                    status?.sshAvailable,
                    detail: status == null
                        ? null
                        : '${status.host}:${status.sshPort}',
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (_checkedAt != null)
                    Text(
                      'Last checked ${TimeOfDay.fromDateTime(_checkedAt!).format(context)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
    );
  }
}
