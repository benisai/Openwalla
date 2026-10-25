import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/services/vlan_discovery_service.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class VlansScreen extends ConsumerStatefulWidget {
  const VlansScreen({super.key});

  @override
  ConsumerState<VlansScreen> createState() => _VlansScreenState();
}

class _VlansScreenState extends ConsumerState<VlansScreen> {
  VlanTopology? _topology;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final topology = await ref.read(appStateProvider).fetchVlanTopology();
      if (!mounted) return;
      setState(() {
        _topology = topology;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Widget _heading(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  Widget _vlan(VlanEntry vlan) {
    final topology = _topology!;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text('VLAN ${vlan.id}'),
        subtitle: Text('${vlan.device} · ${vlan.kindLabel}'),
        leading: Icon(
          Icons.account_tree_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        children: [
          _detail('Section', vlan.section),
          _detail(
            'Interfaces',
            vlan.interfaces.isEmpty
                ? (vlan.kind == VlanKind.switchVlan ? 'Not resolved' : 'None')
                : vlan.interfaces.join(', '),
          ),
          if (vlan.local != null)
            _detail(
              'Local participation',
              vlan.local! ? 'Enabled' : 'Disabled',
            ),
          for (final member in vlan.ports)
            Builder(
              builder: (context) {
                final matching = topology.ports.where(
                  (p) =>
                      p.name == member.port &&
                      (vlan.kind != VlanKind.switchVlan
                          ? p.switchName == null
                          : p.switchName == vlan.device),
                );
                final label = matching.isEmpty
                    ? member.port
                    : matching.first.label;
                return _detail(
                  label,
                  '${member.tagged ? 'Tagged' : 'Untagged'}${member.primary ? ' · PVID' : ''}',
                );
              },
            ),
          if (vlan.ports.isEmpty) _detail('Ports', 'None reported'),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );

  Widget _list(List<Widget> children) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final topology = _topology;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: LuciAppBar(
          title: 'VLANs',
          showBack: true,
          actions: [
            IconButton(
              tooltip: 'Refresh VLANs',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
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
            : topology == null
            ? const SizedBox.shrink()
            : Column(
                children: [
                  ListTile(
                    title: Text(topology.layoutLabel),
                    subtitle: Text(
                      '${topology.vlans.length} VLANs · ${topology.bridges.length} bridges',
                    ),
                    trailing: Text(
                      'Read-only',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  for (final warning in topology.warnings)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(warning)),
                        ],
                      ),
                    ),
                  const TabBar(
                    tabs: [
                      Tab(text: 'VLANs'),
                      Tab(text: 'Ports & Bridges'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _list([
                          if (topology.vlans.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(32),
                              child: Text(
                                'No configured VLANs',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          const SizedBox(height: 12),
                          ...topology.vlans.map(_vlan),
                        ]),
                        _list([
                          if (topology.bridges.isNotEmpty) _heading('Bridges'),
                          for (final bridge in topology.bridges)
                            ListTile(
                              leading: const Icon(Icons.hub_outlined),
                              title: Text(bridge.name),
                              subtitle: Text(
                                '${bridge.ports.isEmpty ? 'No ports reported' : bridge.ports.join(', ')}\n'
                                'VLAN filtering: ${bridge.filtering == null
                                    ? 'Automatic / not reported'
                                    : bridge.filtering!
                                    ? 'Enabled'
                                    : 'Disabled'}',
                              ),
                            ),
                          _heading('Ports'),
                          if (topology.ports.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'No port mapping reported',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          for (final port in topology.ports)
                            ListTile(
                              leading: Icon(
                                port.kind == 'CPU connection'
                                    ? Icons.memory_outlined
                                    : Icons.settings_ethernet_rounded,
                              ),
                              title: Text(port.label),
                              subtitle: Text(
                                [
                                  port.kind,
                                  if (port.switchName != null)
                                    '${port.switchName} · port ${port.name}',
                                  ...port.bridges,
                                ].join(' · '),
                              ),
                              trailing: port.link == null
                                  ? null
                                  : Icon(
                                      Icons.circle,
                                      size: 10,
                                      color: port.link!
                                          ? Colors.green
                                          : Theme.of(
                                              context,
                                            ).colorScheme.outline,
                                    ),
                            ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
