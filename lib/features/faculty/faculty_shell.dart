import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
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

/// Bottom navigation for Faculty Office users. Also registers the device for
/// push notifications and handles notification taps.
class FacultyShell extends ConsumerStatefulWidget {
  const FacultyShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<FacultyShell> createState() => _FacultyShellState();
}

class _FacultyShellState extends ConsumerState<FacultyShell> {
  final _subs = <StreamSubscription<dynamic>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initPush());
  }

  Future<void> _initPush() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final push = ref.read(pushNotificationServiceProvider);
    _subs
      ..add(push.onNotificationTap.listen(_openFromPush))
      ..add(push.onForegroundMessage.listen(_showForegroundBanner));
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

  void _showForegroundBanner(RemoteMessage message) {
    if (!mounted) return;
    final title = message.notification?.title ?? 'New notification';
    final body = message.notification?.body;
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
          action: SnackBarAction(label: 'View', onPressed: () => _openFromPush(message.data)),
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
