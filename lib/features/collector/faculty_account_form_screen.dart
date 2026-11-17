import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/validators.dart';
import '../../providers/office_provider.dart';
import '../../repositories/office_repository.dart';
import '../../shared/widgets/dialogs.dart';

/// Text controllers for the faculty account fields.
class AccountFieldsController {
  final fullName = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();

  void dispose() {
    fullName.dispose();
    email.dispose();
    password.dispose();
  }
}

/// Reusable name / email / temporary password fields.
class AccountFields extends StatefulWidget {
  const AccountFields({super.key, required this.controller});

  final AccountFieldsController controller;

  @override
  State<AccountFields> createState() => _AccountFieldsState();
}

class _AccountFieldsState extends State<AccountFields> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Column(
      children: [
        TextFormField(
          controller: c.fullName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Account holder name',
            hintText: 'e.g. Office secretary or office name',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          validator: (v) => Validators.name(v, 'Name'),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: c.email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Login email',
            prefixIcon: Icon(Icons.mail_outline),
          ),
          validator: Validators.email,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: c.password,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Temporary password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          validator: Validators.password,
        ),
      ],
    );
  }
}

/// Collector: add another login account to an existing office.
class FacultyAccountFormScreen extends ConsumerStatefulWidget {
  const FacultyAccountFormScreen({super.key, required this.officeId});

  final String officeId;

  @override
  ConsumerState<FacultyAccountFormScreen> createState() => _FacultyAccountFormScreenState();
}

class _FacultyAccountFormScreenState extends ConsumerState<FacultyAccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _account = AccountFieldsController();
  bool _saving = false;

  @override
  void dispose() {
    _account.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(officeRepositoryProvider).provisionFacultyAccount(
            officeId: widget.officeId,
            fullName: _account.fullName.text,
            email: _account.email.text,
            password: _account.password.text,
          );
      if (!mounted) return;
      showSuccessSnack(context, 'Login account created');
      context.pop();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider(widget.officeId)).value;
    return Scaffold(
      appBar: AppBar(title: const Text('New office account')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (office != null) ...[
              Text('For ${office.officeName}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
            ],
            AccountFields(controller: _account),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Create account'),
            ),
          ],
        ),
      ),
    );
  }
}
