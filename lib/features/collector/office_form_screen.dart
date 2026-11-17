import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/exceptions/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';
import '../../models/office_model.dart';
import '../../providers/office_provider.dart';
import '../../repositories/office_repository.dart';
import '../../routes/app_routes.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/state_views.dart';
import 'faculty_account_form_screen.dart';

/// Collector: register a new faculty office together with its login account
/// (via the `provisionFacultyAccount` Cloud Function), or edit an existing
/// office's name, building and description.
class OfficeFormScreen extends ConsumerWidget {
  const OfficeFormScreen({super.key, this.officeId});

  final String? officeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (officeId == null) return const _OfficeForm();
    final office = ref.watch(officeProvider(officeId!));
    return office.when(
      skipLoadingOnReload: true,
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorState(message: AppException.messageOf(e))),
      data: (o) => o == null
          ? Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.apartment, title: 'Office not found'))
          : _OfficeForm(existing: o),
    );
  }
}

class _OfficeForm extends ConsumerStatefulWidget {
  const _OfficeForm({this.existing});

  final Office? existing;

  @override
  ConsumerState<_OfficeForm> createState() => _OfficeFormState();
}

class _OfficeFormState extends ConsumerState<_OfficeForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.officeName);
  late final _building = TextEditingController(text: widget.existing?.building);
  late final _description = TextEditingController(text: widget.existing?.description);
  final _account = AccountFieldsController();
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _building.dispose();
    _description.dispose();
    _account.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(officeRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.updateOfficeDetails(
          widget.existing!.officeId,
          officeName: _name.text,
          building: _building.text,
          description: _description.text,
        );
        if (!mounted) return;
        showSuccessSnack(context, 'Office updated');
        context.pop();
      } else {
        final result = await repo.provisionFacultyAccount(
          officeName: _name.text,
          building: _building.text,
          description: _description.text,
          fullName: _account.fullName.text,
          email: _account.email.text,
          password: _account.password.text,
        );
        if (!mounted) return;
        showSuccessSnack(context, 'Office and login account created');
        context.pushReplacement(AppRoutes.collectorOffice(result.officeId));
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
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit office' : 'Add faculty office')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const SectionHeader(title: 'Office information', padding: EdgeInsets.fromLTRB(4, 4, 0, 8)),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Office name',
                hintText: 'e.g. College of Engineering Dean\'s Office',
                prefixIcon: Icon(Icons.apartment),
              ),
              validator: (v) => Validators.name(v, 'Office name'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _building,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Building / location',
                hintText: 'e.g. Main Building, 2nd floor',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              validator: (v) => Validators.name(v, 'Building'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              maxLines: 3,
              minLines: 2,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                alignLabelWithHint: true,
              ),
            ),
            if (!_isEdit) ...[
              const SectionHeader(title: 'Office login account'),
              Text(
                'Faculty Office staff will sign in with these credentials. Share the temporary '
                'password privately; they can change it from their profile.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              AccountFields(controller: _account),
            ] else ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.mintSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Points and collection statistics are maintained automatically and cannot be edited.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(_isEdit ? 'Save changes' : 'Create office & account'),
            ),
          ],
        ),
      ),
    );
  }
}
