import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/connection_provider.dart';
import '../models/connection_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'sftp_screen.dart';

class SftpSelectorScreen extends ConsumerWidget {
  const SftpSelectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectionProfilesProvider);
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final bgImage = isPortrait ? 'assets/background_vertical.png' : 'assets/background_horizontal.png';

    return Scaffold(
      backgroundColor: AppColors.canvasBase,
      appBar: AppBar(
        title: const Text('SFTP File Manager'),
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(bgImage),
            fit: BoxFit.cover,
            opacity: 0.7,
          ),
        ),
        child: _buildBody(context, state),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ConnectionProfileState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(child: Text('Error: ${state.error}', style: const TextStyle(color: AppColors.softCrimson)));
    }

    final profiles = state.profiles;
    if (profiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_off_outlined, size: 64, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text('No saved connections', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 8),
            Text('Go to Servers tab to add a connection.', style: AppTextStyles.bodyMedium),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: profiles.length,
      itemBuilder: (context, index) {
        final profile = profiles[index];
        final status = state.statuses[profile.id] ?? ServerStatus.checking;

        Widget statusIcon;
        switch (status) {
          case ServerStatus.online:
            statusIcon = const Icon(Icons.check_circle, size: 12, color: AppColors.phosphorGreen);
            break;
          case ServerStatus.offline:
            statusIcon = const Icon(Icons.cancel, size: 12, color: AppColors.softCrimson);
            break;
          case ServerStatus.checking:
            statusIcon = const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
            );
            break;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.surface1,
                  child: Icon(Icons.folder_shared, color: AppColors.subtleAmber),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppColors.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: statusIcon,
                  ),
                ),
              ],
            ),
            title: Text(profile.name, style: AppTextStyles.titleMedium),
            subtitle: Text(
              '${profile.host}:${profile.port}',
              style: AppTextStyles.monoSmall,
            ),
            trailing: ElevatedButton.icon(
              icon: const Icon(Icons.folder, size: 16),
              label: const Text('Browse Files'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SftpScreen(profile: profile),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
