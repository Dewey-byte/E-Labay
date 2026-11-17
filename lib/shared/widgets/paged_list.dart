import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/exceptions/app_exception.dart';
import 'state_views.dart';

/// A scrolling list backed by a live (real-time) Firestore query whose limit
/// grows as the user scrolls — real-time updates plus pagination.
///
/// Give it a new `key` whenever its filters change so paging restarts.
class PagedList<T> extends ConsumerStatefulWidget {
  const PagedList({
    super.key,
    required this.watch,
    required this.itemBuilder,
    required this.empty,
    this.header = const [],
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 96),
    this.pageSize = AppConstants.pageSize,
    this.spacing = 10,
    this.onRetry,
  });

  /// Watches the provider for the given limit, e.g.
  /// `(ref, limit) => ref.watch(myProvider(query.copyWith(limit: limit)))`.
  final AsyncValue<List<T>> Function(WidgetRef ref, int limit) watch;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Widget empty;
  final List<Widget> header;
  final EdgeInsets padding;
  final int pageSize;
  final double spacing;

  /// Invalidate the underlying provider(s) to retry after an error.
  final VoidCallback? onRetry;

  @override
  ConsumerState<PagedList<T>> createState() => _PagedListState<T>();
}

class _PagedListState<T> extends ConsumerState<PagedList<T>> {
  late int _limit = widget.pageSize;
  List<T>? _lastItems;

  @override
  Widget build(BuildContext context) {
    final async = widget.watch(ref, _limit);
    if (async.hasValue) _lastItems = async.value;
    final items = async.value ?? _lastItems;

    if (items == null) {
      return CustomScrollView(
        slivers: [
          ...widget.header,
          SliverFillRemaining(
            hasScrollBody: false,
            child: async.hasError
                ? ErrorState(
                    message: AppException.messageOf(async.error!),
                    onRetry: widget.onRetry,
                  )
                : const LoadingView(),
          ),
        ],
      );
    }

    final hasMore = items.length >= _limit;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (hasMore && !async.isLoading && n.metrics.extentAfter < 400) {
          setState(() => _limit += widget.pageSize);
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          ...widget.header,
          if (items.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: widget.empty)
          else
            SliverPadding(
              padding: widget.padding.copyWith(bottom: hasMore ? 8 : widget.padding.bottom),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => SizedBox(height: widget.spacing),
                itemBuilder: (context, i) => widget.itemBuilder(context, items[i]),
              ),
            ),
          if (items.isNotEmpty && hasMore)
            SliverPadding(
              padding: EdgeInsets.only(bottom: widget.padding.bottom),
              sliver: const SliverToBoxAdapter(child: LoadingView(compact: true)),
            ),
        ],
      ),
    );
  }
}
