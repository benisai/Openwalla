import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/services/router_system_settings_service.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/luci_toast.dart';

class RouterSystemSettingsScreen extends ConsumerStatefulWidget {
  final bool timezone;

  const RouterSystemSettingsScreen({super.key, this.timezone = false});

  @override
  ConsumerState<RouterSystemSettingsScreen> createState() =>
      _RouterSystemSettingsScreenState();
}

class _RouterSystemSettingsScreenState
    extends ConsumerState<RouterSystemSettingsScreen> {
  final _hostname = TextEditingController();
  final _search = TextEditingController();
  Map<String, String> _zones = {};
  String _selected = 'UTC';
  String _original = '';
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hostname.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final app = ref.read(appStateProvider);
      final settings = await app.fetchRouterSystemSettings();
      final zones = widget.timezone
          ? await app.fetchRouterTimezones()
          : <String, String>{};
      if (!mounted) return;
      setState(() {
        _hostname.text = settings.hostname;
        _selected = settings.zoneName;
        _original = widget.timezone ? settings.zoneName : settings.hostname;
        _zones = zones;
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

  Future<void> _save() async {
    if (!widget.timezone &&
        !RouterSystemSettingsService.validHostname(_hostname.text.trim())) {
      context.showToastWarning(
        'Check hostname',
        subtitle: 'Use letters, numbers, and hyphens in valid hostname labels.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final app = ref.read(appStateProvider);
      if (widget.timezone) {
        await app.changeRouterTimezone(_selected);
      } else {
        await app.changeRouterHostname(_hostname.text);
      }
      if (!mounted) return;
      context.showToastSuccess(
        widget.timezone ? 'Timezone updated' : 'Hostname updated',
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      context.showToastError(
        widget.timezone
            ? 'Could not update timezone'
            : 'Could not update hostname',
        subtitle: error.toString().replaceFirst('Bad state: ', ''),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final changed = widget.timezone
        ? _selected != _original && _zones.containsKey(_selected)
        : _hostname.text.trim() != _original;
    final names =
        _zones.keys
            .where(
              (name) => name.toLowerCase().contains(
                _search.text.trim().toLowerCase(),
              ),
            )
            .toList()
          ..sort();
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: LuciAppBar(
          title: widget.timezone ? 'Timezone' : 'Change Hostname',
          showBack: true,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : widget.timezone
            ? Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _search,
                      enabled: !_saving,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Search timezones',
                        prefixIcon: const Icon(Icons.search),
                        helperText: 'Current: $_original',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: names.isEmpty
                        ? const Center(child: Text('No matching timezones'))
                        : ListView.builder(
                            itemCount: names.length,
                            itemBuilder: (context, index) {
                              final name = names[index];
                              return ListTile(
                                title: Text(name),
                                selected: name == _selected,
                                trailing: name == _selected
                                    ? const Icon(Icons.check_rounded)
                                    : null,
                                enabled: !_saving,
                                onTap: () => setState(() => _selected = name),
                              );
                            },
                          ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: _hostname,
                    enabled: !_saving,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (changed && !_saving) _save();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Hostname',
                      prefixIcon: Icon(Icons.router_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: _loading || _error != null
            ? null
            : SafeArea(
                minimum: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: changed && !_saving ? _save : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving' : 'Save'),
                ),
              ),
      ),
    );
  }
}
