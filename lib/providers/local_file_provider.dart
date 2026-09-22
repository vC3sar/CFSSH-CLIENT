import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';

class LocalFileState {
  final String currentPath;
  final String rootPath;
  final List<FileSystemEntity> items;
  final bool isLoading;
  final String? error;

  LocalFileState({
    required this.currentPath,
    required this.rootPath,
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  LocalFileState copyWith({
    String? currentPath,
    String? rootPath,
    List<FileSystemEntity>? items,
    bool? isLoading,
    String? error,
  }) {
    return LocalFileState(
      currentPath: currentPath ?? this.currentPath,
      rootPath: rootPath ?? this.rootPath,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class LocalFileNotifier extends StateNotifier<LocalFileState> {
  LocalFileNotifier() : super(LocalFileState(currentPath: '/', rootPath: '/')) {
    _init();
  }

  Future<void> _init() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final directory = await getApplicationDocumentsDirectory();
      // Ensure the "CFSSH_Local" directory exists inside documents
      final localWorkspace = Directory(p.join(directory.path, 'CFSSH_Local'));
      if (!await localWorkspace.exists()) {
        await localWorkspace.create(recursive: true);
      }
      
      state = state.copyWith(
        currentPath: localWorkspace.path,
        rootPath: localWorkspace.path,
      );
      await loadDirectory(localWorkspace.path);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to initialize local workspace: $e');
    }
  }

  Future<void> loadDirectory(String path) async {
    state = state.copyWith(isLoading: true, error: null, currentPath: path);
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        throw Exception('Directory does not exist');
      }

      final List<FileSystemEntity> entities = await dir.list().toList();
      
      // Sort: Folders first, then files
      entities.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });

      state = state.copyWith(items: entities, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Error reading directory: $e');
    }
  }

  Future<void> navigateUp() async {
    if (state.currentPath == state.rootPath || p.equals(state.currentPath, state.rootPath)) {
      return; // Can't go above root
    }
    final parentDir = Directory(state.currentPath).parent;
    await loadDirectory(parentDir.path);
  }

  Future<void> createFolder(String name) async {
    try {
      final newDir = Directory(p.join(state.currentPath, name));
      await newDir.create();
      await loadDirectory(state.currentPath);
    } catch (e) {
      state = state.copyWith(error: 'Failed to create folder: $e');
    }
  }

  Future<void> deleteEntity(FileSystemEntity entity) async {
    try {
      if (entity is Directory) {
        await entity.delete(recursive: true);
      } else {
        await entity.delete();
      }
      await loadDirectory(state.currentPath);
    } catch (e) {
      state = state.copyWith(error: 'Failed to delete: $e');
    }
  }
  
  Future<void> refresh() async {
    await loadDirectory(state.currentPath);
  }

  Future<void> importFromSaf() async {
    try {
      final result = await FilePicker.pickFiles(); // removed allowMultiple
      if (result.isNotEmpty) {
        state = state.copyWith(isLoading: true);
        for (var file in result) {
          if (file.path != null) {
            final sourceFile = File(file.path!);
            final destPath = p.join(state.currentPath, file.name);
            await sourceFile.copy(destPath);
          }
        }
        await loadDirectory(state.currentPath);
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to import files: $e', isLoading: false);
    }
  }

  Future<void> exportToSaf(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final resultUri = await FilePicker.saveFile(
        dialogTitle: 'Export ${p.basename(file.path)}',
        fileName: p.basename(file.path),
        bytes: bytes,
      );
      if (resultUri != null) {
        debugPrint('File exported to $resultUri');
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to export file: $e');
    }
  }
}

final localFileProvider = StateNotifierProvider<LocalFileNotifier, LocalFileState>((ref) {
  return LocalFileNotifier();
});
