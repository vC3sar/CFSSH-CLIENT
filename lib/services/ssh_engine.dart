import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import 'dart:convert';

import '../models/connection_profile.dart';
import '../security/secure_storage.dart';
import '../repositories/database_service.dart';
import '../services/host_key_manager.dart';

typedef HostKeyVerificationCallback = Future<bool> Function(
  String host,
  int port,
  String algorithm,
  String sha256Fingerprint,
  String md5Fingerprint,
  bool isChanged,
  String? oldFingerprint
);

enum SshSessionStatus { disconnected, connecting, connected, reconnecting, disconnecting, error }

class SshSessionState {
  final ConnectionProfile profile;
  SSHClient? client;
  SSHSession? shell;
  final Terminal terminal = Terminal(maxLines: 10000);
  
  SshSessionStatus status = SshSessionStatus.disconnected;
  
  bool get isConnected => status == SshSessionStatus.connected;
  bool get isConnecting => status == SshSessionStatus.connecting || status == SshSessionStatus.reconnecting;
  
  String? error;
  
  bool manualDisconnect = false;
  int reconnectAttempts = 0;
  int lastCols = 80;
  int lastRows = 24;

  SshSessionState(this.profile);
}

class SshEngine extends ChangeNotifier {
  final SecureStorage _secureStorage = SecureStorage();
  final HostKeyManager hostKeyManager;
  
  SshEngine({required this.hostKeyManager});
  
  // Mapping of profileId to active state
  final Map<String, SshSessionState> _activeSessions = {};

  SshSessionState? getSession(String profileId) => _activeSessions[profileId];

  SshSessionState getOrCreateSession(ConnectionProfile profile) {
    var state = _activeSessions[profile.id];
    if (state == null) {
      state = SshSessionState(profile);
      _activeSessions[profile.id] = state;
      // We don't notifyListeners here because it's typically called during initState
    }
    return state;
  }

  List<SshSessionState> get activeSessions => _activeSessions.values.toList();

  Future<void> connect(
    ConnectionProfile profile, {
    HostKeyVerificationCallback? onHostKeyVerification,
  }) async {
    var state = getOrCreateSession(profile);
    
    if (state.isConnecting || state.isConnected) {
      debugPrint('SSH_ENGINE: Already connecting/connected to ${profile.id}');
      return; 
    }
    
    state.manualDisconnect = false;
    state.status = SshSessionStatus.connecting;
    state.error = null;
    notifyListeners();
    
    // YIELD TO UI THREAD: Prevents freezing during navigation transition
    await Future.delayed(const Duration(milliseconds: 400));
    
    try {
      final socket = await SSHSocket.connect(
        profile.host, 
        profile.port, 
        timeout: Duration(milliseconds: profile.timeout)
      );

      final pass = profile.authMethod == 'password' 
          ? (await _secureStorage.getPassword(profile.id) ?? '')
          : null;
      
      final identities = await _getIdentities(profile);

      if (profile.authMethod == 'private_key' && identities.isEmpty) {
        throw Exception('No SSH Key selected or private key could not be loaded. Please assign a valid key in Servers.');
      }

      state.client = SSHClient(
        socket,
        username: profile.username,
        keepAliveInterval: profile.keepalive > 0 ? Duration(seconds: profile.keepalive) : null,
        identities: identities,
        onPasswordRequest: profile.authMethod == 'password'
            ? () => pass ?? ''
            : null,
        onVerifyHostKey: (String algorithm, Uint8List rawFingerprint) async {
          final sha256 = hostKeyManager.computeSHA256Fingerprint(rawFingerprint);
          final md5 = hostKeyManager.computeMD5Fingerprint(rawFingerprint);
          
          final trustedHost = await hostKeyManager.getTrustedHost(profile.host, profile.port);
          
          if (trustedHost != null) {
            if (trustedHost.fingerprint == sha256) {
              hostKeyManager.saveTrustedHost(profile.host, profile.port, algorithm, sha256);
              return true;
            } else {
              if (onHostKeyVerification != null) {
                return await onHostKeyVerification(
                  profile.host, profile.port, algorithm, sha256, md5, true, trustedHost.fingerprint
                );
              }
              return false;
            }
          } else {
            if (onHostKeyVerification != null) {
              return await onHostKeyVerification(
                profile.host, profile.port, algorithm, sha256, md5, false, null
              );
            }
            return false;
          }
        },
      );

      await state.client!.authenticated;
      state.status = SshSessionStatus.connected;
      state.reconnectAttempts = 0; // reset on success
      notifyListeners();
      debugPrint('SSH_ENGINE: Authenticated successfully.');
      
      // Auto-reconnect listener
      state.client!.done.whenComplete(() {
        if (!state.manualDisconnect && state.reconnectAttempts < 3) {
          _handleAutoReconnect(profile, onHostKeyVerification);
        } else if (!state.manualDisconnect && state.reconnectAttempts >= 3) {
          state.error = 'Connection lost. Max reconnect attempts reached.';
          state.status = SshSessionStatus.error;
          notifyListeners();
        }
      });
      
    } catch (e, stackTrace) {
      debugPrint('SSH_ENGINE ERROR: $e');
      debugPrint('SSH_ENGINE STACK: $stackTrace');
      state.error = e.toString();
      state.status = SshSessionStatus.error;
      notifyListeners();
      // Do not rethrow; we handled it by updating the UI state safely.
    }
  }

  void _handleAutoReconnect(ConnectionProfile profile, HostKeyVerificationCallback? onHostKeyVerification) {
    final state = _activeSessions[profile.id];
    if (state == null || state.manualDisconnect || state.status == SshSessionStatus.reconnecting) return;

    state.reconnectAttempts++;
    state.status = SshSessionStatus.reconnecting;
    state.error = 'Connection lost. Reconnecting (Attempt ${state.reconnectAttempts}/3)...';
    notifyListeners();

    debugPrint('SSH_ENGINE: Auto-reconnecting ${profile.id}, attempt ${state.reconnectAttempts}');

    Future.delayed(const Duration(seconds: 3), () async {
      try {
        await connect(profile, onHostKeyVerification: onHostKeyVerification);
        
        final newState = _activeSessions[profile.id];
        if (newState != null && newState.isConnected && newState.shell != null) {
           newState.shell = null; // force recreation
           await startShell(profile.id, newState.lastCols, newState.lastRows);
           newState.terminal.write('\r\n\x1B[1;32m--- Reconnected automatically ---\x1B[0m\r\n');
        }
      } catch (e) {
        debugPrint('SSH_ENGINE: Auto-reconnect failed: $e');
        final failedState = _activeSessions[profile.id];
        if (failedState != null && !failedState.manualDisconnect && failedState.reconnectAttempts < 3) {
           // Wait and try again
           Future.delayed(const Duration(seconds: 2), () {
             if (!failedState.manualDisconnect) {
               failedState.status = SshSessionStatus.disconnected; // Reset so reconnect can trigger
               _handleAutoReconnect(profile, onHostKeyVerification);
             }
           });
        } else if (failedState != null) {
           failedState.error = 'Connection lost. Auto-reconnect failed.';
           failedState.status = SshSessionStatus.error;
           notifyListeners();
        }
      }
    });
  }

  Future<List<SSHKeyPair>> _getIdentities(ConnectionProfile profile) async {
    debugPrint('SSH_ENGINE: _getIdentities for "${profile.name}" (authMethod: ${profile.authMethod}, keyId: ${profile.privateKeyId})');
    if (profile.authMethod == 'private_key') {
      // 1. Attempt to load the specifically selected key if provided
      if (profile.privateKeyId != null) {
        final pk = await _secureStorage.getPrivateKey(profile.privateKeyId!);
        final pass = await _secureStorage.getPassphrase(profile.privateKeyId!);
        if (pk != null) {
          try {
            final keys = SSHKeyPair.fromPem(pk, pass);
            if (keys.isNotEmpty) {
              debugPrint('SSH_ENGINE: Loaded ${keys.length} identity(ies) for specified keyId: ${profile.privateKeyId}');
              return keys;
            }
          } catch (e, st) {
            debugPrint('SSH_ENGINE ERROR parsing primary keyId ${profile.privateKeyId}: $e\n$st');
          }
        }
      }

      final allKeys = await DatabaseService.instance.getAllSshKeys();
      debugPrint('SSH_ENGINE: Attempting fallback with all saved SSH keys in Key Manager (count: ${allKeys.length}).');
      final List<SSHKeyPair> fallbackIdentities = [];
      for (final keyModel in allKeys) {
        final pk = await _secureStorage.getPrivateKey(keyModel.id);
        final pass = await _secureStorage.getPassphrase(keyModel.id);
        if (pk != null) {
          try {
            await Future.delayed(Duration.zero); // YIELD TO UI THREAD: Prevents skipped frames during heavy crypto parsing
            final parsed = SSHKeyPair.fromPem(pk, pass);
            fallbackIdentities.addAll(parsed);
          } catch (e) {
            debugPrint('SSH_ENGINE ERROR parsing fallback key "${keyModel.name}": $e');
          }
        }
      }
      if (fallbackIdentities.isNotEmpty) {
        debugPrint('SSH_ENGINE: Successfully loaded ${fallbackIdentities.length} fallback SSH key identity(ies).');
        return fallbackIdentities;
      }
    }
    return [];
  }

  Future<SSHSession> startShell(String profileId, int cols, int rows) async {
    final state = _activeSessions[profileId];
    if (state == null || state.client == null) {
      throw Exception('Session not connected');
    }
    
    // If shell is already active, just return it and resize
    if (state.shell != null) {
      state.shell!.resizeTerminal(cols, rows, cols * 8, rows * 16);
      return state.shell!;
    }

    state.lastCols = cols;
    state.lastRows = rows;

    // PTY configuration for professional terminal layout
    state.shell = await state.client!.shell(
      pty: SSHPtyConfig(
        type: 'xterm-256color',
        width: cols, 
        height: rows, 
      )
    );
    
    // Attach stream listeners only once
    state.shell!.stdout.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen((String text) {
      state.terminal.write(text);
    });

    state.shell!.stderr.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen((String text) {
      state.terminal.write(text);
    });
    
    return state.shell!;
  }
  
  Future<void> disposeSession(String profileId) async {
    final state = _activeSessions[profileId];
    if (state != null) {
      state.manualDisconnect = true;
      try {
        state.client?.close();
      } catch (_) {}
      state.status = SshSessionStatus.disconnected;
      _activeSessions.remove(profileId);
      notifyListeners();
    }
  }

  Future<void> disconnect(String profileId) async {
    final state = _activeSessions[profileId];
    if (state != null) {
      state.manualDisconnect = true;
      state.status = SshSessionStatus.disconnecting;
      notifyListeners();
      
      try {
        state.client?.close();
      } catch (_) {}
      
      state.status = SshSessionStatus.disconnected;
      notifyListeners();
    }
  }
  
  void disconnectAll() {
    for (var state in _activeSessions.values) {
      state.manualDisconnect = true;
      state.status = SshSessionStatus.disconnected;
      try {
        state.client?.close();
      } catch (_) {}
    }
    _activeSessions.clear();
    notifyListeners();
  }
}
