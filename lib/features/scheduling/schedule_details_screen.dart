import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/enums.dart';
import '../../models/schedule_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/schedule_provider.dart';
import '../../repositories/schedule_repository.dart';
import '../../routes/app_routes.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/info_row.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_chip.dart';

/// Collection details for both roles. Collectors get management actions
/// (start/assess, edit, reschedule, cancel); Faculty Offices view only.
class ScheduleDetailsScreen extends ConsumerWidget {
  const ScheduleDetailsScreen({super.key, required this.scheduleId});

  final String scheduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(scheduleProvider(scheduleId));
    final isCollector = ref.watch(currentUserProvider)?.isCollector ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collection details'),
        actions: [
          if (isCollector && (schedule.value?.status.isPending ?? false))
            _CollectorMenu(schedule: schedule.value!),
        ],
      ),
      body: AsyncValueView(
        value: schedule,
        onRetry: () => ref.invalidate(scheduleProvider(scheduleId)),
        data: (s) => s == null
            ? const EmptyState(
                icon: Icons.event_busy,
                title: 'Schedule not found',
                message: 'It may have been removed or you may not have access to it.',
              )
            : _Body(schedule: s, isCollector: isCollector),
      ),
      bottomNavigationBar: isCollector && schedule.value != null && schedule.value!.canBeAssessed
          ? _AssessBar(schedule: schedule.value!)
          : null,
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.schedule, required this.isCollector});

  final Schedule schedule;
  final bool isCollector;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = schedule;
    final color = s.isOverdue ? AppColors.danger : s.status.color;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        AppCard(
          color: AppColors.tint(color, 0.06),
          borderColor: AppColors.tint(color, 0.3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusChip(status: s.status, overdue: s.isOverdue),
              const SizedBox(height: 12),
              Text(Fmt.dayLabel(s.collectionDate), style: theme.textTheme.headlineSmall),
              Text(
                '${Fmt.date(s.collectionDate)} · ${Fmt.time(s.collectionDate)}',
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
              if (s.status == ScheduleStatus.rescheduled && s.previousCollectionDate != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Moved from ${Fmt.dateTime(s.previousCollectionDate!)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.rescheduled),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            children: [
              InfoRow(icon: Icons.apartment, label: 'Faculty office', value: s.officeName),
              if (s.building.isNotEmpty)
                InfoRow(icon: Icons.location_on_outlined, label: 'Building', value: s.building),
              InfoRow(
                icon: Icons.person_outline,
                label: 'Scheduled by',
                value: s.collectorName.isEmpty ? 'Collector' : s.collectorName,
              ),
              InfoRow(
                icon: Icons.sticky_note_2_outlined,
                label: "Collector's instructions",
                value: s.notes.isEmpty ? 'No instructions' : s.notes,
              ),
              if (s.statusNote != null)
                InfoRow(
                  icon: s.status == ScheduleStatus.cancelled ? Icons.cancel_outlined : Icons.update,
                  label: s.status == ScheduleStatus.cancelled ? 'Cancellation reason' : 'Reason for change',
                  value: s.statusNote!,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Schedule updates', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (s.createdAt != null)
                _TimelineItem(icon: Icons.add_circle_outline, text: 'Created', date: s.createdAt!),
              if (s.updatedAt != null &&
                  s.createdAt != null &&
                  s.updatedAt!.difference(s.createdAt!).inSeconds > 5)
                _TimelineItem(icon: Icons.edit_outlined, text: 'Last updated', date: s.updatedAt!),
              if (s.completedAt != null)
                _TimelineItem(icon: Icons.task_alt, text: 'Collection completed', date: s.completedAt!),
            ],
          ),
        ),
        if (s.status == ScheduleStatus.completed && s.collectionId != null) ...[
          const SizedBox(height: 12),
          AppCard(
            onTap: () => context.push(
              isCollector
                  ? AppRoutes.collectorCollection(s.collectionId!)
                  : AppRoutes.facultyCollection(s.collectionId!),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.tint(AppColors.gold),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.emoji_events_outlined, color: AppColors.gold),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Assessment result', style: theme.textTheme.titleSmall),
                      Text(
                        '${s.pointsAwarded ?? 0} points awarded · view details',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.icon, required this.text, required this.date});

  final IconData icon;
  final String text;
  final DateTime date;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
            Text(Fmt.dateTime(date), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

/// Bottom action: start the collection and open the assessment.
class _AssessBar extends ConsumerStatefulWidget {
  const _AssessBar({required this.schedule});

  final Schedule schedule;

  @override
  ConsumerState<_AssessBar> createState() => _AssessBarState();
}

class _AssessBarState extends ConsumerState<_AssessBar> {
  bool _busy = false;

  Future<void> _start() async {
    final s = widget.schedule;
    if (s.status != ScheduleStatus.inProgress) {
      setState(() => _busy = true);
      try {
        await ref.read(scheduleRepositoryProvider).markInProgress(s.scheduleId);
      } catch (e) {
        if (mounted) showErrorSnack(context, e);
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) context.push(AppRoutes.collectorAssess(s.scheduleId));
  }

  @override
  Widget build(BuildContext context) {
    final inProgress = widget.schedule.status == ScheduleStatus.inProgress;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: _busy ? null : _start,
          icon: Icon(inProgress ? Icons.fact_check_outlined : Icons.local_shipping_outlined),
          label: Text(inProgress ? 'Continue assessment' : 'Start collection & assess'),
        ),
      ),
    );
  }
}

enum _MenuAction { edit, reschedule, cancel }

class _CollectorMenu extends ConsumerWidget {
  const _CollectorMenu({required this.schedule});

  final Schedule schedule;

  Future<void> _reschedule(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: schedule.collectionDate.isBefore(today) ? today : schedule.collectionDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'New collection date',
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(schedule.collectionDate),
      helpText: 'New collection time',
    );
    if (time == null || !context.mounted) return;
    final when = Fmt.combine(date, time);
    if (when.isBefore(DateTime.now())) {
      showErrorSnack(context, 'The new collection time must be in the future.');
      return;
    }
    final reason = await showTextInputDialog(
      context,
      title: 'Reschedule to ${Fmt.dateTime(when)}',
      label: 'Reason',
      message: '${schedule.officeName} will be notified.',
      confirmLabel: 'Reschedule',
    );
    if (reason == null || !context.mounted) return;
    try {
      await ref.read(scheduleRepositoryProvider).reschedule(
            schedule,
            collectionDate: when,
            collectionTime: Fmt.timeOfDayToStorage(time),
            reason: reason,
          );
      if (context.mounted) showSuccessSnack(context, 'Collection rescheduled');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final reason = await showTextInputDialog(
      context,
      title: 'Cancel this collection?',
      label: 'Reason',
      message: '${schedule.officeName} will be notified. This cannot be undone.',
      confirmLabel: 'Cancel collection',
      destructive: true,
    );
    if (reason == null || !context.mounted) return;
    try {
      await ref.read(scheduleRepositoryProvider).cancel(schedule.scheduleId, reason: reason);
      if (context.mounted) showSuccessSnack(context, 'Collection cancelled');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_MenuAction>(
      onSelected: (action) {
        switch (action) {
          case _MenuAction.edit:
            context.push(AppRoutes.collectorEditSchedule(schedule.scheduleId));
          case _MenuAction.reschedule:
            _reschedule(context, ref);
          case _MenuAction.cancel:
            _cancel(context, ref);
        }
      },
      itemBuilder: (_) => [
        if (schedule.canBeModified) ...const [
          PopupMenuItem(
            value: _MenuAction.edit,
            child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit schedule')),
          ),
          PopupMenuItem(
            value: _MenuAction.reschedule,
            child: ListTile(leading: Icon(Icons.update), title: Text('Reschedule')),
          ),
        ],
        const PopupMenuItem(
          value: _MenuAction.cancel,
          child: ListTile(
            leading: Icon(Icons.cancel_outlined, color: AppColors.danger),
            title: Text('Cancel collection', style: TextStyle(color: AppColors.danger)),
          ),
        ),
      ],
    );
  }
}
