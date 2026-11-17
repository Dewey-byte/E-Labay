import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/exceptions/app_exception.dart';
import '../../core/theme/app_colors.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsets.all(compact ? 16 : 32),
          child: SizedBox(
            width: compact ? 22 : 32,
            height: compact ? 22 : 32,
            child: const CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32, vertical: compact ? 20 : 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(compact ? 12 : 18),
              decoration: const BoxDecoration(
                color: AppColors.mintSurface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: compact ? 24 : 36, color: AppColors.forestGreen),
            ),
            SizedBox(height: compact ? 10 : 16),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry, this.compact = false});

  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Unable to load',
        message: message,
        compact: compact,
        action: onRetry == null
            ? null
            : OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(140, 44)),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
      );
}

/// Renders an [AsyncValue] with consistent loading and error states. Keeps
/// showing previous data while a provider reloads.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.compact = false,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) => value.when(
        skipLoadingOnReload: true,
        data: data,
        loading: () => LoadingView(compact: compact),
        error: (e, _) => ErrorState(
          message: AppException.messageOf(e),
          onRetry: onRetry,
          compact: compact,
        ),
      );
}
