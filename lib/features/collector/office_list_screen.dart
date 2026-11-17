import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/office_model.dart';
import '../../providers/office_provider.dart';
import '../../routes/app_routes.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/initials_avatar.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_chip.dart';

enum _OfficeSort {
  name('Name (A–Z)'),
  points('Most points'),
  rate('Best segregation');

  const _OfficeSort(this.label);
  final String label;
}

/// Collector: all registered faculty offices with search and filters.
class OfficeListScreen extends ConsumerStatefulWidget {
  const OfficeListScreen({super.key});

  @override
  ConsumerState<OfficeListScreen> createState() => _OfficeListScreenState();
}

class _OfficeListScreenState extends ConsumerState<OfficeListScreen> {
  String _query = '';
  String? _building;
  _OfficeSort _sort = _OfficeSort.name;

  List<Office> _apply(List<Office> offices) {
    final q = _query.toLowerCase();
    final filtered = offices.where((o) {
      final matchesQuery = q.isEmpty ||
          o.officeName.toLowerCase().contains(q) ||
          o.building.toLowerCase().contains(q);
      final matchesBuilding = _building == null || o.building == _building;
      return matchesQuery && matchesBuilding;
    }).toList();
    switch (_sort) {
      case _OfficeSort.name:
        break; // already alphabetical from Firestore
      case _OfficeSort.points:
        filtered.sort((a, b) => b.totalPoints.compareTo(a.totalPoints));
      case _OfficeSort.rate:
        filtered.sort((a, b) =>
            (b.properSegregationRate ?? -1).compareTo(a.properSegregationRate ?? -1));
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final offices = ref.watch(officesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Faculty offices')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'offices-add',
        onPressed: () => context.push(AppRoutes.collectorNewOffice),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Add office'),
      ),
      body: AsyncValueView(
        value: offices,
        onRetry: () => ref.invalidate(officesProvider),
        data: (all) {
          final buildings = all.map((o) => o.building).where((b) => b.isNotEmpty).toSet().toList()
            ..sort();
          final list = _apply(all);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search office or building',
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    PopupMenuButton<_OfficeSort>(
                      initialValue: _sort,
                      onSelected: (v) => setState(() => _sort = v),
                      itemBuilder: (_) => [
                        for (final s in _OfficeSort.values) PopupMenuItem(value: s, child: Text(s.label)),
                      ],
                      child: Chip(
                        avatar: const Icon(Icons.sort, size: 18),
                        label: Text(_sort.label),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('All buildings'),
                      selected: _building == null,
                      onSelected: (_) => setState(() => _building = null),
                    ),
                    for (final b in buildings) ...[
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(b),
                        selected: _building == b,
                        onSelected: (sel) => setState(() => _building = sel ? b : null),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(
                        icon: Icons.apartment,
                        title: all.isEmpty ? 'No offices registered' : 'No matching offices',
                        message: all.isEmpty
                            ? 'Add the participating faculty offices and their login accounts.'
                            : 'Try a different search or filter.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _OfficeTile(
                          office: list[i],
                          onTap: () => context.push(AppRoutes.collectorOffice(list[i].officeId)),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OfficeTile extends StatelessWidget {
  const _OfficeTile({required this.office, required this.onTap});

  final Office office;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          InitialsAvatar(name: office.officeName, size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(office.officeName, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  office.building.isEmpty ? 'No building set' : office.building,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    RateChip(rate: office.properSegregationRate),
                    TagChip(
                      label: '${office.totalCollections} collected',
                      color: AppColors.info,
                      icon: Icons.task_alt,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text(Fmt.number(office.totalPoints),
                  style: theme.textTheme.titleLarge?.copyWith(color: AppColors.forestGreen)),
              Text('points', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}
