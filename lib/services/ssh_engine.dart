import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import '../models/connection_profile.dart';
import '../security/secure_storage.dart';

class SshSessionState {
  final ConnectionProfile profile;
  SSHClient? client;
  SSHSession? shell;
  bool isConnected = false;
  bool isConnecting = false;
  String? error;

  SshSessionState(this.profile);
}

class SshEngine {
  final SecureStorage _secureStorage = SecureStorage();
  
  // Mapping of profileId to active state
  final Map<String, SshSessionState> _activeSessions = {};

  SshSessionState? getSession(String profileId) => _activeSessions[profileId];

  List<SshSessionState> get activeSessions => _activeSessions.values.toList();

  Future<void> connect(ConnectionProfile profile) async {
    var state = _activeSessions[profile.id];
    
    if (state != null) {
      if (state.isConnected || state.isConnecting) {
        debugPrint('SSH_ENGINE: Already connecting/connected to ${profile.id}');
        return; 
      }
    } else {
      state = SshSessionState(profile);
      _activeSessions[profile.id] = state;
    }
    
    state.isConnecting = true;
    state.error = null;
    
    // YIELD TO UI THREAD: Prevents "Skipped 375 frames!" freezing during navigation transition
    await Future.delayed(const Duration(milliseconds: 400));
    
    try {
      final socket = await SSHSocket.connect(
        profile.host, 
        profile.port, 
        timeout: Duration(milliseconds: profile.timeout)
      );

      final pass = profile.authMethod == 'password' 
          ? await _secureStorage.getPassword(profile.id) 
          : null;
      
      final identities = await _getIdentities(profile);

      if (pass == null && identities.isEmpty) {
        throw Exception('No authentication credentials configured.');
      }

      state.client = SSHClient(
        socket,
        username: profile.username,
        keepAliveInterval: profile.keepalive > 0 ? Duration(seconds: profile.keepalive) : null,
        identities: identities,
        onPasswordRequest: (pass != null && pass.isNotEmpty)
            ? () => pass
            : null,
      );

      await state.client!.authenticated;
      state.isConnected = true;
      state.isConnecting = false;
      debugPrint('SSH_ENGINE: Authenticated successfully.');
      
    } catch (e, stackTrace) {
      debugPrint('SSH_ENGINE ERROR: $e');
      debugPrint('SSH_ENGINE STACK: $stackTrace');
      state.error = e.toString();
      state.isConnected = false;
      state.isConnecting = false;
      rethrow;
    }
  }

  Future<List<SSHKeyPair>> _getIdentities(ConnectionProfile profile) async {
    if (profile.authMethod == 'private_key' && profile.privateKeyId != null) {
      final pk = await _secureStorage.getPrivateKey(profile.privateKeyId!);
      final pass = await _secureStorage.getPassphrase(profile.privateKeyId!);
      if (pk != null) {
        return SSHKeyPair.fromPem(pk, pass);
      }
    }
    return [];
  }

  Future<SSHSession> startShell(String profileId, int cols, int rows) async {
    final state = _activeSessions[profileId];
    if (state == null || state.client == null) {
      throw Exception('Session not connected');
    }
    
    // PTY configuration for professional terminal layout
    state.shell = await state.client!.shell(
      pty: SSHPtyConfig(
        type: 'xterm-256color',
        width: cols, 
        height: rows, 
      )
    );
    
    return state.shell!;
  }
  
  Future<void> disconnect(String profileId) async {
    final state = _activeSessions[profileId];
    if (state != null) {
      state.client?.close();
      _activeSessions.remove(profileId);
    }
  }
  
  void disconnectAll() {
    for (var state in _activeSessions.values) {
      state.client?.close();
    }
    _activeSessions.clear();
  }
}
