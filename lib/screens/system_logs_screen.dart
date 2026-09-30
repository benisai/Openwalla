import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class SystemLogsScreen extends ConsumerStatefulWidget {
  const SystemLogsScreen({super.key});

  @override
  ConsumerState<SystemLogsScreen> createState() => _SystemLogsScreenState();
}

class _SystemLogsScreenState extends ConsumerState<SystemLogsScreen> {
  late Future<List<String>> _logsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _logsFuture = _loadLogs();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<String>> _loadLogs() {
    return ref
        .read(appStateProvider)
        .fetchSystemLogs(limit: 400, context: context);
  }

  Future<void> _refresh() async {
    final future = _loadLogs();
    setState(() {
      _logsFuture = future;
    });
    await future;
  }

  List<String> _filteredLogs(List<String> logs) {
    if (_query.isEmpty) return logs;
    return logs.where((line) => line.toLowerCase().contains(_query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const LuciAppBar(title: 'System Logs', showBack: true),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search logs',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _searchController.clear,
                        ),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: FutureBuilder<List<String>>(
                  future: _logsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final logs = snapshot.data ?? const <String>[];
                    final visibleLogs = _filteredLogs(logs);
                    if (logs.isEmpty) {
                      return _EmptyLogsState(
                        icon: Icons.article_rounded,
                        title: 'No logs found',
                        message: 'Pull down to try reading router logs again.',
                      );
                    }
                    if (visibleLogs.isEmpty) {
                      return _EmptyLogsState(
                        icon: Icons.search_off_rounded,
                        title: 'No matching logs',
                        message: 'Try another search term.',
                      );
                    }

                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: visibleLogs.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final line = visibleLogs[index];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                          child: SelectableText(
                            line,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontFamily: 'monospace',
                                  height: 1.35,
                                ),
                          ),
                        );
                      },
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

class _EmptyLogsState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyLogsState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 24),
      children: [
        Icon(icon, size: 52, color: colorScheme.onSurfaceVariant),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
