import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/exceptions/app_exception.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/feature_flags.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/scoring.dart';
import '../../models/enums.dart';
import '../../models/schedule_model.dart';
import '../../models/scoring_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/points_provider.dart';
import '../../providers/schedule_provider.dart';
import '../../repositories/collection_repository.dart';
import '../../routes/app_routes.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_chip.dart';

/// Collector: waste segregation assessment for a scheduled collection.
class AssessmentScreen extends ConsumerStatefulWidget {
  const AssessmentScreen({super.key, required this.scheduleId});

  final String scheduleId;

  @override
  ConsumerState<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends ConsumerState<AssessmentScreen> {
  /// Once the form is open it stays open, even when the schedule flips to
  /// `completed` right after submission (the screen is then replaced).
  Schedule? _formSchedule;

  @override
  Widget build(BuildContext context) {
    if (_formSchedule != null) return _AssessmentForm(schedule: _formSchedule!);
    final schedule = ref.watch(scheduleProvider(widget.scheduleId));
    return schedule.when(
      skipLoadingOnReload: true,
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(message: AppException.messageOf(e)),
      ),
      data: (s) {
        if (s == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.event_busy, title: 'Schedule not found'),
          );
        }
        if (!s.canBeAssessed) {
          return Scaffold(
            appBar: AppBar(title: const Text('Assessment')),
            body: EmptyState(
              icon: s.status == ScheduleStatus.completed ? Icons.task_alt : Icons.block,
              title: s.status == ScheduleStatus.completed
                  ? 'This collection has already been assessed'
                  : 'This collection was cancelled',
              action: s.collectionId == null
                  ? null
                  : FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
                      onPressed: () =>
                          context.pushReplacement(AppRoutes.collectorCollection(s.collectionId!)),
                      child: const Text('View assessment'),
                    ),
            ),
          );
        }
        _formSchedule = s;
        return _AssessmentForm(schedule: s);
      },
    );
  }
}

class _AssessmentForm extends ConsumerStatefulWidget {
  const _AssessmentForm({required this.schedule});

  final Schedule schedule;

  @override
  ConsumerState<_AssessmentForm> createState() => _AssessmentFormState();
}

class _AssessmentFormState extends ConsumerState<_AssessmentForm> {
  final _results = <WasteCategory, SegregationResult>{};
  final _remarks = TextEditingController();
  final _photos = <XFile>[];
  final _picker = ImagePicker();
  bool _submitting = false;
  String _progressLabel = '';
  bool _showErrors = false;

  bool get _complete => _results.length == WasteCategory.values.length;

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= AppConstants.maxEvidencePhotos) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final file = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 70);
      if (file != null) setState(() => _photos.add(file));
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Could not open the ${source.name}: $e');
    }
  }

  Future<void> _review(ScoringConfig config) async {
    FocusScope.of(context).unfocus();
    setState(() => _showErrors = true);
    if (!_complete) {
      showErrorSnack(context, 'Assess all ${WasteCategory.values.length} waste categories first.');
      return;
    }
    final score = calculateScore(_results, config);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ReviewSheet(
        schedule: widget.schedule,
        results: _results,
        score: score,
        remarks: _remarks.text.trim(),
        photoCount: _photos.length,
      ),
    );
    if (confirmed == true) await _submit();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _progressLabel = _photos.isEmpty ? 'Submitting assessment…' : 'Uploading photos…';
    });
    final repo = ref.read(collectionRepositoryProvider);
    try {
      var urls = <String>[];
      if (_photos.isNotEmpty) {
        urls = await repo.uploadEvidence(
          officeId: widget.schedule.officeId,
          scheduleId: widget.schedule.scheduleId,
          photos: _photos,
        );
        if (mounted) setState(() => _progressLabel = 'Submitting assessment…');
      }
      final collector = ref.read(currentUserProvider);
      if (collector == null) return;
      await repo.submitAssessment(
        scheduleId: widget.schedule.scheduleId,
        collector: collector,
        results: Map.of(_results),
        remarks: _remarks.text,
        evidenceImageUrls: urls,
      );
      if (!mounted) return;
      context.pushReplacement(AppRoutes.collectorSubmitted(widget.schedule.scheduleId));
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        showErrorSnack(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(scoringConfigProvider).value ?? ScoringConfig.defaults;
    final score = calculateScore(_results, config);
    final theme = Theme.of(context);
    final s = widget.schedule;

    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        appBar: AppBar(title: const Text('Waste segregation assessment')),
        body: AbsorbPointer(
          absorbing: _submitting,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              AppCard(
                child: Row(
                  children: [
                    const Icon(Icons.apartment, color: AppColors.forestGreen),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.officeName, style: theme.textTheme.titleSmall),
                          Text(Fmt.dateTime(s.collectionDate), style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SectionHeader(title: 'Segregation by category'),
              for (final category in WasteCategory.values) ...[
                _CategoryCard(
                  category: category,
                  selected: _results[category],
                  showError: _showErrors && !_results.containsKey(category),
                  config: config,
                  onChanged: (r) => setState(() => _results[category] = r),
                ),
                const SizedBox(height: 10),
              ],
              const SectionHeader(title: 'Remarks (optional)'),
              TextField(
                controller: _remarks,
                maxLines: 4,
                minLines: 2,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Feedback for the office, e.g. "Recyclables mixed with food waste."',
                ),
              ),
              if (FeatureFlags.photoUploads) ...[
                SectionHeader(
                  title: 'Collection evidence (optional)',
                  actionLabel: _photos.length < AppConstants.maxEvidencePhotos ? 'Add photo' : null,
                  onAction: _addPhoto,
                ),
                if (_photos.isEmpty)
                  AppCard(
                    onTap: _addPhoto,
                    child: Row(
                      children: [
                        const Icon(Icons.add_a_photo_outlined, color: AppColors.forestGreen),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Attach up to ${AppConstants.maxEvidencePhotos} photos of the collected waste.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _photos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) => Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_photos[i].path),
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: InkWell(
                              onTap: () => setState(() => _photos.removeAt(i)),
                              child: const CircleAvatar(
                                radius: 13,
                                backgroundColor: Colors.black54,
                                child: Icon(Icons.close, size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Calculated score', style: theme.textTheme.labelMedium),
                      Text(
                        '${score.points} / ${score.maxPoints} pts',
                        style: theme.textTheme.titleLarge?.copyWith(color: AppColors.forestGreen),
                      ),
                      Text(
                        '${_results.length} of ${WasteCategory.values.length} assessed',
                        style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: FilledButton(
                    onPressed: _submitting ? null : () => _review(config),
                    child: _submitting
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  _progressLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          )
                        : const Text('Review & submit'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.selected,
    required this.onChanged,
    required this.config,
    this.showError = false,
  });

  final WasteCategory category;
  final SegregationResult? selected;
  final ValueChanged<SegregationResult> onChanged;
  final ScoringConfig config;
  final bool showError;

  String _pointsLabel(SegregationResult r) => switch (r) {
    SegregationResult.proper => '+${config.properPoints}',
    SegregationResult.improper => config.improperPoints == 0 ? '0' : '+${config.improperPoints}',
    SegregationResult.notApplicable => 'excluded',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      borderColor: showError
          ? AppColors.danger
          : (selected != null ? AppColors.tint(selected!.color, 0.5) : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.tint(category.color),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(category.icon, color: category.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.label, style: theme.textTheme.titleSmall),
                    Text(category.examples, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (selected != null) SegregationChip(result: selected!),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final r in SegregationResult.values) ...[
                Expanded(
                  child: _OptionButton(
                    result: r,
                    selected: selected == r,
                    points: _pointsLabel(r),
                    onTap: () => onChanged(r),
                  ),
                ),
                if (r != SegregationResult.values.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.result,
    required this.selected,
    required this.points,
    required this.onTap,
  });

  final SegregationResult result;
  final bool selected;
  final String points;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = result.color;
    return Material(
      color: selected ? color : AppColors.tint(color, 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Icon(result.icon, color: selected ? Colors.white : color, size: 22),
              const SizedBox(height: 4),
              Text(
                result.shortLabel,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              Text(
                points,
                style: TextStyle(color: selected ? Colors.white70 : AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewSheet extends StatelessWidget {
  const _ReviewSheet({
    required this.schedule,
    required this.results,
    required this.score,
    required this.remarks,
    required this.photoCount,
  });

  final Schedule schedule;
  final Map<WasteCategory, SegregationResult> results;
  final ScoreBreakdown score;
  final String remarks;
  final int photoCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Review assessment', style: theme.textTheme.titleLarge),
            Text(schedule.officeName, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            for (final c in WasteCategory.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(c.icon, color: c.color, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(c.label)),
                    SegregationChip(result: results[c]!),
                  ],
                ),
              ),
            const Divider(height: 28),
            Row(
              children: [
                Expanded(child: Text('Points to award', style: theme.textTheme.titleSmall)),
                Text(
                  '${score.points} / ${score.maxPoints}',
                  style: theme.textTheme.headlineSmall?.copyWith(color: AppColors.forestGreen),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${score.properCount} properly segregated · ${score.improperCount} improperly · '
              '${WasteCategory.values.length - score.applicableCount} not applicable',
              style: theme.textTheme.bodySmall,
            ),
            if (remarks.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Remarks', style: theme.textTheme.labelLarge),
              Text(remarks),
            ],
            if (FeatureFlags.photoUploads) ...[
              const SizedBox(height: 8),
              Text(
                '$photoCount evidence photo${photoCount == 1 ? '' : 's'} attached',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.tint(AppColors.warning, 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Submitting marks the collection as completed, awards the points and notifies the '
                'office. An assessment cannot be changed after submission.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Submit assessment'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Back to editing'),
            ),
          ],
        ),
      ),
    );
  }
}
