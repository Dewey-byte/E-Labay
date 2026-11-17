import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../repositories/schedule_repository.dart';

/// Bottom navigation for the Collector role. On open it sends any due
/// collection reminders (pickups within 24 hours), since the Spark plan has
/// no scheduled server jobs.
class CollectorShell extends ConsumerStatefulWidget {
  const CollectorShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<CollectorShell> createState() => _CollectorShellState();
}

class _CollectorShellState extends ConsumerState<CollectorShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(scheduleRepositoryProvider).sendDueReminders().then(
        (sent) => debugPrint('Collection reminders sent: $sent'),
        onError: (Object e) => debugPrint('Reminder check failed: $e'),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) =>
            navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Schedules',
          ),
          NavigationDestination(
            icon: Icon(Icons.apartment_outlined),
            selectedIcon: Icon(Icons.apartment),
            label: 'Offices',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
