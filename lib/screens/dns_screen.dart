import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

enum _DnsPanel { dns, blocked }

class DnsScreen extends ConsumerStatefulWidget {
  const DnsScreen({super.key});

  @override
  ConsumerState<DnsScreen> createState() => _DnsScreenState();
}

class _DnsScreenState extends ConsumerState<DnsScreen> {
  final PageController _pageController = PageController();
  List<OpenwrtDnsHostEntry> _entries = const [];
  int _panelIndex = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final entries = await ref
          .read(appStateProvider)
          .fetchDnsHostEntries(context: context);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load DNS entries.';
        _isLoading = false;
      });
    }
  }

  Future<void> _showEntrySheet([OpenwrtDnsHostEntry? entry]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _DnsEntrySheet(entry: entry),
    );
    if (saved == true) await _load();
  }

  Future<void> _deleteEntry(OpenwrtDnsHostEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete DNS Entry'),
        content: Text('Delete ${entry.hostname}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(appStateProvider).deleteDnsHostEntry(entry.section);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('DNS entry deleted.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete entry: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dnsEntries = _entries
        .where((entry) => !entry.isBlockedSinkhole)
        .toList(growable: false);
    final blockedEntries = _entries
        .where((entry) => entry.isBlockedSinkhole)
        .toList(growable: false);

    return Scaffold(
      appBar: LuciAppBar(title: 'DNS', showBack: true),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _DnsPanelSwitcher(
              selectedIndex: _panelIndex,
              onSelected: _selectPanel,
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _panelIndex = index),
                children: [
                  _buildPanel(
                    panel: _DnsPanel.dns,
                    entries: dnsEntries,
                    title: 'DNS Entries',
                    emptyMessage: 'No custom DNS entries found.',
                  ),
                  _buildPanel(
                    panel: _DnsPanel.blocked,
                    entries: blockedEntries,
                    title: 'Blocked Domains',
                    emptyMessage: 'No blocked DNS entries found.',
                  ),
                ],
              ),
            ),
            _DnsPanelDots(count: 2, currentIndex: _panelIndex),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _selectPanel(int index) {
    setState(() => _panelIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildPanel({
    required _DnsPanel panel,
    required List<OpenwrtDnsHostEntry> entries,
    required String title,
    required String emptyMessage,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isBlockedPanel = panel == _DnsPanel.blocked;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _showEntrySheet(
                  isBlockedPanel
                      ? const OpenwrtDnsHostEntry(
                          section: '',
                          hostname: '',
                          ipAddress: '127.0.0.1',
                        )
                      : null,
                ),
                icon: Icon(
                  isBlockedPanel ? Icons.block_rounded : Icons.add_rounded,
                ),
                label: Text(isBlockedPanel ? 'Block' : 'Add'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _DnsEmptyCard(message: _error!, onRefresh: _load)
          else if (entries.isEmpty)
            _DnsEmptyCard(message: emptyMessage, onRefresh: _load)
          else
            ...entries.map(
              (entry) => _DnsEntryCard(
                entry: entry,
                onEdit: () => _showEntrySheet(entry),
                onDelete: () => _deleteEntry(entry),
              ),
            ),
        ],
      ),
    );
  }
}

class _DnsPanelSwitcher extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _DnsPanelSwitcher({
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const tabs = ['DNS', 'Blocked'];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final selected = selectedIndex == index;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(7),
              onTap: () => onSelected(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  tabs[index],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DnsPanelDots extends StatelessWidget {
  final int count;
  final int currentIndex;

  const _DnsPanelDots({required this.count, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: index == currentIndex ? 16 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: index == currentIndex
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _DnsEntryCard extends StatelessWidget {
  final OpenwrtDnsHostEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DnsEntryCard({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Row(
        children: [
          Icon(
            entry.isBlockedSinkhole ? Icons.block_rounded : Icons.dns_rounded,
            color: entry.isBlockedSinkhole
                ? colorScheme.error
                : colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.hostname.isEmpty ? 'Unnamed host' : entry.hostname,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  entry.ipAddress.isEmpty ? 'No IP address' : entry.ipAddress,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

class _DnsEmptyCard extends StatelessWidget {
  final String message;
  final Future<void> Function() onRefresh;

  const _DnsEmptyCard({required this.message, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

class _DnsEntrySheet extends ConsumerStatefulWidget {
  final OpenwrtDnsHostEntry? entry;

  const _DnsEntrySheet({this.entry});

  @override
  ConsumerState<_DnsEntrySheet> createState() => _DnsEntrySheetState();
}

class _DnsEntrySheetState extends ConsumerState<_DnsEntrySheet> {
  late final TextEditingController _hostnameController;
  late final TextEditingController _ipController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _hostnameController = TextEditingController(
      text: widget.entry?.hostname ?? '',
    );
    _ipController = TextEditingController(text: widget.entry?.ipAddress ?? '');
  }

  @override
  void dispose() {
    _hostnameController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final hostname = _hostnameController.text.trim();
    final ip = _ipController.text.trim();
    if (hostname.isEmpty || ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hostname and IP address are required.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .saveDnsHostEntry(
            OpenwrtDnsHostEntry(
              section: widget.entry?.section ?? '',
              hostname: hostname,
              ipAddress: ip,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save entry: $e')));
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.entry == null || widget.entry!.section.trim().isEmpty;
    final isBlockedEntry = widget.entry?.isBlockedSinkhole ?? false;
    final title = isBlockedEntry
        ? (isNew ? 'Block Domain' : 'Edit Blocked Domain')
        : (isNew ? 'Add DNS Entry' : 'Edit DNS Entry');

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _hostnameController,
            enabled: !_isSaving,
            decoration: InputDecoration(
              labelText: isBlockedEntry ? 'Domain' : 'Hostname',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ipController,
            enabled: !_isSaving,
            decoration: const InputDecoration(labelText: 'IP address'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_isSaving ? 'Saving' : 'Save'),
          ),
        ],
      ),
    );
  }
}
