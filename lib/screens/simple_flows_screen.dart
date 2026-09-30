import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class SimpleFlowsScreen extends ConsumerStatefulWidget {
  const SimpleFlowsScreen({super.key});

  @override
  ConsumerState<SimpleFlowsScreen> createState() => _SimpleFlowsScreenState();
}

class _SimpleFlowItem {
  final String time;
  final String source;
  final String sourceLabel;
  final String destination;
  final String protocol;
  final String destinationPort;
  final String timestamp;
  final String status;
  final String transfer;

  const _SimpleFlowItem({
    required this.time,
    required this.source,
    required this.sourceLabel,
    required this.destination,
    required this.protocol,
    required this.destinationPort,
    required this.timestamp,
    required this.status,
    required this.transfer,
  });

  factory _SimpleFlowItem.fromConnectionFlow(
    NetifyFlow flow, {
    Map<String, String> hostnameByIp = const {},
  }) {
    final parts = flow.rawJson.split('|');
    final source = parts.length > 3 ? parts[3].trim() : flow.localIp;
    final destination = parts.length > 4 ? parts[4].trim() : flow.destination;
    final transfer = parts.length > 5
        ? parts[5].trim()
        : _formatBytes(flow.totalBytes);
    final status = parts.length > 6 ? parts[6].trim() : '-';
    final sourceIp = _endpointIp(source);

    return _SimpleFlowItem(
      time: _formatClock(flow.timestamp.toLocal()),
      source: source.isEmpty ? '-' : source,
      sourceLabel: hostnameByIp[sourceIp] ?? (source.isEmpty ? '-' : source),
      destination: destination.isEmpty ? '-' : destination,
      protocol: flow.protocol,
      destinationPort: flow.destinationPort.isEmpty
          ? flow.protocol
          : '${flow.protocol} ${flow.destinationPort}',
      timestamp: _formatDateTime(flow.timestamp.toLocal()),
      status: status.isEmpty ? '-' : status,
      transfer: transfer,
    );
  }

  static String _endpointIp(String endpoint) {
    final trimmed = endpoint.trim();
    final bracketMatch = RegExp(r'^\[([^\]]+)\]').firstMatch(trimmed);
    if (bracketMatch != null) return bracketMatch.group(1) ?? '';
    final colon = trimmed.lastIndexOf(':');
    if (colon > 0 && trimmed.indexOf(':') == colon) {
      return trimmed.substring(0, colon);
    }
    return trimmed;
  }

  static String _formatClock(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  static String _formatDateTime(DateTime time) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[time.month - 1]} ${time.day}, ${time.year} at ${_formatClock(time)}';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)} GB';
  }
}

class _SimpleFlowsScreenState extends ConsumerState<SimpleFlowsScreen> {
  static const int _pageSize = 250;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreFlows = true;
  String? _error;
  String? _selectedProtocolFilter;
  int _flowCount = 0;
  List<_SimpleFlowItem> _flows = const [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFlows());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _isLoading ||
        _isLoadingMore ||
        !_hasMoreFlows) {
      return;
    }

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 320) {
      _loadMoreFlows();
    }
  }

  Future<void> _loadFlows() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _hasMoreFlows = true;
      _error = null;
    });

    try {
      final appState = ref.read(appStateProvider);
      final hostnames = await _hostnameByIp(appState);
      final summary = await appState.fetchOpenwallaFlowSummary(
        provider: OpenwallaFlowProvider.conntrack,
        protocolFilter: _selectedProtocolFilter,
      );
      if (summary.provider == OpenwallaFlowProvider.none) {
        if (!mounted) return;
        setState(() {
          _flowCount = 0;
          _flows = const [];
          _hasMoreFlows = false;
          _isLoading = false;
        });
        return;
      }

      final flows = await appState.fetchConnectionFlows(
        limit: _pageSize,
        protocolFilter: _selectedProtocolFilter,
      );
      if (!mounted) return;
      setState(() {
        _flowCount = summary.count;
        _flows = flows
            .map(
              (flow) => _SimpleFlowItem.fromConnectionFlow(
                flow,
                hostnameByIp: hostnames,
              ),
            )
            .toList();
        _hasMoreFlows = flows.length == _pageSize && _flows.length < _flowCount;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load simple flow data.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreFlows() async {
    if (!mounted || _isLoading || _isLoadingMore || !_hasMoreFlows) return;
    setState(() => _isLoadingMore = true);

    try {
      final appState = ref.read(appStateProvider);
      final hostnames = await _hostnameByIp(appState);
      final flows = await appState.fetchConnectionFlows(
        limit: _pageSize,
        offset: _flows.length,
        protocolFilter: _selectedProtocolFilter,
      );
      if (!mounted) return;
      setState(() {
        _flows = [
          ..._flows,
          ...flows.map(
            (flow) => _SimpleFlowItem.fromConnectionFlow(
              flow,
              hostnameByIp: hostnames,
            ),
          ),
        ];
        _hasMoreFlows = flows.length == _pageSize && _flows.length < _flowCount;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasMoreFlows = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<Map<String, String>> _hostnameByIp(AppState appState) async {
    final deviceDbNames = await appState.fetchDeviceNameMaps();
    final byIp = <String, String>{...deviceDbNames.$2};
    final dhcpLeases =
        appState.dashboardData?['dhcpLeases']?['dhcp_leases']
            as List<dynamic>? ??
        const [];

    for (final lease in dhcpLeases) {
      if (lease is! Map) continue;
      final hostname = lease['hostname']?.toString().trim();
      final ip = lease['ipaddr']?.toString().trim();
      if (hostname == null ||
          hostname.isEmpty ||
          hostname == '*' ||
          ip == null ||
          ip.isEmpty) {
        continue;
      }
      byIp.putIfAbsent(ip, () => hostname);
    }

    return byIp;
  }

  void _toggleProtocolFilter(String protocol) {
    setState(() {
      _selectedProtocolFilter = _selectedProtocolFilter == protocol
          ? null
          : protocol;
    });
    _loadFlows();
  }

  String _formatCount(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final remaining = text.length - i;
      buffer.write(text[i]);
      if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
    }
    return buffer.toString();
  }

  void _showFlowDetails(_SimpleFlowItem flow) {
    showDialog<void>(
      context: context,
      builder: (context) => _SimpleFlowDetailsDialog(flow: flow),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const LuciAppBar(title: 'Simple Flows', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadFlows,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Text(
                'Last 24 Hours',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Conntrack Flows',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatCount(_flowCount),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['HTTP', 'HTTPS', 'DNS']
                    .map(
                      (label) => _SimpleFilterChip(
                        label: label,
                        selected: _selectedProtocolFilter == label,
                        onPressed: () => _toggleProtocolFilter(label),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _SimpleFlowEmptyCard(message: _error!, action: _loadFlows)
              else if (_flows.isEmpty)
                _SimpleFlowEmptyCard(
                  message: 'No simple flow data yet.',
                  action: _loadFlows,
                )
              else
                _SimpleFlowListCard(flows: _flows, onTapFlow: _showFlowDetails),
              if (_isLoadingMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (!_isLoading && _flows.isNotEmpty && !_hasMoreFlows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'End of flows',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimpleFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _SimpleFilterChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: selected
            ? colorScheme.onPrimary
            : colorScheme.onSurfaceVariant,
        backgroundColor: selected ? colorScheme.primary : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        minimumSize: Size.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(
          color: selected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class _SimpleFlowEmptyCard extends StatelessWidget {
  final String message;
  final VoidCallback action;

  const _SimpleFlowEmptyCard({required this.message, required this.action});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 28),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: action,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

class _SimpleFlowListCard extends StatelessWidget {
  final List<_SimpleFlowItem> flows;
  final ValueChanged<_SimpleFlowItem> onTapFlow;

  const _SimpleFlowListCard({required this.flows, required this.onTapFlow});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        children: flows
            .map(
              (flow) =>
                  _SimpleFlowRow(flow: flow, onTap: () => onTapFlow(flow)),
            )
            .toList(),
      ),
    );
  }
}

class _SimpleFlowRow extends StatelessWidget {
  final _SimpleFlowItem flow;
  final VoidCallback onTap;

  const _SimpleFlowRow({required this.flow, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final destinationIp = _SimpleFlowItem._endpointIp(flow.destination);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                flow.time,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                destinationIp.isEmpty ? flow.destination : destinationIp,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimpleFlowDetailsDialog extends StatelessWidget {
  final _SimpleFlowItem flow;

  const _SimpleFlowDetailsDialog({required this.flow});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Dialog.fullscreen(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        appBar: LuciAppBar(
          title: 'Simple Flow',
          showBack: true,
          actions: [
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Text(
                'Simple Flow uses Conntrack connection-level data. Detailed app metadata requires Netify.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 16),
              _SimpleDetailSection(
                title: 'Connection',
                rows: [
                  _SimpleDetailRow(label: 'Timestamp', value: flow.timestamp),
                  _SimpleDetailRow(label: 'Protocol', value: flow.protocol),
                  _SimpleDetailRow(label: 'Status', value: flow.status),
                  _SimpleDetailRow(label: 'Transfer', value: flow.transfer),
                ],
              ),
              const SizedBox(height: 18),
              _SimpleDetailSection(
                title: 'Endpoints',
                rows: [
                  _SimpleDetailRow(label: 'Source', value: flow.source),
                  _SimpleDetailRow(
                    label: 'Source Name',
                    value: flow.sourceLabel,
                  ),
                  _SimpleDetailRow(
                    label: 'Destination',
                    value: flow.destination,
                  ),
                  _SimpleDetailRow(
                    label: 'Destination Port',
                    value: flow.destinationPort,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimpleDetailSection extends StatelessWidget {
  final String title;
  final List<_SimpleDetailRow> rows;

  const _SimpleDetailSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.38),
            ),
          ),
          child: Column(children: rows),
        ),
      ],
    );
  }
}

class _SimpleDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _SimpleDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.22),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
