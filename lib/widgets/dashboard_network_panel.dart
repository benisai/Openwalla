import 'package:flutter/material.dart';

/// Compact overview of reported logical networks and active access points.
class DashboardNetworkPanel extends StatelessWidget {
  const DashboardNetworkPanel({
    super.key,
    required this.data,
    required this.onNetwork,
    required this.onWifi,
  });

  final Map<String, dynamic> data;
  final VoidCallback onNetwork;
  final VoidCallback onWifi;

  static const _cyan = Color(0xFF18AEEA);
  static const _green = Color(0xFF20CF70);
  static const _orange = Color(0xFFF27C24);

  static bool _true(Object? value) =>
      value == true || value == 1 || value == '1';
  static bool _false(Object? value) =>
      value == false || value == 0 || value == '0';

  List<({String name, bool? up})>? get _networks {
    final dump = data['interfaceDump'];
    final interfaces = dump is Map ? dump['interface'] : null;
    if (interfaces is! List) return null;
    final networks = <String, bool?>{};
    for (final interface in interfaces.whereType<Map>()) {
      final name = '${interface['interface'] ?? ''}'.trim();
      if (name.isEmpty || name == 'loopback' || name == 'lo') continue;
      final state = interface['up'];
      networks[name] = _true(state)
          ? true
          : _false(state)
          ? false
          : null;
    }
    return [
      for (final entry in networks.entries) (name: entry.key, up: entry.value),
    ];
  }

  int? get _wifiCount {
    final wireless = data['wireless'];
    if (wireless is! Map) return null;
    final accessPoints = <String>{};
    for (final entry in wireless.entries) {
      final radio = entry.value;
      if (radio is! Map || _false(radio['up']) || _true(radio['disabled'])) {
        continue;
      }
      final interfaces = radio['interfaces'];
      if (interfaces is! List) continue;
      for (var index = 0; index < interfaces.length; index++) {
        final interface = interfaces[index];
        if (interface is! Map || _false(interface['up'])) continue;
        final config = interface['config'] is Map
            ? interface['config'] as Map
            : const {};
        final info = interface['iwinfo'] is Map
            ? interface['iwinfo'] as Map
            : const {};
        if (_true(config['disabled'])) continue;
        final mode = '${config['mode'] ?? info['mode'] ?? ''}'.toLowerCase();
        if (mode != 'ap' && mode != 'master' && mode != 'ap-wds') continue;
        // Count access-point interfaces, not unique SSIDs or repeater uplinks.
        accessPoints.add(
          '${entry.key}:${interface['section'] ?? interface['ifname'] ?? interface['name'] ?? index}',
        );
      }
    }
    return accessPoints.length;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final networks = _networks;
    return Row(
      key: const ValueKey('dashboard-network-panel'),
      children: [
        Icon(Icons.public_rounded, color: _cyan, size: 30),
        const SizedBox(width: 10),
        Expanded(
          flex: 3,
          child: InkWell(
            key: const ValueKey('dashboard-network-open'),
            onTap: onNetwork,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Network',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (networks == null || networks.isEmpty)
                    Text(
                      networks == null ? 'Unavailable' : 'No networks',
                      style: Theme.of(context).textTheme.labelSmall,
                    )
                  else
                    Wrap(
                      spacing: 3,
                      runSpacing: 4,
                      children: [
                        for (final network in networks.take(4))
                          Tooltip(
                            message:
                                '${network.name}: ${network.up == null
                                    ? 'Unknown'
                                    : network.up!
                                    ? 'Up'
                                    : 'Down'}',
                            child: Semantics(
                              label:
                                  '${network.name}: ${network.up == null
                                      ? 'Unknown'
                                      : network.up!
                                      ? 'Up'
                                      : 'Down'}',
                              child: Container(
                                key: ValueKey('network-status-${network.name}'),
                                width: 16,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: network.up == null
                                      ? colors.onSurfaceVariant.withValues(
                                          alpha: 0.25,
                                        )
                                      : network.up!
                                      ? _green
                                      : _orange,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Icon(
                                  Icons.settings_ethernet_rounded,
                                  size: 12,
                                  color: network.up == null
                                      ? colors.onSurfaceVariant
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        if (networks.length > 4)
                          Text(
                            '+${networks.length - 4}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _metric(
            context,
            icon: Icons.account_tree_outlined,
            count: networks?.length,
            label: 'Networks',
            tooltip: 'Network interfaces',
            onTap: onNetwork,
          ),
        ),
        Container(
          width: 1,
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          color: colors.outlineVariant.withValues(alpha: 0.5),
        ),
        Expanded(
          flex: 2,
          child: _metric(
            context,
            icon: Icons.wifi_rounded,
            count: _wifiCount,
            label: 'Wi-Fi',
            tooltip: 'Active Wi-Fi access points',
            onTap: onWifi,
          ),
        ),
      ],
    );
  }

  Widget _metric(
    BuildContext context, {
    required IconData icon,
    required int? count,
    required String label,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: '$tooltip: ${count ?? 'unavailable'}',
        button: true,
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey('dashboard-network-$label'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: _cyan),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${count ?? '--'} $label',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
