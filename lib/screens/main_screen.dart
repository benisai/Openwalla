import 'package:flutter/material.dart';
import 'package:openwalla/screens/dashboard_screen.dart';
import 'package:openwalla/screens/more_screen.dart';
import 'package:openwalla/screens/statistics_screen.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/widgets/luci_navigation_enhancements.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MainScreen extends ConsumerStatefulWidget {
  final int? initialTab;

  const MainScreen({super.key, this.initialTab});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialTab != null) {
      _selectedIndex = widget.initialTab!.clamp(0, 2);
    }
  }

  @override
  void didUpdateWidget(MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle initial tab changes
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
      _selectedIndex = widget.initialTab!.clamp(0, 2);
    }
  }

  List<Widget> _widgetOptions(bool showStatistics) => [
    const DashboardScreen(),
    if (showStatistics) const StatisticsScreen(),
    const MoreScreen(),
  ];

  List<NavigationDestination> _destinations({required bool showStatistics}) => [
    const NavigationDestination(
      selectedIcon: Icon(Icons.dashboard),
      icon: Icon(Icons.dashboard_outlined),
      label: 'Dashboard',
    ),
    if (showStatistics)
      const NavigationDestination(
        selectedIcon: Icon(Icons.query_stats_rounded),
        icon: Icon(Icons.query_stats_outlined),
        label: 'Statistics',
      ),
    const NavigationDestination(
      selectedIcon: Icon(Icons.more_horiz),
      icon: Icon(Icons.more_horiz_outlined),
      label: 'More',
    ),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen for requestedTab in AppState
    final appState = ref.watch(appStateProvider);
    if (appState.requestedTab != null &&
        appState.requestedTab != _selectedIndex) {
      // Store the values before the callback to avoid null reference issues
      final requestedTab = appState.requestedTab!;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _selectedIndex = requestedTab.clamp(0, 2);
        });
        appState.requestedTab = null;
        appState.requestedInterfaceToScroll = null;
      });
    }
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (context) {
            final showStatistics =
                appState.dashboardPreferences.showStatisticsTab;
            final pages = _widgetOptions(showStatistics);
            if (_selectedIndex >= pages.length) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _selectedIndex = pages.length - 1);
              });
            }
            final safeIndex = _selectedIndex.clamp(0, pages.length - 1);
            return LuciTabTransition(
              transitionKey: 'tab_$safeIndex',
              child: pages.elementAt(safeIndex),
            );
          },
        ),
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final showStatistics =
              appState.dashboardPreferences.showStatisticsTab;
          final destinations = _destinations(showStatistics: showStatistics);
          final safeIndex = _selectedIndex.clamp(0, destinations.length - 1);
          return NavigationBar(
            onDestinationSelected: (index) {
              _onItemTapped(index);
            },
            selectedIndex: safeIndex,
            destinations: destinations,
          );
        },
      ),
    );
  }
}
