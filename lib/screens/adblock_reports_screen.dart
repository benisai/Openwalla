import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/adblock_report.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class AdblockReportsScreen extends ConsumerStatefulWidget {
  const AdblockReportsScreen({super.key});

  @override
  ConsumerState<AdblockReportsScreen> createState() =>
      _AdblockReportsScreenState();
}

class _AdblockReportsScreenState extends ConsumerState<AdblockReportsScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _rows = <AdblockDnsRequest>[];
  AdblockReport? _report;
  String? _error;
  bool _loading = true;
  int _generation = 0;
  Timer? _refreshTimer;
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 300 &&
          !_loading &&
          _error == null &&
          _report?.hasMore == true) {
        unawaited(_load(more: true));
      }
    });
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (mounted &&
          !_loading &&
          _rows.length <= 200 &&
          (!_scroll.hasClients || _scroll.offset < 100) &&
          ModalRoute.of(context)?.isCurrent == true &&
          (lifecycle == null || lifecycle == AppLifecycleState.resumed)) {
        unawaited(_load());
      }
    });
  }

  void _searchChanged() {
    _searchTimer?.cancel();
    _generation++;
    setState(() {
      _rows.clear();
      _report = null;
      _loading = true;
      _error = null;
    });
    _searchTimer = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _load({bool more = false}) async {
    if (!mounted) return;
    final generation = ++_generation;
    final before = more ? _report?.nextId : null;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await ref
          .read(appStateProvider)
          .fetchAdblockReport(search: _search.text.trim(), beforeId: before);
      if (mounted && generation == _generation) {
        setState(() {
          if (!more) _rows.clear();
          _rows.addAll(report?.requests ?? []);
          _report = report;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error =
              'Could not read reports. Check the connection or update AdBlock in Router Setup.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _refreshTimer?.cancel();
    _searchTimer?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final report = _report;
    return Scaffold(
      appBar: LuciAppBar(
        title: 'AdBlock Reports',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Refresh reports',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _search,
                maxLength: 256,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Search domains or devices',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            _searchChanged();
                          },
                        ),
                ),
                onChanged: (_) => _searchChanged(),
              ),
            ),
            SizedBox(
              height: 2,
              child: _loading
                  ? const LinearProgressIndicator(minHeight: 2)
                  : null,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: TextStyle(color: colors.error)),
              ),
            if (report != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${report.total} blocked queries',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${_rows.length} of ${report.matching} matches',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (report.heartbeat == null ||
                        DateTime.now().difference(report.heartbeat!).inMinutes >
                            2)
                      Text(
                        'Collection is not active',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loading ? () async {} : _load,
                child: _rows.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _loading
                                  ? 'Loading reports...'
                                  : _error != null && report == null
                                  ? 'Report unavailable'
                                  : _search.text.trim().isNotEmpty
                                  ? 'No matching queries'
                                  : 'No blocked DNS queries recorded yet.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount:
                            _rows.length + (report?.hasMore == true ? 1 : 0),
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 16, endIndent: 16),
                        itemBuilder: (_, index) {
                          if (index == _rows.length) {
                            return TextButton.icon(
                              onPressed: _loading
                                  ? null
                                  : () => _load(more: true),
                              icon: const Icon(Icons.expand_more_rounded),
                              label: Text(
                                _loading ? 'Loading...' : 'Load more',
                              ),
                            );
                          }
                          final row = _rows[index];
                          return ListTile(
                            leading: Icon(
                              Icons.block_rounded,
                              color: colors.error,
                            ),
                            title: Text(
                              row.domain,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                row.deviceLabel,
                                if (row.deviceName.isNotEmpty) row.client,
                                if (row.mac.isNotEmpty) row.mac,
                                '${row.timestamp.toLocal().toString().split('.').first} - ${row.type}',
                                'AdBlock rule: ${row.matchedRule}',
                              ].join('\n'),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
