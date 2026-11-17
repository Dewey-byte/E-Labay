import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/exceptions/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/office_model.dart';
import '../../models/schedule_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/office_provider.dart';
import '../../providers/schedule_provider.dart';
import '../../repositories/schedule_repository.dart';
import '../../routes/app_routes.dart';
import '../../shared/components/office_picker_sheet.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/initials_avatar.dart';
import '../../shared/widgets/state_views.dart';

/// Collector: manually create a collection schedule, or edit a pending one.
/// Schedules are never generated automatically.
class ScheduleFormScreen extends ConsumerWidget {
  const ScheduleFormScreen({super.key, this.scheduleId, this.initialOfficeId});

  final String? scheduleId;
  final String? initialOfficeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (scheduleId == null) {
      if (initialOfficeId == null) return const _ScheduleForm();
      final office = ref.watch(officeProvider(initialOfficeId!));
      return office.when(
        skipLoadingOnReload: true,
        loading: () => const Scaffold(body: LoadingView()),
        error: (_, _) => const _ScheduleForm(),
        data: (o) => _ScheduleForm(initialOffice: o),
      );
    }
    final schedule = ref.watch(scheduleProvider(scheduleId!));
    return schedule.when(
      skipLoadingOnReload: true,
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorState(message: AppException.messageOf(e))),
      data: (s) {
        if (s == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.event_busy, title: 'Schedule not found'),
          );
        }
        if (!s.canBeModified) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(
              icon: Icons.lock_outline,
              title: 'This schedule can no longer be edited',
              message: 'Status: ${s.status.label}',
            ),
          );
        }
        return _ScheduleForm(existing: s);
      },
    );
  }
}

class _ScheduleForm extends ConsumerStatefulWidget {
  const _ScheduleForm({this.existing, this.initialOffice});

  final Schedule? existing;
  final Office? initialOffice;

  @override
  ConsumerState<_ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends ConsumerState<_ScheduleForm> {
  late Office? _office = widget.initialOffice;
  late DateTime? _date = widget.existing?.collectionDate;
  late TimeOfDay? _time =
      widget.existing == null ? null : TimeOfDay.fromDateTime(widget.existing!.collectionDate);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  bool _saving = false;
  bool _showErrors = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickOffice() async {
    final office = await showOfficePicker(context, selectedId: _office?.officeId);
    if (office != null) setState(() => _office = office);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _date ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(today) ? today : initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Collection date',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Collection time',
    );
    if (picked != null) setState(() => _time = picked);
  }

  String? get _validationError {
    if (!_isEdit && _office == null) return 'Select a faculty office.';
    if (_date == null) return 'Select a collection date.';
    if (_time == null) return 'Select a collection time.';
    final when = Fmt.combine(_date!, _time!);
    final unchanged = _isEdit && when.isAtSameMomentAs(widget.existing!.collectionDate);
    if (!unchanged && when.isBefore(DateTime.now())) {
      return 'The collection time must be in the future.';
    }
    return null;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _showErrors = true);
    final error = _validationError;
    if (error != null) {
      showErrorSnack(context, error);
      return;
    }
    final collector = ref.read(currentUserProvider);
    if (collector == null) return;
    final when = Fmt.combine(_date!, _time!);
    final time = Fmt.timeOfDayToStorage(_time!);
    final repo = ref.read(scheduleRepositoryProvider);

    if (_isEdit && !when.isAtSameMomentAs(widget.existing!.collectionDate)) {
      final ok = await showConfirmDialog(
        context,
        title: 'Reschedule collection?',
        message: 'Changing the date or time marks this collection as Rescheduled and '
            'notifies ${widget.existing!.officeName}.',
        confirmLabel: 'Reschedule',
      );
      if (!ok || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await repo.updateSchedule(
          widget.existing!,
          collectionDate: when,
          collectionTime: time,
          notes: _notes.text,
        );
        if (!mounted) return;
        showSuccessSnack(context, 'Schedule updated');
        context.pop();
      } else {
        final id = await repo.createSchedule(
          office: _office!,
          collector: collector,
          collectionDate: when,
          collectionTime: time,
          notes: _notes.text,
        );
        if (!mounted) return;
        showSuccessSnack(context, 'Schedule created · ${_office!.officeName} has been notified');
        context.pushReplacement(AppRoutes.collectorSchedule(id));
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final officeName = _isEdit ? widget.existing!.officeName : _office?.officeName;
    final building = _isEdit ? widget.existing!.building : _office?.building;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit schedule' : 'New collection schedule')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _FieldLabel('Faculty office'),
          AppCard(
            onTap: _isEdit ? null : _pickOffice,
            borderColor: _showErrors && officeName == null ? AppColors.danger : null,
            child: Row(
              children: [
                officeName == null
                    ? const InitialsAvatar(name: '', icon: Icons.apartment, size: 44)
                    : InitialsAvatar(name: officeName, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(officeName ?? 'Select an office', style: theme.textTheme.titleSmall),
                      if (building != null && building.isNotEmpty)
                        Text(building, style: theme.textTheme.bodySmall),
                      if (_isEdit)
                        Text(
                          'To change the office, cancel this schedule and create a new one.',
                          style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
                        ),
                    ],
                  ),
                ),
                if (!_isEdit) const Icon(Icons.unfold_more, color: AppColors.textMuted),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel('Date'),
                    _PickerTile(
                      icon: Icons.calendar_today,
                      value: _date == null ? 'Select date' : Fmt.shortDate(_date!),
                      error: _showErrors && _date == null,
                      onTap: _pickDate,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel('Time'),
                    _PickerTile(
                      icon: Icons.schedule,
                      value: _time == null ? 'Select time' : _time!.format(context),
                      error: _showErrors && _time == null,
                      onTap: _pickTime,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _FieldLabel('Instructions or remarks (optional)'),
          TextField(
            controller: _notes,
            maxLines: 4,
            minLines: 3,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Please place segregated bins outside the office door.',
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.mintSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_outlined, color: AppColors.forestGreen, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isEdit
                        ? 'The office will be notified of the changes.'
                        : 'The office is notified as soon as you save, and reminded within 24 hours of the collection.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(_isEdit ? 'Save changes' : 'Save schedule'),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({required this.icon, required this.value, required this.onTap, this.error = false});

  final IconData icon;
  final String value;
  final VoidCallback onTap;
  final bool error;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        borderColor: error ? AppColors.danger : null,
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.forestGreen),
            const SizedBox(width: 10),
            Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
}
