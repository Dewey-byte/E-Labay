import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/office_provider.dart';
import '../../repositories/auth_repository.dart';
import '../../routes/app_routes.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/initials_avatar.dart';
import '../../shared/widgets/status_chip.dart';

/// Profile for both roles: identity, office, photo, name and password.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploading = false;

  Future<void> _changePhoto(AppUser user) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      imageQuality: 75,
    );
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      await ref.read(authRepositoryProvider).uploadProfileImage(user.uid, File(file.path));
      if (mounted) showSuccessSnack(context, 'Profile photo updated');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _editName(AppUser user) async {
    final controller = TextEditingController(text: user.fullName);
    final formKey = GlobalKey<FormState>();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit name'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name'),
            validator: (v) => Validators.name(v, 'Name'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, controller.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name == user.fullName || !mounted) return;
    try {
      await ref.read(authRepositoryProvider).updateProfile(user.uid, fullName: name);
      if (mounted) showSuccessSnack(context, 'Name updated');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _changePassword() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ChangePasswordSheet(),
    );
    if (changed == true && mounted) showSuccessSnack(context, 'Password changed');
  }

  Future<void> _signOut() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will stop receiving push notifications on this device until you sign in again.',
      confirmLabel: 'Sign out',
    );
    if (ok) await ref.read(sessionControllerProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Scaffold();
    final office = user.isFaculty ? ref.watch(myOfficeProvider).value : null;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Stack(
                  children: [
                    InitialsAvatar(name: user.displayName, imageUrl: user.profileImage, size: 88),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Material(
                        color: AppColors.forestGreen,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _uploading ? null : () => _changePhoto(user),
                          child: Padding(
                            padding: const EdgeInsets.all(7),
                            child: _uploading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.camera_alt_outlined, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(user.displayName, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                Text(user.email, style: theme.textTheme.bodySmall),
                const SizedBox(height: 10),
                TagChip(
                  label: user.role.label,
                  color: user.isCollector ? AppColors.info : AppColors.forestGreen,
                  icon: user.isCollector ? Icons.local_shipping_outlined : Icons.apartment,
                ),
              ],
            ),
          ),
          if (office != null) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Row(
                children: [
                  const Icon(Icons.apartment, color: AppColors.forestGreen),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(office.officeName, style: theme.textTheme.titleSmall),
                        if (office.building.isNotEmpty) Text(office.building, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (user.isFaculty) ...[
                  ListTile(
                    leading: const Icon(Icons.emoji_events_outlined),
                    title: const Text('Points history'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.facultyPoints),
                  ),
                  ListTile(
                    leading: const Icon(Icons.insights_outlined),
                    title: const Text('Office performance'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.facultyPerformance),
                  ),
                  const Divider(),
                ],
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Edit name'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editName(user),
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Change password'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _changePassword,
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    user.isCollector ? AppRoutes.collectorSettings : AppRoutes.facultySettings,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _new.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Change password', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
              validator: Validators.loginPassword,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _new,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
              validator: Validators.password,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm new password'),
              validator: (v) => v != _new.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Update password'),
            ),
          ],
        ),
      ),
    );
  }
}
