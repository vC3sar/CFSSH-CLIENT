import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:dartssh2/dartssh2.dart';
import '../models/connection_profile.dart';
import '../providers/ssh_provider.dart';
import '../services/ssh_engine.dart';
import '../services/sftp_engine.dart';

final sftpEngineProvider = Provider<SftpEngine>((ref) {
  final sshEngine = ref.watch(sshEngineProvider);
  return SftpEngine(sshEngine);
});

class SftpState {
  final String currentPath;
  final List<SftpName> items;
  final bool isLoading;
  final String? error;

  SftpState({
    this.currentPath = '.',
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  SftpState copyWith({
    String? currentPath,
    List<SftpName>? items,
    bool? isLoading,
    String? error,
  }) {
    return SftpState(
      currentPath: currentPath ?? this.currentPath,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class SftpNotifier extends StateNotifier<SftpState> {
  final ConnectionProfile profile;
  final Ref ref;
  late SftpEngine _sftpEngine;
  late SshEngine _sshEngine;
  SftpClient? _sftpClient;

  SftpNotifier(this.profile, this.ref) : super(SftpState(isLoading: true)) {
    _sftpEngine = ref.read(sftpEngineProvider);
    _sshEngine = ref.read(sshEngineProvider);
  }

  Future<void> connectAndLoad({HostKeyVerificationCallback? onHostKeyVerification}) async {
    try {
      state = state.copyWith(isLoading: true, error: '');
      
      var session = _sshEngine.getSession(profile.id);
      if (session == null || !session.isConnected) {
        await _sshEngine.connect(profile, onHostKeyVerification: onHostKeyVerification);
      }
      
      _sftpClient = await _sftpEngine.getSftpClient(profile.id);
      
      String startPath = state.currentPath;
      if (startPath == '.') {
        try {
          await _sftpClient!.stat('.');
        } catch (_) {}
      }
      
      await loadDirectory(startPath);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<void> loadDirectory(String path) async {
    if (_sftpClient == null) return;
    
    try {
      state = state.copyWith(isLoading: true, error: '');
      final items = await _sftpClient!.listdir(path);
      
      items.sort((a, b) {
        final aIsDir = a.attr.isDirectory;
        final bIsDir = b.attr.isDirectory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
      });
      
      state = state.copyWith(
        currentPath: path,
        items: items.where((i) => i.filename != '.' && i.filename != '..').toList(),
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to load $path: $e', isLoading: false);
    }
  }

  Future<void> navigateUp() async {
    if (state.currentPath == '/' || state.currentPath == '.') return;
    
    List<String> parts = state.currentPath.split('/');
    parts.removeWhere((p) => p.isEmpty);
    if (parts.isNotEmpty) parts.removeLast();
    
    String newPath = '/${parts.join('/')}';
    if (newPath == '/') newPath = '/';
    if (state.currentPath == '.' && parts.isEmpty) newPath = '.';
    
    await loadDirectory(newPath);
  }

  Future<void> uploadFile(String localFilePath, String fileName) async {
    if (_sftpClient == null) return;
    try {
      state = state.copyWith(isLoading: true, error: '');
      
      final remotePath = '${state.currentPath}/$fileName';
      final file = File(localFilePath);
      final remoteFile = await _sftpClient!.open(remotePath, mode: SftpFileOpenMode.create | SftpFileOpenMode.write);
      
      final stream = file.openRead();
      await remoteFile.write(stream.cast<Uint8List>());
      await remoteFile.close();
      
      await loadDirectory(state.currentPath);
    } catch (e) {
      state = state.copyWith(error: 'Upload failed: $e', isLoading: false);
    }
  }

  Future<void> downloadFile(String remoteFileName, String localFilePath) async {
    if (_sftpClient == null) return;
    try {
      state = state.copyWith(isLoading: true, error: '');
      
      final remotePath = '${state.currentPath}/$remoteFileName';
      final remoteFile = await _sftpClient!.open(remotePath, mode: SftpFileOpenMode.read);
      
      final localFile = File(localFilePath);
      final sink = localFile.openWrite();
      
      await for (var chunk in remoteFile.read()) {
        sink.add(chunk);
      }
      
      await sink.flush();
      await sink.close();
      await remoteFile.close();
      
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(error: 'Download failed: $e', isLoading: false);
    }
  }
}

final sftpProvider = StateNotifierProvider.autoDispose.family<SftpNotifier, SftpState, ConnectionProfile>((ref, profile) {
  return SftpNotifier(profile, ref);
});
