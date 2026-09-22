import 'package:uuid/uuid.dart';

class TrustedHost {
  final String id;
  final String host;
  final int port;
  final String algorithm;
  final String fingerprint;
  final DateTime createdAt;
  final DateTime lastUsedAt;

  TrustedHost({
    String? id,
    required this.host,
    required this.port,
    required this.algorithm,
    required this.fingerprint,
    DateTime? createdAt,
    DateTime? lastUsedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        lastUsedAt = lastUsedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'host': host,
      'port': port,
      'algorithm': algorithm,
      'fingerprint': fingerprint,
      'createdAt': createdAt.toIso8601String(),
      'lastUsedAt': lastUsedAt.toIso8601String(),
    };
  }

  factory TrustedHost.fromMap(Map<String, dynamic> map) {
    return TrustedHost(
      id: map['id'],
      host: map['host'],
      port: map['port'],
      algorithm: map['algorithm'],
      fingerprint: map['fingerprint'],
      createdAt: DateTime.parse(map['createdAt']),
      lastUsedAt: DateTime.parse(map['lastUsedAt']),
    );
  }

  TrustedHost copyWith({
    String? host,
    int? port,
    String? algorithm,
    String? fingerprint,
    DateTime? lastUsedAt,
  }) {
    return TrustedHost(
      id: id,
      host: host ?? this.host,
      port: port ?? this.port,
      algorithm: algorithm ?? this.algorithm,
      fingerprint: fingerprint ?? this.fingerprint,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }
}
