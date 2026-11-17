import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/office_model.dart';
import '../../providers/office_provider.dart';
import '../widgets/initials_avatar.dart';
import '../widgets/state_views.dart';

/// Searchable bottom sheet for choosing a faculty office. Returns the chosen
/// office, or null when dismissed.
Future<Office?> showOfficePicker(BuildContext context, {String? selectedId}) {
  return showModalBottomSheet<Office>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _OfficePickerSheet(selectedId: selectedId),
  );
}

class _OfficePickerSheet extends ConsumerStatefulWidget {
  const _OfficePickerSheet({this.selectedId});
  final String? selectedId;

  @override
  ConsumerState<_OfficePickerSheet> createState() => _OfficePickerSheetState();
}

class _OfficePickerSheetState extends ConsumerState<_OfficePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final offices = ref.watch(officesProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select faculty office', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search office or building',
                  ),
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncValueView(
              value: offices,
              onRetry: () => ref.invalidate(officesProvider),
              data: (list) {
                final filtered = list
                    .where((o) =>
                        _query.isEmpty ||
                        o.officeName.toLowerCase().contains(_query) ||
                        o.building.toLowerCase().contains(_query))
                    .toList();
                if (filtered.isEmpty) {
                  return const EmptyState(
                    icon: Icons.apartment,
                    title: 'No offices found',
                    message: 'Add faculty offices from the Offices tab.',
                    compact: true,
                  );
                }
                return ListView.builder(
                  controller: controller,
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final o = filtered[i];
                    final selected = o.officeId == widget.selectedId;
                    return ListTile(
                      leading: InitialsAvatar(name: o.officeName, size: 40),
                      title: Text(o.officeName),
                      subtitle: Text(o.building.isEmpty ? 'No building set' : o.building),
                      trailing: selected
                          ? const Icon(Icons.check_circle, color: AppColors.forestGreen)
                          : null,
                      onTap: () => Navigator.of(context).pop(o),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
