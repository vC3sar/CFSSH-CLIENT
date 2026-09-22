import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/trusted_host.dart';
import '../repositories/database_service.dart';

final hostKeyManagerProvider = Provider<HostKeyManager>((ref) {
  return HostKeyManager();
});

class HostKeyManager {
  final DatabaseService _db = DatabaseService.instance;

  /// Generates the SHA256 fingerprint of a raw host key blob.
  /// Format: SHA256:xxxxxxxxxxxxxxxxxxxxxxxxx (base64 without padding)
  String computeSHA256Fingerprint(Uint8List rawKeyBlob) {
    final hash = sha256.convert(rawKeyBlob);
    final base64Hash = base64.encode(hash.bytes).replaceAll('=', '');
    return 'SHA256:$base64Hash';
  }

  /// Generates the MD5 fingerprint of a raw host key blob.
  /// Format: xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
  String computeMD5Fingerprint(Uint8List rawKeyBlob) {
    final hash = md5.convert(rawKeyBlob);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
  }

  /// Retrieves the trusted host key for a given host and port.
  Future<TrustedHost?> getTrustedHost(String host, int port) async {
    return await _db.getTrustedHost(host, port);
  }

  /// Saves or updates a host key as trusted.
  Future<void> saveTrustedHost(String host, int port, String algorithm, String fingerprint) async {
    final existing = await _db.getTrustedHost(host, port);
    
    final newTrustedHost = TrustedHost(
      id: existing?.id,
      host: host,
      port: port,
      algorithm: algorithm,
      fingerprint: fingerprint,
      createdAt: existing?.createdAt ?? DateTime.now(),
      lastUsedAt: DateTime.now(),
    );
    
    await _db.insertTrustedHost(newTrustedHost);
  }

  /// Gets all trusted hosts.
  Future<List<TrustedHost>> getAllTrustedHosts() async {
    return await _db.getAllTrustedHosts();
  }

  /// Revokes trust for a host key.
  Future<void> deleteTrustedHost(String id) async {
    await _db.deleteTrustedHost(id);
  }
}
