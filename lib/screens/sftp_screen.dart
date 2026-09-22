import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';

import '../models/connection_profile.dart';
import '../providers/sftp_provider.dart';
import '../providers/local_file_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/host_key_dialogs.dart';

class SftpScreen extends ConsumerStatefulWidget {
  final ConnectionProfile profile;

  const SftpScreen({super.key, required this.profile});

  @override
  ConsumerState<SftpScreen> createState() => _SftpScreenState();
}

class _SftpScreenState extends ConsumerState<SftpScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sftpProvider(widget.profile).notifier).connectAndLoad(
        onHostKeyVerification: (host, port, algorithm, sha256Fingerprint, md5Fingerprint, isChanged, oldFingerprint) async {
          return await HostKeyDialogs.showVerificationDialog(
            context, ref, host, port, algorithm, sha256Fingerprint, md5Fingerprint, isChanged, oldFingerprint,
          );
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.canvasBase,
        appBar: AppBar(
          title: Row(
            children: [
              const Icon(Icons.folder_shared, color: AppColors.electricCyan),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.profile.name, overflow: TextOverflow.ellipsis)),
            ],
          ),
          bottom: const TabBar(
            indicatorColor: AppColors.electricCyan,
            labelColor: AppColors.electricCyan,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: [
              Tab(icon: Icon(Icons.computer), text: 'Local'),
              Tab(icon: Icon(Icons.cloud), text: 'Remote'),
            ],
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              if (isWide) {
                return Row(
                  children: [
                    Expanded(child: _buildLocalView(context)),
                    Container(width: 1, color: AppColors.surfaceBorder),
                    Expanded(child: _buildRemoteView(context)),
                  ],
                );
              } else {
                return TabBarView(
                  children: [
                    _buildLocalView(context),
                    _buildRemoteView(context),
                  ],
                );
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLocalView(BuildContext context) {
    final state = ref.watch(localFileProvider);
    final notifier = ref.read(localFileProvider.notifier);
    final remoteNotifier = ref.read(sftpProvider(widget.profile).notifier);

    return DropTarget(
      onDragDone: (detail) async {
        if (detail.files.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Importing ${detail.files.length} files...')));
          for (var xFile in detail.files) {
            final sourceFile = File(xFile.path);
            final destPath = p.join(state.currentPath, xFile.name);
            await sourceFile.copy(destPath);
          }
          await notifier.refresh();
        }
      },
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data.startsWith('remote|'),
        onAcceptWithDetails: (details) async {
          // Received from Remote
          final remoteFilename = details.data.substring(7);
          final localDest = p.join(state.currentPath, remoteFilename);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloading $remoteFilename...')));
          await remoteNotifier.downloadFile(remoteFilename, localDest);
          await notifier.refresh();
        },
        builder: (context, candidateData, rejectedData) {
          return Column(
            children: [
              _buildPathBar(
                path: state.currentPath,
                onUp: notifier.navigateUp,
                onRefresh: notifier.refresh,
                title: 'Local Workspace',
                actionIcon: Icons.add_to_drive,
                actionTooltip: 'Import from Phone (SAF)',
                onAction: notifier.importFromSaf,
                highlight: candidateData.isNotEmpty,
              ),
              if (state.error != null) _buildErrorBar(state.error!),
              Expanded(
                child: state.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        itemCount: state.items.length,
                        itemBuilder: (context, index) {
                          final item = state.items[index];
                          final isDir = item is Directory;
                          final filename = p.basename(item.path);
                          
                          Widget listTile = ListTile(
                            leading: Icon(
                              isDir ? Icons.folder : Icons.insert_drive_file,
                              color: isDir ? AppColors.subtleAmber : AppColors.textSecondary,
                            ),
                            title: Text(filename, style: AppTextStyles.bodyLarge),
                            subtitle: Text(isDir ? 'Directory' : _formatSize(File(item.path).lengthSync())),
                            trailing: isDir ? null : SizedBox(
                              width: 40,
                              child: PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                                onSelected: (val) async {
                                  if (val == 'upload') {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploading $filename...')));
                                    await remoteNotifier.uploadFile(item.path, filename);
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload complete'), backgroundColor: AppColors.phosphorGreen));
                                  } else if (val == 'export') {
                                    await notifier.exportToSaf(item as File);
                                  } else if (val == 'delete') {
                                    await notifier.deleteEntity(item);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'upload', child: Text('Upload to Remote')),
                                  const PopupMenuItem(value: 'export', child: Text('Export File (SAF)')),
                                  const PopupMenuItem(value: 'delete', child: Text('Delete Local File', style: TextStyle(color: AppColors.softCrimson))),
                                ],
                              ),
                            ),
                            onTap: () {
                              if (isDir) {
                                notifier.loadDirectory(item.path);
                              }
                            },
                          );

                          if (!isDir) {
                            return Draggable<String>(
                              data: 'local|${item.path}',
                              feedback: Material(
                                elevation: 8,
                                color: Colors.transparent,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(8)),
                                  child: Text('Uploading: $filename', style: AppTextStyles.bodyMedium),
                                ),
                              ),
                              childWhenDragging: Opacity(opacity: 0.5, child: listTile),
                              child: listTile,
                            );
                          }
                          return listTile;
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRemoteView(BuildContext context) {
    final state = ref.watch(sftpProvider(widget.profile));
    final notifier = ref.read(sftpProvider(widget.profile).notifier);
    final localState = ref.read(localFileProvider);
    final localNotifier = ref.read(localFileProvider.notifier);

    return DropTarget(
      onDragDone: (detail) async {
        if (detail.files.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploading ${detail.files.length} files...')));
          for (var xFile in detail.files) {
            await notifier.uploadFile(xFile.path, xFile.name);
          }
        }
      },
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data.startsWith('local|'),
        onAcceptWithDetails: (details) async {
          // Received from Local
          final localPath = details.data.substring(6);
          final filename = p.basename(localPath);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploading $filename...')));
          await notifier.uploadFile(localPath, filename);
        },
        builder: (context, candidateData, rejectedData) {
          return Column(
            children: [
              _buildPathBar(
                path: state.currentPath,
                onUp: notifier.navigateUp,
                onRefresh: () => notifier.loadDirectory(state.currentPath),
                title: 'Remote Server',
                highlight: candidateData.isNotEmpty,
              ),
              if (state.error != null && state.error!.isNotEmpty) _buildErrorBar(state.error!),
              Expanded(
                child: state.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        itemCount: state.items.length,
                        itemBuilder: (context, index) {
                          final item = state.items[index];
                          final isDir = item.attr.isDirectory;
                          final filename = item.filename;

                          Widget listTile = ListTile(
                            leading: Icon(
                              isDir ? Icons.folder : Icons.cloud_circle,
                              color: isDir ? AppColors.subtleAmber : AppColors.electricCyan,
                            ),
                            title: Text(filename, style: AppTextStyles.bodyLarge),
                            subtitle: Text(isDir ? 'Directory' : _formatSize(item.attr.size ?? 0)),
                            trailing: isDir ? null : SizedBox(
                              width: 40,
                              child: PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                                onSelected: (val) async {
                                  if (val == 'download') {
                                    final localDest = p.join(localState.currentPath, filename);
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloading $filename to Local...')));
                                    await notifier.downloadFile(filename, localDest);
                                    await localNotifier.refresh();
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download complete'), backgroundColor: AppColors.phosphorGreen));
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'download', child: Text('Download to Local Workspace')),
                                ],
                              ),
                            ),
                            onTap: () {
                              if (isDir) {
                                String nextPath = state.currentPath == '/' ? '/$filename' : '${state.currentPath}/$filename';
                                if (state.currentPath == '.') nextPath = './$filename';
                                notifier.loadDirectory(nextPath);
                              }
                            },
                          );

                          if (!isDir) {
                            return Draggable<String>(
                              data: 'remote|$filename',
                              feedback: Material(
                                elevation: 8,
                                color: Colors.transparent,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(8)),
                                  child: Text('Downloading: $filename', style: AppTextStyles.bodyMedium),
                                ),
                              ),
                              childWhenDragging: Opacity(opacity: 0.5, child: listTile),
                              child: listTile,
                            );
                          }
                          return listTile;
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPathBar({
    required String path,
    required VoidCallback onUp,
    required VoidCallback onRefresh,
    required String title,
    IconData? actionIcon,
    String? actionTooltip,
    VoidCallback? onAction,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: highlight ? AppColors.electricCyan.withOpacity(0.1) : AppColors.surface1,
        border: Border(
          bottom: BorderSide(color: highlight ? AppColors.electricCyan : AppColors.surfaceBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
              const Spacer(),
              if (actionIcon != null && onAction != null)
                IconButton(
                  icon: Icon(actionIcon, size: 20, color: AppColors.electricCyan),
                  tooltip: actionTooltip,
                  onPressed: onAction,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
                onPressed: onRefresh,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 20, color: AppColors.textSecondary),
                onPressed: onUp,
                tooltip: 'Go Up',
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  path,
                  style: AppTextStyles.monoMedium.copyWith(color: AppColors.electricCyan),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBar(String error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      color: AppColors.softCrimson.withValues(alpha: 0.2),
      child: Text(
        error,
        style: const TextStyle(color: AppColors.softCrimson),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
