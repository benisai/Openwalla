import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/router_setup_screen.dart';
import 'package:openwalla/screens/routes_screen.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/luci_toast.dart';

enum _FlowTimeRange {
  oneHour('Last Hour', 1),
  sixHours('Last 6 Hours', 6),
  twelveHours('Last 12 Hours', 12),
  twentyFourHours('Last 24 Hours', 24);

  final String label;
  final int hours;

  const _FlowTimeRange(this.label, this.hours);
}

enum _FlowBlockType { domain, ip }

enum _FlowDomainScope { exact, root }

enum _FlowIpScope { device, network }

class FlowsScreen extends ConsumerStatefulWidget {
  final String? deviceMac;
  final String? deviceName;

  const FlowsScreen({super.key, this.deviceMac, this.deviceName});

  @override
  ConsumerState<FlowsScreen> createState() => _FlowsScreenState();
}

class _FlowItem {
  final String time;
  final String destination;
  final String country;
  final bool blocked;
  final String deviceName;
  final String deviceGroup;
  final String deviceIp;
  final String devicePort;
  final String macAddress;
  final String vendor;
  final String destinationIp;
  final String destinationPort;
  final String region;
  final String timestamp;
  final String direction;
  final String outboundInterface;
  final String status;
  final String transfer;

  const _FlowItem({
    required this.time,
    required this.destination,
    required this.country,
    required this.blocked,
    required this.deviceName,
    required this.deviceGroup,
    required this.deviceIp,
    required this.devicePort,
    required this.macAddress,
    required this.vendor,
    required this.destinationIp,
    required this.destinationPort,
    required this.region,
    required this.timestamp,
    required this.direction,
    required this.outboundInterface,
    required this.status,
    required this.transfer,
  });

  factory _FlowItem.fromNetify(
    NetifyFlow flow, {
    Map<String, String> hostnameByMac = const {},
    Map<String, String> hostnameByIp = const {},
  }) {
    final time = _formatClock(flow.timestamp.toLocal());
    final timestamp = _formatDateTime(flow.timestamp.toLocal());
    final destinationPort = flow.destinationPort == '0'
        ? '-'
        : flow.destinationPort;
    final devicePort = flow.localPort.isEmpty ? '-' : flow.localPort;
    final deviceName =
        hostnameByMac[flow.deviceMac] ??
        hostnameByIp[flow.localIp] ??
        (flow.localIp == '-' ? flow.deviceMac : flow.localIp);

    return _FlowItem(
      time: time,
      destination: flow.destination,
      country: flow.countryCode.isEmpty ? '?' : flow.countryCode,
      blocked: false,
      deviceName: deviceName.isEmpty ? '-' : deviceName,
      deviceGroup: '-',
      deviceIp: flow.localIp,
      devicePort: devicePort,
      macAddress: flow.deviceMac.isEmpty ? '-' : flow.deviceMac,
      vendor: '-',
      destinationIp: flow.destinationIp,
      destinationPort: destinationPort,
      region: flow.region.isEmpty ? flow.countryCode : flow.region,
      timestamp: timestamp,
      direction: flow.direction,
      outboundInterface: flow.interfaceName,
      status: 'Active',
      transfer: _formatBytes(flow.totalBytes),
    );
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

class _FlowsScreenState extends ConsumerState<FlowsScreen> {
  static const Color _cyan = Color(0xFF18AEEA);
  static const Color _red = Color(0xFFFF4D4F);
  static const int _pageSize = 250;
  static const int _maxLoadedFlows = 2000;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreFlows = true;
  bool _netifyMissing = false;
  String? _error;
  String? _selectedProtocolFilter;
  _FlowTimeRange _selectedTimeRange = _FlowTimeRange.twentyFourHours;
  int _flowCount = 0;
  int _loadGeneration = 0;
  Timer? _searchDebounce;
  final TextEditingController _searchController = TextEditingController();
  List<_FlowItem> _flows = const [];
  (Map<String, String>, Map<String, String>) _cachedHostnames = (
    const {},
    const {},
  );
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFlows());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
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

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      _loadMoreFlows();
    }
  }

  Future<void> _loadFlows() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _hasMoreFlows = true;
      _netifyMissing = false;
      _error = null;
    });

    try {
      final appState = ref.read(appStateProvider);
      final hasNetify = await appState.hasNetifySupport(
        context: mounted ? context : null,
      );
      if (!hasNetify) {
        if (!mounted) return;
        setState(() {
          _flowCount = 0;
          _flows = const [];
          _hasMoreFlows = false;
          _netifyMissing = true;
          _isLoading = false;
        });
        return;
      }
      final hostnamesFuture = _hostnameMaps(appState);
      final summaryFuture = appState.fetchOpenwallaFlowSummary(
        provider: OpenwallaFlowProvider.netify,
        protocolFilter: _selectedProtocolFilter,
        hoursBack: _selectedTimeRange.hours,
        deviceMac: widget.deviceMac,
        searchQuery: _searchController.text,
      );
      final flowsFuture = appState.fetchNetifyFlows(
        limit: _pageSize,
        protocolFilter: _selectedProtocolFilter,
        hoursBack: _selectedTimeRange.hours,
        deviceMac: widget.deviceMac,
        searchQuery: _searchController.text,
      );
      final hostnames = await hostnamesFuture;
      final flows = await flowsFuture;
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _cachedHostnames = hostnames;
        _flows = _mapFlowItems(flows, hostnames);
        _flowCount = flows.length;
        _hasMoreFlows = flows.length == _pageSize;
        _isLoading = false;
      });

      final summary = await summaryFuture;
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _flowCount = summary.count;
        _hasMoreFlows =
            _flows.length < summary.count && _flows.length < _maxLoadedFlows;
      });
      unawaited(_loadFlowBatches(generation));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load flow data.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadFlowBatches(int generation) async {
    while (mounted &&
        generation == _loadGeneration &&
        _hasMoreFlows &&
        _flows.length < _maxLoadedFlows) {
      await _loadMoreFlows(generation: generation);
    }
  }

  Future<void> _loadMoreFlows({int? generation}) async {
    if (!mounted || _isLoading || _isLoadingMore || !_hasMoreFlows) {
      return;
    }

    final activeGeneration = generation ?? _loadGeneration;
    if (activeGeneration != _loadGeneration) return;

    setState(() => _isLoadingMore = true);

    try {
      final appState = ref.read(appStateProvider);
      final requestLimit = (_maxLoadedFlows - _flows.length).clamp(
        1,
        _pageSize,
      );
      final flows = await appState.fetchNetifyFlows(
        limit: requestLimit,
        offset: _flows.length,
        protocolFilter: _selectedProtocolFilter,
        hoursBack: _selectedTimeRange.hours,
        deviceMac: widget.deviceMac,
        searchQuery: _searchController.text,
      );
      if (!mounted || activeGeneration != _loadGeneration) return;
      final items = _mapFlowItems(flows, _cachedHostnames);
      setState(() {
        _flows = [..._flows, ...items];
        _hasMoreFlows =
            flows.length == requestLimit &&
            _flows.length < _flowCount &&
            _flows.length < _maxLoadedFlows;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || activeGeneration != _loadGeneration) return;
      setState(() {
        _hasMoreFlows = false;
        _isLoadingMore = false;
      });
    }
  }

  List<_FlowItem> _mapFlowItems(
    List<NetifyFlow> flows,
    (Map<String, String>, Map<String, String>) hostnames,
  ) {
    return flows.map((flow) {
      return _FlowItem.fromNetify(
        flow,
        hostnameByMac: hostnames.$1,
        hostnameByIp: hostnames.$2,
      );
    }).toList();
  }

  Future<(Map<String, String>, Map<String, String>)> _hostnameMaps(
    AppState appState,
  ) async {
    final deviceDbNames = await appState.fetchDeviceNameMaps();
    final byMac = <String, String>{...deviceDbNames.$1};
    final byIp = <String, String>{...deviceDbNames.$2};
    final dhcpLeases =
        appState.dashboardData?['dhcpLeases']?['dhcp_leases']
            as List<dynamic>? ??
        const [];

    for (final lease in dhcpLeases) {
      if (lease is! Map) continue;
      final hostname = lease['hostname']?.toString().trim();
      if (hostname == null || hostname.isEmpty || hostname == '*') continue;

      final mac = lease['macaddr']?.toString().trim().toUpperCase();
      final ip = lease['ipaddr']?.toString().trim();
      if (mac != null && mac.isNotEmpty) {
        byMac.putIfAbsent(mac.replaceAll('-', ':'), () => hostname);
      }
      if (ip != null && ip.isNotEmpty) {
        byIp.putIfAbsent(ip, () => hostname);
      }
    }

    return (byMac, byIp);
  }

  void _toggleProtocolFilter(String protocol) {
    setState(() {
      _selectedProtocolFilter = _selectedProtocolFilter == protocol
          ? null
          : protocol;
    });
    _loadFlows();
  }

  void _changeTimeRange(_FlowTimeRange range) {
    if (_selectedTimeRange == range) return;
    setState(() {
      _selectedTimeRange = range;
    });
    _loadFlows();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _loadFlows);
  }

  void _clearSearch() {
    if (_searchController.text.isEmpty) return;
    _searchDebounce?.cancel();
    _searchController.clear();
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

  void _showFlowDetails(_FlowItem flow) {
    showDialog<void>(
      context: context,
      builder: (context) => _FlowDetailsDialog(flow: flow),
    );
  }

  void _openNetifySetup() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const RouterSetupScreen(netifyOnly: true),
      ),
    );
  }

  Future<void> _configureFlowStats() async {
    final appState = ref.read(appStateProvider);
    final settings = await appState.fetchFlowStatsSettings(context: context);
    if (!mounted) return;
    var enabled = settings.enabled;
    var pollSeconds = settings.pollSeconds;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Flow Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Usage statistics'),
                subtitle: const Text('Higher router CPU usage'),
                value: enabled,
                onChanged: (value) => setDialogState(() => enabled = value),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('Polling interval')),
                  Text('$pollSeconds seconds'),
                ],
              ),
              Slider(
                min: 2,
                max: 10,
                divisions: 8,
                value: pollSeconds.toDouble(),
                onChanged: enabled
                    ? (value) => setDialogState(
                        () => pollSeconds = value.round().clamp(2, 10),
                      )
                    : null,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    try {
      await appState.saveFlowStatsSettings(
        FlowStatsSettings(enabled: enabled, pollSeconds: pollSeconds),
        context: context,
      );
      if (!mounted) return;
      context.showToastSuccess(
        enabled ? 'Flow usage enabled' : 'Flow usage disabled',
      );
    } catch (error) {
      if (!mounted) return;
      context.showToastError('Could not update flow usage');
    }
  }

  Future<void> _showFlowUsage() async {
    final usage = await ref
        .read(appStateProvider)
        .fetchFlowStatsUsage(context: context);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Text(
                  'Flow Usage',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _FlowUsageMetric(
                        label: 'Downloaded',
                        value: _FlowItem._formatBytes(usage.downloadedBytes),
                        icon: Icons.arrow_downward_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FlowUsageMetric(
                        label: 'Uploaded',
                        value: _FlowItem._formatBytes(usage.uploadedBytes),
                        icon: Icons.arrow_upward_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              Expanded(
                child: usage.devices.isEmpty
                    ? const Center(child: Text('No flow usage collected yet.'))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: usage.devices.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final device = usage.devices[index];
                          return ListTile(
                            leading: const Icon(Icons.devices_rounded),
                            title: Text(device.device),
                            subtitle: Text(
                              '${_FlowItem._formatBytes(device.downloadedBytes)} down  •  ${_FlowItem._formatBytes(device.uploadedBytes)} up',
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: widget.deviceMac == null ? 'Network Flows' : 'Device Flows',
        showBack: true,
        actions: widget.deviceMac == null
            ? [
                IconButton(
                  tooltip: 'Flow usage',
                  onPressed: _showFlowUsage,
                  icon: const Icon(Icons.bar_chart_rounded),
                ),
                IconButton(
                  tooltip: 'Flow settings',
                  onPressed: _configureFlowStats,
                  icon: const Icon(Icons.settings_rounded),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadFlows,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                sliver: SliverToBoxAdapter(child: _buildFlowHeader(context)),
              ),
              if (_isLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_netifyMissing)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: _FlowSetupCard(onPressed: _openNetifySetup),
                  ),
                )
              else if (_error != null)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: _FlowEmptyCard(message: _error!, action: _loadFlows),
                  ),
                )
              else if (_flows.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: _FlowEmptyCard(
                      message: 'No Netify flow data yet.',
                      action: _loadFlows,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: _flows.length,
                    itemBuilder: (context, index) {
                      final flow = _flows[index];
                      return _FlowRowCard(
                        flow: flow,
                        isFirst: index == 0,
                        isLast: index == _flows.length - 1,
                        onTap: () => _showFlowDetails(flow),
                      );
                    },
                  ),
                ),
              SliverToBoxAdapter(child: _buildFlowFooter(context)),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlowHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.deviceMac != null) ...[
          Text(
            widget.deviceName?.trim().isNotEmpty == true
                ? widget.deviceName!.trim()
                : widget.deviceMac!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            PopupMenuButton<_FlowTimeRange>(
              initialValue: _selectedTimeRange,
              onSelected: _changeTimeRange,
              itemBuilder: (context) => _FlowTimeRange.values
                  .map(
                    (range) => PopupMenuItem<_FlowTimeRange>(
                      value: range,
                      child: Text(range.label),
                    ),
                  )
                  .toList(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedTimeRange.label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) {
            _searchDebounce?.cancel();
            _loadFlows();
          },
          decoration: InputDecoration(
            hintText: 'Search hostname or domain',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, value, child) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return IconButton(
                  tooltip: 'Clear search',
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.close_rounded),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          widget.deviceMac == null ? 'All Flows' : 'Device Flows',
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
                (label) => _FilterChip(
                  label: label,
                  selected: _selectedProtocolFilter == label,
                  onPressed: () => _toggleProtocolFilter(label),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildFlowFooter(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_isLoading && _flows.isNotEmpty && !_hasMoreFlows) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          _flowCount > _maxLoadedFlows
              ? 'Showing latest $_maxLoadedFlows flows'
              : 'End of flows',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _FlowUsageMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _FlowUsageMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(height: 10),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _FlowEmptyCard extends StatelessWidget {
  final String message;
  final VoidCallback action;

  const _FlowEmptyCard({required this.message, required this.action});

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

class _FlowSetupCard extends StatelessWidget {
  final VoidCallback onPressed;

  const _FlowSetupCard({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 22),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.account_tree_rounded,
            color: colorScheme.primary,
            size: 32,
          ),
          const SizedBox(height: 14),
          Text(
            'Detailed Flow is not installed',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Install Netify and the Openwalla Netify collector to enable detailed flow data.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Install Netify'),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = selected
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: foregroundColor,
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

class _FlowRowCard extends StatelessWidget {
  final _FlowItem flow;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  const _FlowRowCard({
    required this.flow,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  BorderRadius get _radius => BorderRadius.vertical(
    top: isFirst ? const Radius.circular(8) : Radius.zero,
    bottom: isLast ? const Radius.circular(8) : Radius.zero,
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: _radius,
        border: Border(
          left: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.42),
          ),
          right: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.42),
          ),
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.42),
          ),
          bottom: isLast
              ? BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.42),
                )
              : BorderSide.none,
        ),
      ),
      child: ClipRRect(
        borderRadius: _radius,
        child: _FlowRow(flow: flow, onTap: onTap),
      ),
    );
  }
}

class _FlowRow extends StatelessWidget {
  final _FlowItem flow;
  final VoidCallback onTap;

  const _FlowRow({required this.flow, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = flow.blocked
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurface;

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
                  decoration: flow.blocked ? TextDecoration.lineThrough : null,
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
                flow.destination,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  decoration: flow.blocked ? TextDecoration.lineThrough : null,
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

class _FlowDetailsDialog extends ConsumerWidget {
  final _FlowItem flow;

  const _FlowDetailsDialog({required this.flow});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog.fullscreen(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        appBar: LuciAppBar(
          title: 'Flow Details',
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
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                  children: [
                    _DetailSection(
                      title: 'Device',
                      rows: [
                        _DetailRow(
                          label: 'Name',
                          value: flow.deviceName,
                          icon: Icons.sensors_rounded,
                          iconColor: _FlowsScreenState._cyan,
                        ),
                        _DetailRow(label: 'IP Address', value: flow.deviceIp),
                        _DetailRow(label: 'Port', value: flow.devicePort),
                        _DetailRow(
                          label: 'MAC Address',
                          value: flow.macAddress,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _DetailSection(
                      title: 'Destination',
                      rows: [
                        _DetailRow(label: 'Name', value: flow.destination),
                        _DetailRow(
                          label: 'IP Address',
                          value: flow.destinationIp,
                        ),
                        _DetailRow(label: 'Port', value: flow.destinationPort),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _DetailSection(
                      title: 'Flow Detail',
                      rows: [
                        _DetailRow(label: 'Timestamp', value: flow.timestamp),
                        _DetailRow(label: 'Direction', value: flow.direction),
                        _DetailRow(
                          label: 'Outbound Interface',
                          value: flow.outboundInterface,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.96),
                  border: Border(
                    top: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () async {
                          final appState = ref.read(appStateProvider);
                          final hasPbr = await appState.hasPbrSupport(
                            context: context,
                          );
                          if (!context.mounted) return;
                          if (!hasPbr) {
                            context.showToastWarning(
                              'PBR component required',
                              subtitle:
                                  'Install it from Routes before creating a flow policy.',
                              actionKey: 'flow-route-pbr',
                            );
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const RoutesScreen(),
                              ),
                            );
                            return;
                          }
                          await showAddPbrPolicySheet(
                            context,
                            initialDestination: flow.destination,
                            initialName: 'Route ${flow.destination}',
                          );
                        },
                        icon: const Icon(Icons.alt_route_rounded),
                        label: const Text('Route'),
                        style: TextButton.styleFrom(
                          foregroundColor: _FlowsScreenState._cyan,
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => _showFlowBlockSheet(context, flow),
                        icon: const Icon(Icons.block_rounded),
                        label: const Text('Block'),
                        style: TextButton.styleFrom(
                          foregroundColor: _FlowsScreenState._red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFlowBlockSheet(BuildContext context, _FlowItem flow) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _FlowBlockSheet(flow: flow),
    );
  }
}

class _FlowBlockSheet extends ConsumerStatefulWidget {
  final _FlowItem flow;

  const _FlowBlockSheet({required this.flow});

  @override
  ConsumerState<_FlowBlockSheet> createState() => _FlowBlockSheetState();
}

class _FlowBlockSheetState extends ConsumerState<_FlowBlockSheet> {
  late _FlowBlockType _blockType;
  late _FlowDomainScope _domainScope;
  late _FlowIpScope _ipScope;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final domain = _sanitizeDomain(widget.flow.destination);
    _blockType = domain.isEmpty ? _FlowBlockType.ip : _FlowBlockType.domain;
    final root = _extractRootDomain(domain);
    _domainScope = root.isNotEmpty && root != domain
        ? _FlowDomainScope.exact
        : _FlowDomainScope.root;
    _ipScope = _isValidIp(widget.flow.deviceIp)
        ? _FlowIpScope.device
        : _FlowIpScope.network;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final domain = _sanitizeDomain(widget.flow.destination);
    final rootDomain = _extractRootDomain(domain);
    final canBlockDomain = domain.isNotEmpty;
    final canBlockIp = _isValidIp(widget.flow.destinationIp);
    final canBlockDeviceIp = _isValidIp(widget.flow.deviceIp);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Block Flow',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.flow.destination,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 18),
            SegmentedButton<_FlowBlockType>(
              segments: const [
                ButtonSegment(
                  value: _FlowBlockType.domain,
                  icon: Icon(Icons.language_rounded),
                  label: Text('Domain'),
                ),
                ButtonSegment(
                  value: _FlowBlockType.ip,
                  icon: Icon(Icons.public_off_rounded),
                  label: Text('IP'),
                ),
              ],
              selected: {_blockType},
              onSelectionChanged: (selection) {
                setState(() => _blockType = selection.first);
              },
            ),
            const SizedBox(height: 14),
            if (_blockType == _FlowBlockType.domain)
              _buildDomainOptions(context, domain, rootDomain, canBlockDomain)
            else
              _buildIpOptions(context, canBlockIp, canBlockDeviceIp),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    _isSaving ||
                        (_blockType == _FlowBlockType.domain &&
                            !canBlockDomain) ||
                        (_blockType == _FlowBlockType.ip && !canBlockIp)
                    ? null
                    : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.block_rounded),
                label: Text(_isSaving ? 'Saving...' : 'Save Block Rule'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDomainOptions(
    BuildContext context,
    String domain,
    String rootDomain,
    bool canBlockDomain,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!canBlockDomain) {
      return _FlowActionNotice(
        icon: Icons.info_outline_rounded,
        message: 'This flow does not include a valid domain.',
      );
    }
    return Column(
      children: [
        _FlowOptionTile(
          selected: _domainScope == _FlowDomainScope.exact,
          onTap: () => setState(() => _domainScope = _FlowDomainScope.exact),
          title: const Text('Exact domain'),
          subtitle: domain,
        ),
        _FlowOptionTile(
          selected: _domainScope == _FlowDomainScope.root,
          onTap: rootDomain.isEmpty
              ? null
              : () => setState(() => _domainScope = _FlowDomainScope.root),
          title: const Text('Root domain'),
          subtitle: rootDomain.isEmpty ? domain : rootDomain,
        ),
        _FlowActionNotice(
          icon: Icons.dns_rounded,
          message: 'Adds a DHCP custom domain pointing to 127.0.0.1.',
          color: colorScheme.primary,
        ),
      ],
    );
  }

  Widget _buildIpOptions(
    BuildContext context,
    bool canBlockIp,
    bool canBlockDeviceIp,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!canBlockIp) {
      return _FlowActionNotice(
        icon: Icons.info_outline_rounded,
        message: 'This flow does not include a valid destination IP.',
      );
    }
    return Column(
      children: [
        _FlowOptionTile(
          selected: _ipScope == _FlowIpScope.device,
          onTap: canBlockDeviceIp
              ? () => setState(() => _ipScope = _FlowIpScope.device)
              : null,
          title: const Text('This device only'),
          subtitle: canBlockDeviceIp
              ? '${widget.flow.deviceIp} -> ${widget.flow.destinationIp}'
              : 'Source device IP is missing for this flow.',
        ),
        _FlowOptionTile(
          selected: _ipScope == _FlowIpScope.network,
          onTap: () => setState(() => _ipScope = _FlowIpScope.network),
          title: const Text('Whole network'),
          subtitle: 'Any LAN device -> ${widget.flow.destinationIp}',
        ),
        _FlowActionNotice(
          icon: Icons.security_rounded,
          message: 'Adds a firewall reject rule for the destination IP.',
          color: colorScheme.error,
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final appState = ref.read(appStateProvider);
      final messenger = ScaffoldMessenger.of(context);
      if (_blockType == _FlowBlockType.domain) {
        final blockedDomain = await appState.blockNetifyFlowDomain(
          domain: widget.flow.destination,
          rootDomain: _domainScope == _FlowDomainScope.root,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text('Blocked DNS for $blockedDomain')),
        );
      } else {
        await appState.blockNetifyFlowDestinationIp(
          destinationIp: widget.flow.destinationIp,
          sourceIp: widget.flow.deviceIp,
          wholeNetwork: _ipScope == _FlowIpScope.network,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _ipScope == _FlowIpScope.network
                  ? 'Blocked ${widget.flow.destinationIp} for the network'
                  : 'Blocked ${widget.flow.destinationIp} for this device',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save block: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  static String _sanitizeDomain(String value) {
    final domain = value.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (domain.isEmpty ||
        domain.length > 253 ||
        domain.startsWith('.') ||
        domain.endsWith('.') ||
        domain.contains('..') ||
        !RegExp(r'^[a-z0-9.-]+$').hasMatch(domain) ||
        _isValidIp(domain)) {
      return '';
    }
    return domain;
  }

  static String _extractRootDomain(String domain) {
    final sanitized = _sanitizeDomain(domain);
    if (sanitized.isEmpty) return '';
    final parts = sanitized
        .split('.')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 2) return sanitized;
    const secondLevelTlds = {
      'co.uk',
      'org.uk',
      'ac.uk',
      'gov.uk',
      'co.jp',
      'com.au',
      'net.au',
      'org.au',
      'co.nz',
    };
    final lastTwo = parts.sublist(parts.length - 2).join('.');
    if (parts.length >= 3 && secondLevelTlds.contains(lastTwo)) {
      return parts.sublist(parts.length - 3).join('.');
    }
    return lastTwo;
  }

  static bool _isValidIp(String value) =>
      RegExp(
        r'^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.|$)){4}$',
      ).hasMatch(value.trim()) ||
      value.trim().contains(':');
}

class _FlowOptionTile extends StatelessWidget {
  final bool selected;
  final VoidCallback? onTap;
  final Widget title;
  final String subtitle;

  const _FlowOptionTile({
    required this.selected,
    required this.onTap,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEnabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.12)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.42)
                  : colorScheme.outlineVariant.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle(
                      style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                        color: isEnabled
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.55,
                              ),
                        fontWeight: FontWeight.w800,
                      ),
                      child: title,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlowActionNotice extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color? color;

  const _FlowActionNotice({
    required this.icon,
    required this.message,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedColor = color ?? colorScheme.onSurfaceVariant;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: resolvedColor.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(icon, color: resolvedColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<_DetailRow> rows;

  const _DetailSection({required this.title, required this.rows});

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

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;

  const _DetailRow({
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.32),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (icon != null) ...[
                Icon(icon, color: iconColor ?? colorScheme.primary, size: 18),
                const SizedBox(width: 8),
              ],
              Flexible(
                flex: 2,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
