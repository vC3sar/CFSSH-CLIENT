import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'connections_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Determine if we are on a tablet/desktop (wide screen)
    final bool isWideScreen = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (isWideScreen)
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (int index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                },
                labelType: NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard),
                    label: Text('Dashboard'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.dns_outlined),
                    selectedIcon: Icon(Icons.dns),
                    label: Text('Servers'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.history),
                    selectedIcon: Icon(Icons.history),
                    label: Text('History'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: Text('Settings'),
                  ),
                ],
              ),
            if (isWideScreen)
              const VerticalDivider(thickness: 1, width: 1, color: AppColors.surfaceBorder),
            
            // Main Content Area
            Expanded(
              child: _buildMainContent(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: !isWideScreen
          ? NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              backgroundColor: AppColors.surface1,
              indicatorColor: AppColors.surfaceHighlightBorder,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard, color: AppColors.electricCyan),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.dns_outlined),
                  selectedIcon: Icon(Icons.dns, color: AppColors.electricCyan),
                  label: 'Servers',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history),
                  selectedIcon: Icon(Icons.history, color: AppColors.electricCyan),
                  label: 'History',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings, color: AppColors.electricCyan),
                  label: 'Settings',
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildMainContent() {
    if (_selectedIndex == 1) {
      return const ConnectionsScreen();
    }
    
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final bgImage = isPortrait ? 'assets/background_vertical.png' : 'assets/background_horizontal.png';

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
          
          // Dashboard Grid (Placeholder)
          Expanded(
            child: GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width >= 1024 ? 4 : 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.5,
              children: [
                _buildStatCard('ACTIVE SESSIONS', '0', AppColors.phosphorGreen),
                _buildStatCard('SAVED SERVERS', '0', AppColors.textPrimary),
                _buildStatCard('TRANSFERS', '0 active', AppColors.subtleAmber),
                _buildStatCard('RECENT', '-', AppColors.textSecondary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color valueColor) {
    return Card(
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
