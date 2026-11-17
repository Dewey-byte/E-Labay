import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'routes/app_router.dart';

class ELabayApp extends ConsumerWidget {
  const ELabayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Accounts without a valid profile/role (or deactivated ones) are signed
    // out immediately; the login screen explains why.
    ref.listen(sessionProvider, (previous, next) {
      if (next is SessionInvalid) {
        ref.read(authNoticeProvider.notifier).show(next.message);
        ref.read(sessionControllerProvider).signOut();
      }
    });

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
