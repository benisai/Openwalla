import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/luci_toast.dart';

class PortForwardScreen extends ConsumerStatefulWidget {
  const PortForwardScreen({super.key, this.forward, required this.routerIp});

  final OpenwrtPortForward? forward;
  final String routerIp;

  @override
  ConsumerState<PortForwardScreen> createState() => _PortForwardScreenState();
}

class _PortForwardScreenState extends ConsumerState<PortForwardScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _external;
  late final TextEditingController _internal;
  late final TextEditingController _address;
  String _protocol = 'tcp';
  String _source = 'wan';
  String _destination = 'lan';
  bool _differentPort = false;
  bool _enabled = true;
  bool _dirty = false;
  bool _busy = false;
  List<String> _zoneNames = const [];

  @override
  void initState() {
    super.initState();
    final rule = widget.forward;
    String value(String? text) => text == 'Any' ? '' : text ?? '';
    _name = TextEditingController(text: rule?.name ?? '');
    _external = TextEditingController(text: value(rule?.wanPort));
    _internal = TextEditingController(text: value(rule?.destinationPort));
    _address = TextEditingController(text: value(rule?.destinationIp));
    if (rule != null) {
      _enabled = rule.enabled;
      _source = rule.source;
      _destination =
          rule.destinationZone == 'lan' && rule.destinationIp == widget.routerIp
          ? 'router'
          : rule.destinationZone;
      final protocols =
          rule.protocol
              .toLowerCase()
              .replaceAll(',', ' ')
              .split(RegExp(r'\s+'))
              .where((part) => part.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      _protocol = protocols.join(' ');
    }
    _differentPort =
        _internal.text.isNotEmpty && _internal.text != _external.text;
    for (final controller in [_name, _external, _internal, _address]) {
      controller.addListener(_changed);
    }
    _loadZones();
  }

  Future<void> _loadZones() async {
    try {
      final zones = await ref.read(appStateProvider).fetchFirewallZones();
      if (mounted) {
        setState(() => _zoneNames = zones.map((zone) => zone.name).toList());
      }
    } catch (_) {
      // Keep standard and existing zones available if discovery is unavailable.
    }
  }

  void _changed() {
    if (mounted && !_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    for (final controller in [_name, _external, _internal, _address]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _port(String text) => text.trim().replaceAll(RegExp(r'\s*-\s*'), '-');

  String? _validatePort(String? text) {
    final match = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(_port(text ?? ''));
    if (match == null) return 'Enter a port or range, such as 443 or 8000-8010';
    final first = int.tryParse(match[1]!);
    final last = int.tryParse(match[2] ?? match[1]!);
    if (first == null ||
        last == null ||
        first < 1 ||
        last > 65535 ||
        first > last) {
      return 'Use ports from 1 to 65535 in ascending order';
    }
    return null;
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final state = ref.read(appStateProvider);
      final internal = _differentPort
          ? _port(_internal.text)
          : _port(_external.text);
      final address = _destination == 'router'
          ? widget.routerIp
          : _address.text.trim();
      if (widget.forward == null) {
        await state.addPortForward(
          name: _name.text,
          sourceZone: _source,
          externalPort: _port(_external.text),
          protocol: _protocol,
          destinationZone: _destination == 'router' ? 'lan' : _destination,
          destinationIp: address,
          internalPort: internal,
          enabled: _enabled,
        );
      } else {
        await state.updatePortForward(
          widget.forward!,
          name: _name.text,
          sourceZone: _source,
          externalPort: _port(_external.text),
          protocol: _protocol,
          destinationZone: _destination == 'router' ? 'lan' : _destination,
          destinationIp: address,
          internalPort: internal,
          enabled: _enabled,
        );
      }
      if (!mounted) return;
      context.showToastSuccess(
        widget.forward == null ? 'Port forward added' : 'Port forward updated',
        subtitle: _name.text.trim(),
        actionKey: 'port-forward-save',
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        context.showToastError(
          'Port forward could not be saved',
          subtitle: error.toString().replaceFirst('Bad state: ', ''),
          actionKey: 'port-forward-save',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _back() async {
    if (_busy) return;
    if (_dirty &&
        !await _confirm(
          'Discard Changes?',
          'Your unsaved changes will be lost.',
          'Discard',
        )) {
      return;
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _delete() async {
    final rule = widget.forward;
    if (_busy || rule == null) return;
    if (!await _confirm(
      'Delete Port Forward?',
      'Delete "${rule.name}" from the router?',
      'Delete',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(appStateProvider).deletePortForward(rule);
      if (!mounted) return;
      context.showToastSuccess(
        'Port forward deleted',
        subtitle: rule.name,
        actionKey: 'port-forward-delete',
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        context.showToastError(
          'Port forward could not be deleted',
          subtitle: error.toString().replaceFirst('Bad state: ', ''),
          actionKey: 'port-forward-delete',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    required String key,
    String? Function(String?)? validator,
    TextInputType? keyboard,
    bool readOnly = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 8),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextFormField(
          key: ValueKey(key),
          controller: controller,
          enabled: !_busy,
          readOnly: readOnly,
          validator: validator,
          keyboardType: keyboard,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            errorMaxLines: 3,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _surface(Widget child) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(8),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  Widget _zone(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    bool router = false,
  }) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items:
        <String>{
              'wan',
              'lan',
              ..._zoneNames,
              value,
              if (router && widget.routerIp.isNotEmpty) 'router',
            }
            .where((name) => name.isNotEmpty)
            .map(
              (name) => DropdownMenuItem(
                value: name,
                child: Text(
                  name == 'router' ? 'Router' : name.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
    onChanged: _busy
        ? null
        : (next) {
            if (next != null) {
              setState(() {
                onChanged(next);
                _dirty = true;
              });
            }
          },
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope<bool>(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: LuciAppBar(
          showBack: true,
          onBack: _back,
          titleWidget: Text(
            'Port Forwarding',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          actions: [
            TextButton.icon(
              onPressed: _busy || !_dirty ? null : _save,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 20),
              label: const Text('Save'),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    _field(
                      'Port Name',
                      _name,
                      key: 'port-name',
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter a name'
                          : null,
                    ),
                    _field(
                      'Port or Port Range',
                      _external,
                      key: 'external-port',
                      validator: _validatePort,
                      keyboard: TextInputType.text,
                    ),
                    _surface(
                      SwitchListTile.adaptive(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        title: const Text('Use a different internal port'),
                        value: _differentPort,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                _differentPort = value;
                                _dirty = true;
                                if (value && _internal.text.isEmpty) {
                                  _internal.text = _external.text;
                                }
                              }),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_differentPort)
                      _field(
                        'Internal Port or Port Range',
                        _internal,
                        key: 'internal-port',
                        validator: _validatePort,
                        keyboard: TextInputType.text,
                      ),
                    _field(
                      'Destination IP Address',
                      _address,
                      key: 'destination-ip',
                      keyboard: TextInputType.text,
                      readOnly: _destination == 'router',
                      validator: (value) =>
                          InternetAddress.tryParse(
                                (_destination == 'router'
                                        ? widget.routerIp
                                        : value ?? '')
                                    .trim(),
                              ) ==
                              null
                          ? 'Enter a valid IP address'
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 10, bottom: 8),
                      child: Text(
                        'Protocol',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    _surface(
                      RadioGroup<String>(
                        groupValue: _protocol,
                        onChanged: (value) {
                          if (!_busy && value != null) {
                            setState(() {
                              _protocol = value;
                              _dirty = true;
                            });
                          }
                        },
                        child: Column(
                          children: [
                            for (final entry in {
                              'tcp udp': 'TCP & UDP',
                              'tcp': 'TCP',
                              'udp': 'UDP',
                              if (!const {
                                'tcp udp',
                                'tcp',
                                'udp',
                              }.contains(_protocol))
                                _protocol: _protocol.toUpperCase(),
                            }.entries)
                              RadioListTile<String>(
                                value: entry.key,
                                enabled: !_busy,
                                title: Text(entry.value),
                                controlAffinity:
                                    ListTileControlAffinity.trailing,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _surface(
                      SwitchListTile.adaptive(
                        title: const Text('Port forward'),
                        value: _enabled,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                _enabled = value;
                                _dirty = true;
                              }),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ExpansionTile(
                      title: const Text('Advanced'),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                      initiallyExpanded:
                          _source != 'wan' || _destination != 'lan',
                      children: [
                        _zone(
                          'Source Zone',
                          _source,
                          (value) => _source = value,
                        ),
                        const SizedBox(height: 12),
                        _zone('Destination Zone', _destination, (value) {
                          _destination = value;
                          if (value == 'router') {
                            _address.text = widget.routerIp;
                          }
                        }, router: true),
                        const SizedBox(height: 18),
                      ],
                    ),
                    if (widget.forward != null) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _busy ? null : _delete,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete port forward'),
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.error,
                          foregroundColor: colors.onError,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
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
