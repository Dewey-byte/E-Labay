import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/scoring_config.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/points_provider.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/config_repository.dart';
import '../../repositories/leaderboard_repository.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/section_header.dart';

/// Settings for both roles. Collectors manage scoring rules and leaderboard
/// maintenance; Faculty Offices manage push notifications.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Scaffold();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (user.isCollector) ...[
            const SectionHeader(title: 'Scoring rules'),
            const _ScoringCard(),
            const SectionHeader(title: 'Maintenance'),
            const _RecalculateCard(),
          ] else ...[
            const SectionHeader(title: 'Notifications'),
            _PushCard(user: user),
          ],
          const SectionHeader(title: 'About'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.eco_outlined),
                  title: Text(AppConstants.appName),
                  subtitle: Text(AppConstants.appTagline),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Licenses'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: AppConstants.appName,
                    applicationVersion: '1.0.0',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () async {
              final ok = await showConfirmDialog(
                context,
                title: 'Sign out?',
                message: 'You will need to sign in again to use E-Labay.',
                confirmLabel: 'Sign out',
              );
              if (ok) await ref.read(sessionControllerProvider).signOut();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _PushCard extends ConsumerStatefulWidget {
  const _PushCard({required this.user});
  final AppUser user;

  @override
  ConsumerState<_PushCard> createState() => _PushCardState();
}

class _PushCardState extends ConsumerState<_PushCard> {
  bool _saving = false;

  Future<void> _toggle(bool value) async {
    setState(() => _saving = true);
    try {
      await ref.read(authRepositoryProvider).setPushEnabled(widget.user.uid, value);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: SwitchListTile(
        secondary: const Icon(Icons.notifications_active_outlined),
        title: const Text('Push notifications'),
        subtitle: const Text(
          'Alerts for schedules, reminders and assessment results. '
          'The in-app feed is always kept up to date.',
        ),
        value: widget.user.pushEnabled,
        onChanged: _saving ? null : _toggle,
      ),
    );
  }
}

class _ScoringCard extends ConsumerWidget {
  const _ScoringCard();

  Future<void> _edit(BuildContext context, WidgetRef ref, ScoringConfig current) async {
    final updated = await showDialog<ScoringConfig>(
      context: context,
      builder: (_) => _ScoringDialog(initial: current),
    );
    if (updated == null || !context.mounted) return;
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;
    try {
      await ref.read(configRepositoryProvider).updateScoringConfig(updated, uid: uid);
      if (context.mounted) showSuccessSnack(context, 'Scoring rules updated for future assessments');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(scoringConfigProvider).value ?? ScoringConfig.defaults;
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RuleRow(label: 'Properly segregated category', value: '+${config.properPoints} pts'),
          _RuleRow(label: 'Improperly segregated category', value: '+${config.improperPoints} pts'),
          const _RuleRow(label: 'Not applicable category', value: 'excluded'),
          const Divider(height: 24),
          _RuleRow(label: 'Maximum per collection', value: '${config.maxPointsPerCollection} pts', bold: true),
          const SizedBox(height: 12),
          Text(
            'Changes apply to future assessments only. Points already awarded are never changed.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _edit(context, ref, config),
            icon: const Icon(Icons.tune),
            label: const Text('Adjust point values'),
          ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: bold ? FontWeight.w700 : null,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style?.copyWith(color: AppColors.forestGreen, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ScoringDialog extends StatefulWidget {
  const _ScoringDialog({required this.initial});
  final ScoringConfig initial;

  @override
  State<_ScoringDialog> createState() => _ScoringDialogState();
}

class _ScoringDialogState extends State<_ScoringDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _proper = TextEditingController(text: '${widget.initial.properPoints}');
  late final _improper = TextEditingController(text: '${widget.initial.improperPoints}');

  @override
  void dispose() {
    _proper.dispose();
    _improper.dispose();
    super.dispose();
  }

  String? _validate(String? v) {
    final n = int.tryParse(v ?? '');
    if (n == null) return 'Enter a whole number';
    if (n < ScoringConfig.minPoints || n > ScoringConfig.maxPointsPerCategory) {
      return 'Use ${ScoringConfig.minPoints}–${ScoringConfig.maxPointsPerCategory}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Point values'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _proper,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Properly segregated (per category)'),
              validator: (v) {
                final base = _validate(v);
                if (base != null) return base;
                return int.parse(v!) == 0 ? 'Must be greater than 0' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _improper,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Improperly segregated (per category)'),
              validator: (v) {
                final base = _validate(v);
                if (base != null) return base;
                final proper = int.tryParse(_proper.text) ?? 0;
                return int.parse(v!) > proper ? 'Cannot exceed the proper value' : null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              ScoringConfig(
                properPoints: int.parse(_proper.text),
                improperPoints: int.parse(_improper.text),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _RecalculateCard extends ConsumerStatefulWidget {
  const _RecalculateCard();

  @override
  ConsumerState<_RecalculateCard> createState() => _RecalculateCardState();
}

class _RecalculateCardState extends ConsumerState<_RecalculateCard> {
  bool _running = false;

  Future<void> _run() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Recalculate leaderboard?',
      message: 'Every office total is recomputed on the server from the permanent point '
          'transaction ledger and collection records.',
      confirmLabel: 'Recalculate',
    );
    if (!ok) return;
    setState(() => _running = true);
    try {
      final count = await ref.read(leaderboardRepositoryProvider).recalculate();
      if (mounted) showSuccessSnack(context, 'Totals verified for $count offices');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.sync),
        title: const Text('Recalculate leaderboard totals'),
        subtitle: const Text('Verify office points against the transaction ledger'),
        trailing: _running
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chevron_right),
        onTap: _running ? null : _run,
      ),
    );
  }
}
