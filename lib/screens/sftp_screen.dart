import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class SftpScreen extends StatefulWidget {
  final String profileId;
  final String host;

  const SftpScreen({super.key, required this.profileId, required this.host});

  @override
  State<SftpScreen> createState() => _SftpScreenState();
}

class _SftpScreenState extends State<SftpScreen> {
  bool _isWideScreen = true;

  @override
  Widget build(BuildContext context) {
    _isWideScreen = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: AppColors.canvasBase,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.folder_shared, color: AppColors.electricCyan),
            const SizedBox(width: 8),
            Text('SFTP: ${widget.host}'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () {}),
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
        ],
      ),
      body: _isWideScreen ? _buildDualPanel() : _buildSinglePanel(),
    );
  }

  Widget _buildDualPanel() {
    return Row(
      children: [
        Expanded(
          child: _buildFilePanel('LOCAL', '/storage/emulated/0', true),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: AppColors.surfaceBorder),
        Expanded(
          child: _buildFilePanel('REMOTE', '/home/user', false),
        ),
      ],
    );
  }

  Widget _buildSinglePanel() {
    // On mobile, just show remote or add a tab switcher
    return _buildFilePanel('REMOTE', '/home/user', false);
  }

  Widget _buildFilePanel(String title, String path, bool isLocal) {
    return Container(
      color: AppColors.surface1,
      child: Column(
        children: [
          // Panel Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.surfaceBorder)),
            ),
            child: Row(
              children: [
                Text(
                  title,
                  style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    path,
                    style: AppTextStyles.monoMedium.copyWith(color: AppColors.electricCyan),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isLocal)
                  const Icon(Icons.cloud, size: 16, color: AppColors.textSecondary)
                else
                  const Icon(Icons.smartphone, size: 16, color: AppColors.textSecondary),
              ],
            ),
          ),
          
          // Action Bar
          Container(
            padding: const EdgeInsets.all(8),
            color: AppColors.surface2,
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.create_new_folder), onPressed: () {}, tooltip: 'New Folder'),
                IconButton(icon: const Icon(Icons.delete), onPressed: () {}, tooltip: 'Delete'),
                const Spacer(),
                if (isLocal)
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.upload, size: 16),
                    label: const Text('Upload'),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Download'),
                  ),
              ],
            ),
          ),
          
          // File List (Mock)
          Expanded(
            child: ListView.builder(
              itemCount: 10,
              itemBuilder: (context, index) {
                final isFolder = index < 3;
                return ListTile(
                  leading: Icon(
                    isFolder ? Icons.folder : Icons.insert_drive_file,
                    color: isFolder ? AppColors.subtleAmber : AppColors.textSecondary,
                  ),
                  title: Text(
                    isFolder ? 'Folder $index' : 'file_name_$index.txt',
                    style: AppTextStyles.bodyLarge,
                  ),
                  subtitle: Text(
                    isFolder ? 'Directory' : '${(index + 1) * 12} KB',
                    style: AppTextStyles.bodySmall,
                  ),
                  trailing: const Icon(Icons.more_vert),
                  onTap: () {
                    // Navigate folder or open file
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
