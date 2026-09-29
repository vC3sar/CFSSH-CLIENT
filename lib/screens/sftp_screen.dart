import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:path_provider/path_provider.dart';

import 'file_editor_screen.dart';

import '../models/connection_profile.dart';
import '../providers/sftp_provider.dart';
import '../providers/local_file_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/host_key_dialogs.dart';

class SftpScreen extends ConsumerStatefulWidget {
  final ConnectionProfile profile;
  final bool isEmbedded;

  const SftpScreen({super.key, required this.profile, this.isEmbedded = false});

  @override
  ConsumerState<SftpScreen> createState() => _SftpScreenState();
}

class _SftpScreenState extends ConsumerState<SftpScreen> {
  bool? _isVerticalLayout;

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
    return Scaffold(
      backgroundColor: AppColors.canvasBase,
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: Row(
                children: [
                  const Icon(Icons.folder_shared, color: AppColors.electricCyan),
                  const SizedBox(width: 8),
                  Expanded(child: Text(widget.profile.name, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;
            final useVertical = _isVerticalLayout ?? !isWide;
            
            if (!useVertical) {
              return Row(
                children: [
                  Expanded(child: _buildLocalView(context)),
                  Container(width: 1, color: AppColors.surfaceBorder),
                  Expanded(child: _buildRemoteView(context)),
                ],
              );
            } else {
              return Column(
                children: [
                  Expanded(child: _buildLocalView(context)),
                  Container(height: 1, color: AppColors.surfaceBorder),
                  Expanded(child: _buildRemoteView(context)),
                ],
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _uploadWithPrompt(String localPath, String remoteFilename, String remoteDir) async {
    final notifier = ref.read(sftpProvider(widget.profile).notifier);
    final remotePath = '$remoteDir/$remoteFilename'.replaceAll('//', '/');
    if (await notifier.fileExists(remotePath)) {
      final bool? overwrite = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface1,
          title: const Text('Sobreescribir Archivo'),
          content: Text('El archivo "$remoteFilename" ya existe en el servidor. ¿Deseas sobreescribirlo?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Omitir')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.electricCyan, foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sobreescribir'),
            ),
          ],
        ),
      );
      if (overwrite != true) return;
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Subiendo $remoteFilename...')));
    await notifier.uploadFileToExactPath(localPath, remotePath);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subida completada'), backgroundColor: AppColors.phosphorGreen));
  }

  void _openExternal(String filePath) {
    if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '""', filePath]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [filePath]);
    } else if (Platform.isMacOS) {
      Process.run('open', [filePath]);
    }
  }

  void _editLocalFile(String localPath, String filename) {
    final remoteNotifier = ref.read(sftpProvider(widget.profile).notifier);
    final remoteState = ref.read(sftpProvider(widget.profile));
    Navigator.push(context, MaterialPageRoute(builder: (_) => FileEditorScreen(
      file: File(localPath),
      remotePath: '${remoteState.currentPath}/$filename'.replaceAll('//', '/'),
      filename: filename,
      onSave: (local, remote) async {
        return await remoteNotifier.uploadFileToExactPath(local, remote);
      },
    )));
  }

  Future<void> _editRemoteFile(String filename, String currentPath) async {
    final notifier = ref.read(sftpProvider(widget.profile).notifier);
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(p.join(tempDir.path, filename));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Descargando para editar...')));
    await notifier.downloadFile(filename, tempFile.path);
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => FileEditorScreen(
        file: tempFile,
        remotePath: '$currentPath/$filename'.replaceAll('//', '/'),
        filename: filename,
        onSave: (local, remote) async {
          return await notifier.uploadFileToExactPath(local, remote);
        },
      )));
    }
  }

  Future<String?> _showInputDialog(String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface1,
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nombre...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.electricCyan, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Crear'),
          ),
        ],
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
                onPathChanged: (newPath) => notifier.loadDirectory(newPath),
                onUp: notifier.navigateUp,
                onRefresh: notifier.refresh,
                title: 'Local Workspace',
                highlight: candidateData.isNotEmpty,
                extraActions: [
                  IconButton(
                    icon: Icon((_isVerticalLayout ?? !(MediaQuery.of(context).size.width > 700)) ? Icons.view_column : Icons.view_agenda, size: 20, color: AppColors.subtleAmber),
                    tooltip: 'Cambiar Diseño (Lado a lado / Arriba y Abajo)',
                    onPressed: () {
                      setState(() {
                        final current = _isVerticalLayout ?? !(MediaQuery.of(context).size.width > 700);
                        _isVerticalLayout = !current;
                      });
                    },
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_to_drive, size: 20, color: AppColors.electricCyan),
                    tooltip: 'Import from Phone (SAF)',
                    onPressed: notifier.importFromSaf,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                ],
              ),
              if (state.error != null) _buildErrorBar(state.error!),
              Expanded(
                child: state.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onSecondaryTapUp: (details) {
                          showMenu<String>(
                            context: context,
                            position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy, details.globalPosition.dx, details.globalPosition.dy),
                            items: [
                              const PopupMenuItem(value: 'refresh', child: Text('Actualizar')),
                              const PopupMenuItem(value: 'new_folder', child: Text('Nueva Carpeta')),
                              const PopupMenuItem(value: 'new_file', child: Text('Nuevo Archivo')),
                            ],
                          ).then((val) async {
                            if (val == 'refresh') {
                              notifier.refresh();
                            } else if (val == 'new_folder') {
                              final name = await _showInputDialog('Nombre de la Carpeta');
                              if (name != null && name.isNotEmpty) await notifier.createFolder(name);
                            } else if (val == 'new_file') {
                              final name = await _showInputDialog('Nombre del Archivo');
                              if (name != null && name.isNotEmpty) await notifier.createFile(name);
                            }
                          });
                        },
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          itemCount: state.items.length,
                          itemBuilder: (context, index) {
                            final item = state.items[index];
                            final isDir = item is Directory;
                            final filename = p.basename(item.path);
                            
                            
                            void showLocalItemMenu(TapUpDetails details) {
                              showMenu<String>(
                                context: context,
                                position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy, details.globalPosition.dx, details.globalPosition.dy),
                                items: [
                                  const PopupMenuItem(value: 'upload', child: Text('Subir al Remoto')),
                                  if (!isDir) const PopupMenuItem(value: 'edit', child: Text('Editar Archivo')),
                                  if (!isDir) const PopupMenuItem(value: 'external', child: Text('Abrir Externamente')),
                                  if (!isDir) const PopupMenuItem(value: 'export', child: Text('Export File (SAF)')),
                                  const PopupMenuItem(value: 'delete', child: Text('Delete Local', style: TextStyle(color: AppColors.softCrimson))),
                                ],
                              ).then((val) async {
                                if (val == 'upload') {
                                  final remoteState = ref.read(sftpProvider(widget.profile));
                                  await _uploadWithPrompt(item.path, filename, remoteState.currentPath);
                                } else if (val == 'edit') {
                                  _editLocalFile(item.path, filename);
                                } else if (val == 'external') {
                                  _openExternal(item.path);
                                } else if (val == 'export') {
                                  await notifier.exportToSaf(item as File);
                                } else if (val == 'delete') {
                                  await notifier.deleteEntity(item);
                                }
                              });
                            }

                            Widget listTile = GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onSecondaryTapUp: showLocalItemMenu,
                              child: InkWell(
                                onTapUp: showLocalItemMenu,
                                onDoubleTap: () {
                                  if (isDir) {
                                    notifier.loadDirectory(item.path);
                                  } else {
                                    _editLocalFile(item.path, filename);
                                  }
                                },
                                child: ListTile(
                                  enabled: true,
                                  leading: Icon(
                                    isDir ? Icons.folder : Icons.insert_drive_file,
                                    color: isDir ? AppColors.subtleAmber : AppColors.textSecondary,
                                  ),
                                  title: Text(filename, style: AppTextStyles.bodyLarge),
                                  subtitle: Text(isDir ? 'Directory' : _formatSize(File(item.path).lengthSync())),
                                  trailing: isDir ? null : const Icon(Icons.more_vert, color: AppColors.textSecondary),
                                ),
                              ),
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
          await _uploadWithPrompt(localPath, filename, state.currentPath);
        },
        builder: (context, candidateData, rejectedData) {
          return Column(
            children: [
              _buildPathBar(
                path: state.currentPath,
                onPathChanged: (newPath) => notifier.loadDirectory(newPath),
                onUp: notifier.navigateUp,
                onRefresh: () => notifier.loadDirectory(state.currentPath),
                title: 'Remote Server',
                highlight: candidateData.isNotEmpty,
              ),
              if (state.error != null && state.error!.isNotEmpty) _buildErrorBar(state.error!),
              Expanded(
                child: state.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onSecondaryTapUp: (details) {
                          showMenu<String>(
                            context: context,
                            position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy, details.globalPosition.dx, details.globalPosition.dy),
                            items: [
                              const PopupMenuItem(value: 'refresh', child: Text('Actualizar')),
                              const PopupMenuItem(value: 'new_folder', child: Text('Nueva Carpeta')),
                              const PopupMenuItem(value: 'new_file', child: Text('Nuevo Archivo')),
                            ],
                          ).then((val) async {
                            if (val == 'refresh') {
                              notifier.loadDirectory(state.currentPath);
                            } else if (val == 'new_folder') {
                              final name = await _showInputDialog('Nombre de la Carpeta');
                              if (name != null && name.isNotEmpty) await notifier.createDirectory(name);
                            } else if (val == 'new_file') {
                              final name = await _showInputDialog('Nombre del Archivo');
                              if (name != null && name.isNotEmpty) await notifier.createFile(name);
                            }
                          });
                        },
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          itemCount: state.items.length,
                          itemBuilder: (context, index) {
                            final item = state.items[index];
                            final isDir = item.attr.isDirectory;
                            final filename = item.filename;

                            void showRemoteItemMenu(TapUpDetails details) {
                              showMenu<String>(
                                context: context,
                                position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy, details.globalPosition.dx, details.globalPosition.dy),
                                items: [
                                  if (!isDir) const PopupMenuItem(value: 'download', child: Text('Descargar Localmente')),
                                  if (!isDir) const PopupMenuItem(value: 'edit', child: Text('Editar Archivo')),
                                  if (!isDir) const PopupMenuItem(value: 'external', child: Text('Abrir Externamente')),
                                ],
                              ).then((val) async {
                                if (val == 'download') {
                                  final localDest = p.join(localState.currentPath, filename);
                                  if (File(localDest).existsSync()) {
                                    final bool? overwrite = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        backgroundColor: AppColors.surface1,
                                        title: const Text('Sobreescribir Archivo'),
                                        content: Text('El archivo "$filename" ya existe localmente. ¿Deseas sobreescribirlo?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Omitir')),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.electricCyan, foregroundColor: Colors.black),
                                            onPressed: () => Navigator.pop(context, true),
                                            child: const Text('Sobreescribir'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (overwrite != true) return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Descargando $filename...')));
                                  await notifier.downloadFile(filename, localDest);
                                  await localNotifier.refresh();
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Descarga completada'), backgroundColor: AppColors.phosphorGreen));
                                } else if (val == 'edit') {
                                  await _editRemoteFile(filename, state.currentPath);
                                } else if (val == 'external') {
                                  final tempDir = await getTemporaryDirectory();
                                  final tempFile = File(p.join(tempDir.path, filename));
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Descargando para abrir...')));
                                  await notifier.downloadFile(filename, tempFile.path);
                                  _openExternal(tempFile.path);
                                }
                              });
                            }

                            Widget listTile = GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onSecondaryTapUp: showRemoteItemMenu,
                              child: InkWell(
                                onTapUp: showRemoteItemMenu,
                                onDoubleTap: () async {
                                  if (isDir) {
                                    String nextPath = state.currentPath == '/' ? '/$filename' : '${state.currentPath}/$filename';
                                    if (state.currentPath == '.') nextPath = './$filename';
                                    notifier.loadDirectory(nextPath);
                                  } else {
                                    await _editRemoteFile(filename, state.currentPath);
                                  }
                                },
                                child: ListTile(
                                  enabled: true,
                                  leading: Icon(
                                    isDir ? Icons.folder : Icons.cloud_circle,
                                    color: isDir ? AppColors.subtleAmber : AppColors.electricCyan,
                                  ),
                                  title: Text(filename, style: AppTextStyles.bodyLarge),
                                  subtitle: Text(isDir ? 'Directory' : _formatSize(item.attr.size ?? 0)),
                                  trailing: isDir ? null : const Icon(Icons.more_vert, color: AppColors.textSecondary),
                                ),
                              ),
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
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPathBar({
    required String path,
    required void Function(String) onPathChanged,
    required VoidCallback onUp,
    required VoidCallback onRefresh,
    required String title,
    List<Widget>? extraActions,
    bool highlight = false,
  }) {
    final controller = TextEditingController(text: path);
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
              if (extraActions != null) ...extraActions,
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
                child: TextField(
                  controller: controller,
                  style: AppTextStyles.monoMedium.copyWith(color: AppColors.electricCyan),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onSubmitted: (newPath) {
                    if (newPath.isNotEmpty) {
                      onPathChanged(newPath);
                    }
                  },
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
