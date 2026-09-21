import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../providers/connection_provider.dart';
import '../providers/history_provider.dart';
import '../providers/ssh_provider.dart';
import 'connections_screen.dart';
import 'settings_screen.dart';
import 'sftp_selector_screen.dart';
import 'terminal_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final bool isWideScreen = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (isWideScreen) _buildSidebar(),
            Expanded(child: _buildMainContent()),
          ],
        ),
      ),
      bottomNavigationBar: isWideScreen ? null : _buildBottomNav(),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
      color: AppColors.surface1,
      child: Column(
        children: [
          const SizedBox(height: 32),
          const Icon(Icons.rocket_launch, size: 48, color: AppColors.electricCyan),
          const SizedBox(height: 16),
          Text('CFSSH', style: AppTextStyles.headlineMedium),
          const SizedBox(height: 32),
          _buildSidebarItem(Icons.dashboard, 'Dashboard', 0),
          _buildSidebarItem(Icons.dns, 'Servers', 1),
          _buildSidebarItem(Icons.folder_shared, 'Files', 2),
          const Spacer(),
          _buildSidebarItem(Icons.settings, 'Settings', 3),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(IconData icon, String label, int index) {
    final isSelected = _selectedIndex == index;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? AppColors.electricCyan : AppColors.textSecondary,
      ),
      title: Text(
        label,
        style: AppTextStyles.titleMedium.copyWith(
          color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
        ),
      ),
      selected: isSelected,
      selectedTileColor: AppColors.surface2,
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.surfaceBorder),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        backgroundColor: AppColors.surface1,
        selectedItemColor: AppColors.electricCyan,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.dns), label: 'Servers'),
          BottomNavigationBarItem(icon: Icon(Icons.folder_shared), label: 'Files'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_selectedIndex == 1) {
      return const ConnectionsScreen();
    } else if (_selectedIndex == 2) {
      return const SftpSelectorScreen();
    } else if (_selectedIndex == 3) {
      return const SettingsScreen();
    }
    
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final bgImage = isPortrait ? 'assets/background_vertical.png' : 'assets/background_horizontal.png';

    // Watch providers
    final profilesState = ref.watch(connectionProfilesProvider);
    final historyState = ref.watch(historyProvider);
    final activeSessions = ref.watch(sshEngineProvider).activeSessions.where((s) => s.isConnected).length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.canvasBase,
        image: DecorationImage(
          image: AssetImage(bgImage),
          fit: BoxFit.cover,
          opacity: 0.7,
        ),
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CFSSH CLIENT',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Secure Remote Access',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.electricCyan,
                ),
          ),
          const SizedBox(height: 32),
          
          // Dashboard Grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: MediaQuery.of(context).size.width >= 1024 ? 4 : 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 2.0,
            children: [
              _buildGlassStatCard('ACTIVE', '$activeSessions', AppColors.phosphorGreen),
              _buildGlassStatCard('SERVERS', '${profilesState.profiles.length}', AppColors.textPrimary),
            ],
          ),
          
          const SizedBox(height: 32),
          Text('RECENT CONNECTIONS', style: AppTextStyles.labelMedium),
          const SizedBox(height: 16),
          
          // Recent Connections Feed
          Expanded(
            child: historyState.isEmpty
                ? Center(
                    child: Text('No recent connections.', style: AppTextStyles.bodyMedium),
                  )
                : ListView.builder(
                    itemCount: historyState.length,
                    itemBuilder: (context, index) {
                      final history = historyState[index];
                      // Find profile
                      final profile = profilesState.profiles.firstWhere(
                        (p) => p.id == history.profileId,
                        orElse: () => profilesState.profiles.first, // Fallback if deleted
                      );
                      
                      // Don't show if profile was deleted
                      if (!profilesState.profiles.any((p) => p.id == history.profileId)) {
                        return const SizedBox.shrink();
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface1.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.surfaceBorder.withValues(alpha: 0.3)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: AppColors.surface2,
                                child: Icon(Icons.computer, color: AppColors.electricCyan),
                              ),
                              title: Text(profile.name, style: AppTextStyles.titleMedium),
                              subtitle: Text(
                                timeago.format(history.timestamp),
                                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                              ),
                              trailing: const Icon(Icons.chevron_right, color: AppColors.textDisabled),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => TerminalScreen(profile: profile),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassStatCard(String title, String value, Color valueColor) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder.withValues(alpha: 0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: valueColor,
                    fontWeight: FontWeight.bold,
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
