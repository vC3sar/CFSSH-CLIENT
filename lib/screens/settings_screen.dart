import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../security/secure_storage.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'keys_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    return Container(
      color: Colors.transparent, // Background handled by parent container
      child: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text(
            'Settings',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'App Preferences & Security',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.electricCyan,
                ),
          ),
          const SizedBox(height: 32),
          
          _buildSectionHeader('Terminal'),
          Card(
            color: AppColors.surface1,
            margin: const EdgeInsets.only(bottom: 24.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Default Font Size'),
                    subtitle: Text('${settings.defaultFontSize.toInt()} px'),
                    trailing: SizedBox(
                      width: 150,
                      child: Slider(
                        value: settings.defaultFontSize,
                        min: 8.0,
                        max: 48.0,
                        divisions: 40,
                        activeColor: AppColors.electricCyan,
                        onChanged: (value) {
                          settingsNotifier.setDefaultFontSize(value);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          _buildSectionHeader('File Transfer (SFTP)'),
          Card(
            color: AppColors.surface1,
            margin: const EdgeInsets.only(bottom: 24.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Use System File Picker (SAF)'),
                    subtitle: const Text('Use native Android picker instead of custom explorer'),
                    activeThumbColor: AppColors.phosphorGreen,
                    value: settings.useSafFilePicker,
                    onChanged: (value) {
                      settingsNotifier.setUseSafFilePicker(value);
                    },
                  ),
                ],
              ),
            ),
          ),

          _buildSectionHeader('Security & Data'),
          Card(
            color: AppColors.surface1,
            margin: const EdgeInsets.only(bottom: 24.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.key, color: AppColors.electricCyan),
                    title: const Text('SSH Key Manager'),
                    subtitle: const Text('Generate, import, export & manage SSH key pairs'),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.textDisabled),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const KeysScreen()),
                      );
                    },
                  ),
                  const Divider(color: AppColors.surfaceBorder, height: 1),
                  ListTile(
                    title: const Text('Clear Saved Credentials', style: TextStyle(color: AppColors.softCrimson)),
                    subtitle: const Text('Wipes all passwords and keys from secure storage'),
                    trailing: const Icon(Icons.delete_forever, color: AppColors.softCrimson),
                    onTap: () => _showClearCredentialsDialog(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        title.toUpperCase(),
        style: AppTextStyles.labelMedium.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Future<void> _showClearCredentialsDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface2,
        title: const Text('Clear Credentials', style: TextStyle(color: AppColors.softCrimson)),
        content: const Text('Are you sure you want to delete all saved passwords and private keys from the device\'s secure keystore? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.softCrimson),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CLEAR ALL', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true) {
      final secureStorage = SecureStorage();
      await secureStorage.clearAll();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All credentials securely erased.'),
            backgroundColor: AppColors.phosphorGreen,
          ),
        );
      }
    }
  }
}
