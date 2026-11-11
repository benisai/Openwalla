import 'package:flutter/material.dart';
import 'package:openwalla/models/quarantine_notice_state.dart';

class DashboardQuarantineBanner extends StatefulWidget {
  const DashboardQuarantineBanner({
    super.key,
    required this.routerKey,
    required this.quarantinedMacs,
    required this.onView,
    this.statusKnown = true,
    this.noticeState,
  });

  final String routerKey;
  final Set<String> quarantinedMacs;
  final VoidCallback onView;
  final bool statusKnown;
  final QuarantineNoticeState? noticeState;

  @override
  State<DashboardQuarantineBanner> createState() =>
      _DashboardQuarantineBannerState();
}

class _DashboardQuarantineBannerState extends State<DashboardQuarantineBanner> {
  final _localNoticeState = QuarantineNoticeState();
  QuarantineNoticeState get _notices => widget.noticeState ?? _localNoticeState;

  @override
  void initState() {
    super.initState();
    if (widget.statusKnown) {
      _notices.reconcile(widget.routerKey, widget.quarantinedMacs);
    }
  }

  @override
  void didUpdateWidget(covariant DashboardQuarantineBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.statusKnown) {
      _notices.reconcile(widget.routerKey, widget.quarantinedMacs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unseen = _notices.unseen(widget.routerKey, widget.quarantinedMacs);
    if (!widget.statusKnown || unseen.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final count = unseen.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Semantics(
        liveRegion: true,
        child: Material(
          color: colors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: const Color(0xFFEAB308).withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_rounded,
                      color: Color(0xFFEAB308),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'New Device Quarantine',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '$count ${count == 1 ? 'device has' : 'devices have'} been quarantined on your network.',
                ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _notices.dismiss(
                          widget.routerKey,
                          widget.quarantinedMacs,
                        );
                      }),
                      child: const Text('Dismiss'),
                    ),
                    TextButton(
                      onPressed: widget.onView,
                      child: const Text('View Quarantined Devices'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
