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
  AdblockReport? _report;
  String? _error;
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (mounted &&
          !_loading &&
          ModalRoute.of(context)?.isCurrent == true &&
          (lifecycle == null || lifecycle == AppLifecycleState.resumed)) {
        unawaited(_load());
      }
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await ref.read(appStateProvider).fetchAdblockReport();
      if (mounted) setState(() => _report = report);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not read reports. Check the router connection and Openwalla ACL.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final report = _report;
    final rows =
        report?.requests
            .where((row) => row.matches(_search.text.trim()))
            .toList() ??
        <AdblockDnsRequest>[];
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
                decoration: InputDecoration(
                  hintText: 'Search reports',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(_search.clear),
                        ),
                ),
                onChanged: (_) => setState(() {}),
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
                    Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      children: [
                        _count('Queries', report.total),
                        _count('NXDOMAIN', report.blocked),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Updated ${report.generatedAt.toLocal().toString().split('.').first}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (report.start.isNotEmpty && report.end.isNotEmpty)
                      Text(
                        '${report.start} - ${report.end}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 6),
                    Text(
                      '${rows.length} of ${report.requests.length} recent queries',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loading ? () async {} : _load,
                child: rows.isEmpty
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
                                  : report == null
                                  ? 'Waiting for the first DNS report.'
                                  : _search.text.trim().isNotEmpty
                                  ? 'No matching queries'
                                  : 'No DNS queries in this report',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 16, endIndent: 16),
                        itemBuilder: (_, index) {
                          final row = rows[index];
                          return ListTile(
                            title: Text(
                              row.domain,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                row.client,
                                [
                                  row.date,
                                  row.time,
                                ].where((text) => text.isNotEmpty).join(' '),
                                [
                                  row.resultLabel,
                                  row.type,
                                  row.interface,
                                ].where((text) => text.isNotEmpty).join(' - '),
                              ].where((text) => text.isNotEmpty).join('\n'),
                            ),
                            leading: Icon(
                              row.result == 'OK'
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.info_outline_rounded,
                              color: row.result == 'OK'
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
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

  Widget _count(String label, int value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$value', style: Theme.of(context).textTheme.titleLarge),
      Text(label),
    ],
  );
}
