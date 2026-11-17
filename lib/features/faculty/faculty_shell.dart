import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/push_notification_service.dart';
import '../../models/enums.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../repositories/notification_repository.dart';
import '../../routes/app_routes.dart';
import '../notifications/notification_navigation.dart';

/// Bottom navigation for Faculty Office users. Shows an in-app banner for
/// each new notification (live Firestore feed, works on the Spark plan) and,
/// when the optional Blaze push functions are deployed, registers for FCM and
/// opens the related record when a push notification is tapped.
class FacultyShell extends ConsumerStatefulWidget {
  const FacultyShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<FacultyShell> createState() => _FacultyShellState();
}

class _FacultyShellState extends ConsumerState<FacultyShell> {
  final _subs = <StreamSubscription<dynamic>>[];
  final _seen = <String>{};
  bool _feedPrimed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _watchNewNotifications();
      _initPush();
    });
  }

  /// Banners only for notifications that arrive after the app opened.
  void _watchNewNotifications() {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    _subs.add(
      ref.read(notificationRepositoryProvider).watchNotifications(user.uid, limit: 5).listen((items) {
        final fresh = items.where((n) => !_seen.contains(n.notificationId)).toList();
        _seen.addAll(items.map((n) => n.notificationId));
        if (!_feedPrimed) {
          _feedPrimed = true;
          return;
        }
        final newest = fresh.where((n) => !n.isRead).firstOrNull;
        if (newest != null) {
          _showBanner(newest.title, newest.message, {
            'notificationId': newest.notificationId,
            'type': newest.type.value,
            'relatedId': newest.relatedId,
          });
        }
      }, onError: (_) {}),
    );
  }

  Future<void> _initPush() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final push = ref.read(pushNotificationServiceProvider);
    _subs.add(push.onNotificationTap.listen(_openFromPush));
    final initial = await push.register(user.uid);
    if (initial != null && mounted) _openFromPush(initial);
  }

  void _openFromPush(Map<String, dynamic> data) {
    if (!mounted) return;
    final notificationId = data['notificationId'] as String?;
    if (notificationId != null) {
      ref.read(notificationRepositoryProvider).markAsRead(notificationId).ignore();
    }
    final opened = openNotificationTarget(
      context,
      NotificationType.parse(data['type'] as String?),
      data['relatedId'] as String?,
    );
    if (!opened) context.go(AppRoutes.facultyNotifications);
  }

  void _showBanner(String title, String? body, Map<String, dynamic> data) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (body != null) Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
          action: SnackBarAction(label: 'View', onPressed: () => _openFromPush(data)),
        ),
      );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadNotificationCountProvider).value ?? 0;
    final shell = widget.navigationShell;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Schedule',
          ),
          const NavigationDestination(
            icon: Icon(Icons.leaderboard_outlined),
            selectedIcon: Icon(Icons.leaderboard),
            label: 'Leaderboard',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.notifications),
            ),
            label: 'Alerts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
