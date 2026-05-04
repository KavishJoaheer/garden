import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../../core/widgets/error_widget.dart';
import '../../../../core/widgets/gardnx_app_bar.dart';
import '../../../../core/widgets/loading_indicator.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/models/user_profile.dart';
import '../providers/profile_provider.dart';
import '../widgets/preference_selector.dart';

/// Profile screen displaying the user's photo, email, display name,
/// plant preferences, and a logout button.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _displayNameController = TextEditingController();
  bool _isEditingName = false;
  bool _isDeletingAccount = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _handlePickPhoto() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (xFile == null || !mounted) return;

    final notifier = ref.read(profileNotifierProvider.notifier);
    await notifier.uploadProfilePhoto(File(xFile.path));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated.')),
      );
    }
  }

  Future<void> _handleDeletePhoto() async {
    final confirmed = await ConfirmationDialog.show(
      context: context,
      title: 'Remove Photo',
      message: 'Are you sure you want to remove your profile photo?',
      confirmLabel: 'Remove',
      isDestructive: true,
    );

    if (!confirmed || !mounted) return;

    final notifier = ref.read(profileNotifierProvider.notifier);
    await notifier.deleteProfilePhoto();
  }

  Future<void> _handleSaveDisplayName() async {
    final name = _displayNameController.text.trim();
    if (name.isEmpty) return;

    final notifier = ref.read(profileNotifierProvider.notifier);
    await notifier.updateDisplayName(name);

    if (mounted) {
      setState(() => _isEditingName = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Display name updated.')),
      );
    }
  }

  Future<void> _handleUpdatePreferences(PlantPreferences prefs) async {
    final notifier = ref.read(profileNotifierProvider.notifier);
    await notifier.updatePreferences(prefs);
  }

  Future<void> _handleLogout() async {
    final confirmed = await ConfirmationDialog.show(
      context: context,
      title: 'Sign Out',
      message: 'Are you sure you want to sign out?',
      confirmLabel: 'Sign Out',
    );

    if (!confirmed || !mounted) return;

    final signOut = ref.read(signOutProvider);
    await signOut();
  }

  Future<void> _handleDeleteAccount() async {
    final confirmed = await ConfirmationDialog.show(
      context: context,
      title: 'Delete Account',
      message:
          'Are you sure you want to permanently delete your account and all associated data? This action cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );

    if (!confirmed || !mounted) return;

    setState(() => _isDeletingAccount = true);
    try {
      final deleteAccount = ref.read(deleteAccountProvider);
      await deleteAccount();
      // After deletion, the auth stream will automatically route to Splash->Login.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete account: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeletingAccount = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final mutationState = ref.watch(profileNotifierProvider);
    final isMutating = mutationState is AsyncLoading;

    return Scaffold(
      appBar: const GardNxAppBar(title: 'Profile'),
      body: profileAsync.when(
        loading: () => const LoadingIndicator(message: 'Loading profile...'),
        error: (error, _) => AppErrorWidget(
          message: 'Could not load profile.\n$error',
          onRetry: () => ref.invalidate(currentUserProfileProvider),
        ),
        data: (profile) {
          if (profile == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_off_outlined, size: 64,
                        color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'Profile not found.\nPlease sign out and sign up again.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () async {
                        await ref.read(signOutProvider)();
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign Out'),
                    ),
                  ],
                ),
              ),
            );
          }

          return Stack(
            children: [
              _buildProfileContent(context, profile),
              if (isMutating || _isDeletingAccount)
                Container(
                  color: Colors.black26,
                  child: LoadingIndicator(
                    message: _isDeletingAccount ? 'Deleting account...' : 'Saving...',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProfileContent(BuildContext context, UserProfile profile) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          // ----- Profile Photo -----
          _buildPhotoSection(profile),
          const SizedBox(height: 24),

          // ----- Email (read-only) -----
          _buildInfoTile(
            icon: Icons.email_outlined,
            label: 'Email',
            value: profile.email,
          ),
          const SizedBox(height: 12),

          // ----- Display Name -----
          _buildDisplayNameSection(profile),
          const SizedBox(height: 24),

          // ----- Experience Level -----
          _buildExperienceLevelSection(profile),
          const SizedBox(height: 24),

          // ----- Plant Preferences -----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Plant Preferences',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  PreferenceSelector(
                    selectedTypes: profile.preferences.plantTypes,
                    onChanged: (types) {
                      _handleUpdatePreferences(
                        profile.preferences.copyWith(plantTypes: types),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ----- Location -----
          if (profile.location.region != null)
            _buildInfoTile(
              icon: Icons.location_on_outlined,
              label: 'Region',
              value: profile.location.region!,
            ),
          const SizedBox(height: 32),

          // ----- Logout Button -----
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout, color: AppColors.error),
              label: const Text(
                'Sign Out',
                style: TextStyle(color: AppColors.error),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ----- Delete Account Button -----
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _handleDeleteAccount,
              icon: const Icon(Icons.delete_forever, color: AppColors.error),
              label: const Text(
                'Delete Account',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ----- Account info -----
          Text(
            'Member since ${_formatDate(profile.createdAt)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sub-sections
  // ---------------------------------------------------------------------------

  Widget _buildPhotoSection(UserProfile profile) {
    return Center(
      child: Stack(
        children: [
          CircleAvatar(
            radius: 56,
            backgroundColor: AppColors.primaryContainer,
            backgroundImage: profile.photoUrl != null
                ? FileImage(File(profile.photoUrl!))
                : null,
            child: profile.photoUrl == null
                ? const Icon(Icons.person, size: 56, color: AppColors.primary)
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Material(
              shape: const CircleBorder(),
              elevation: 2,
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primary,
                child: PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.camera_alt,
                    size: 18,
                    color: Colors.white,
                  ),
                  onSelected: (value) {
                    if (value == 'upload') {
                      _handlePickPhoto();
                    } else if (value == 'remove') {
                      _handleDeletePhoto();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'upload',
                      child: ListTile(
                        leading: Icon(Icons.photo_library_outlined),
                        title: Text('Choose Photo'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (profile.photoUrl != null)
                      const PopupMenuItem(
                        value: 'remove',
                        child: ListTile(
                          leading:
                              Icon(Icons.delete_outline, color: AppColors.error),
                          title: Text('Remove Photo',
                              style: TextStyle(color: AppColors.error)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisplayNameSection(UserProfile profile) {
    final theme = Theme.of(context);

    if (_isEditingName) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'Display Name',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleSaveDisplayName(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _handleSaveDisplayName,
                icon: const Icon(Icons.check, color: AppColors.primary),
              ),
              IconButton(
                onPressed: () => setState(() => _isEditingName = false),
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: ListTile(
        leading: const Icon(Icons.person_outline, color: AppColors.primary),
        title: Text('Display Name', style: theme.textTheme.labelMedium),
        subtitle: Text(
          profile.displayName ?? 'Not set',
          style: theme.textTheme.bodyLarge,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
          onPressed: () {
            _displayNameController.text = profile.displayName ?? '';
            setState(() => _isEditingName = true);
          },
        ),
      ),
    );
  }

  Widget _buildExperienceLevelSection(UserProfile profile) {
    final theme = Theme.of(context);
    final levels = ['beginner', 'intermediate', 'advanced'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Experience Level', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: levels
                  .map((level) => ButtonSegment(
                        value: level,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            level[0].toUpperCase() + level.substring(1),
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                          ),
                        ),
                      ))
                  .toList(),
              selected: {profile.preferences.experienceLevel},
              onSelectionChanged: (selected) {
                final newLevel = selected.first;
                _handleUpdatePreferences(
                  profile.preferences.copyWith(experienceLevel: newLevel),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(label, style: theme.textTheme.labelMedium),
        subtitle: Text(value, style: theme.textTheme.bodyLarge),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
