class SshKeyModel {
  final String id;
  final String name;
  final String keyType; // 'ED25519', 'RSA_2048', 'RSA_4096', 'ECDSA'
  final String publicKey;
  final String fingerprint;
  final DateTime createdAt;

  const SshKeyModel({
    required this.id,
    required this.name,
    required this.keyType,
    required this.publicKey,
    required this.fingerprint,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'keyType': keyType,
      'publicKey': publicKey,
      'fingerprint': fingerprint,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory SshKeyModel.fromMap(Map<String, dynamic> map) {
    return SshKeyModel(
      id: map['id'],
      name: map['name'],
      keyType: map['keyType'],
      publicKey: map['publicKey'],
      fingerprint: map['fingerprint'],
      createdAt: DateTime.parse(map['createdAt']),
    );
  }

  SshKeyModel copyWith({
    String? id,
    String? name,
    String? keyType,
    String? publicKey,
    String? fingerprint,
    DateTime? createdAt,
  }) {
    return SshKeyModel(
      id: id ?? this.id,
      name: name ?? this.name,
      keyType: keyType ?? this.keyType,
      publicKey: publicKey ?? this.publicKey,
      fingerprint: fingerprint ?? this.fingerprint,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
