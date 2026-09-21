import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../models/connection_profile.dart';
import '../providers/sftp_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class SftpScreen extends ConsumerWidget {
  final ConnectionProfile profile;

  const SftpScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sftpState = ref.watch(sftpProvider(profile));
    final notifier = ref.read(sftpProvider(profile).notifier);

    return Scaffold(
      backgroundColor: AppColors.canvasBase,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.folder_shared, color: AppColors.electricCyan),
            const SizedBox(width: 8),
            Text(profile.name),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => notifier.loadDirectory(sftpState.currentPath),
          ),
        ],
      ),
      body: Column(
        children: [
          // Path Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.surface1,
              border: Border(bottom: BorderSide(color: AppColors.surfaceBorder)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 20, color: AppColors.textSecondary),
                  onPressed: () => notifier.navigateUp(),
                  tooltip: 'Go Up',
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    sftpState.currentPath,
                    style: AppTextStyles.monoMedium.copyWith(color: AppColors.electricCyan),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          
          // Error Bar
          if (sftpState.error != null && sftpState.error!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: AppColors.softCrimson.withValues(alpha: 0.2),
              child: Text(
                sftpState.error!,
                style: const TextStyle(color: AppColors.softCrimson),
                textAlign: TextAlign.center,
              ),
            ),
            
          // File List
          Expanded(
            child: sftpState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: sftpState.items.length,
                    itemBuilder: (context, index) {
                      final item = sftpState.items[index];
                      final isDir = item.attr.isDirectory;
                      
                      return ListTile(
                        leading: Icon(
                          isDir ? Icons.folder : Icons.insert_drive_file,
                          color: isDir ? AppColors.subtleAmber : AppColors.textSecondary,
                        ),
                        title: Text(item.filename, style: AppTextStyles.bodyLarge),
                        subtitle: Text(
                          isDir ? 'Directory' : _formatSize(item.attr.size ?? 0),
                          style: AppTextStyles.bodySmall,
                        ),
                        trailing: isDir ? null : _buildFileMenu(context, notifier, item.filename),
                        onTap: () {
                          if (isDir) {
                            String nextPath = sftpState.currentPath == '/' 
                                ? '/${item.filename}'
                                : '${sftpState.currentPath}/${item.filename}';
                            if (sftpState.currentPath == '.') {
                                nextPath = './${item.filename}';
                            }
                            notifier.loadDirectory(nextPath);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _handleUpload(context, notifier),
        backgroundColor: AppColors.electricCyan,
        child: const Icon(Icons.upload_file, color: Colors.black),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildFileMenu(BuildContext context, SftpNotifier notifier, String filename) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
      onSelected: (value) {
        if (value == 'download') {
          _handleDownload(context, notifier, filename);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'download',
          child: Row(
            children: [
              Icon(Icons.download, size: 20),
              SizedBox(width: 8),
              Text('Download'),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleUpload(BuildContext context, SftpNotifier notifier) async {
    try {
      final result = await FilePicker.pickFiles();
      if (!context.mounted) return;
      
      if (result.isNotEmpty && result.first.path != null) {
        final localPath = result.first.path!;
        final filename = result.first.name;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploading $filename...')),
        );
        
        await notifier.uploadFile(localPath, filename);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upload complete'), backgroundColor: AppColors.phosphorGreen),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.softCrimson),
        );
      }
    }
  }

  Future<void> _handleDownload(BuildContext context, SftpNotifier notifier, String filename) async {
    try {
      // Create a temporary file path
      final tempDir = Directory.systemTemp;
      final tempFilePath = p.join(tempDir.path, filename);
      
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading $filename to memory...')),
      );
      
      // Download to temp file first
      await notifier.downloadFile(filename, tempFilePath);
      
      if (!context.mounted) return;
      
      // Read bytes and save natively
      final bytes = await File(tempFilePath).readAsBytes();
      
      final resultUri = await FilePicker.saveFile(
        dialogTitle: 'Save $filename',
        fileName: filename,
        bytes: bytes,
      );
      
      if (resultUri != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download complete'), backgroundColor: AppColors.phosphorGreen),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.softCrimson),
        );
      }
    }
  }
}
