class ConnectionProfile {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String authMethod; // 'password' | 'private_key'
  final String? privateKeyId;
  final int timeout;
  final int keepalive;
  final DateTime createdAt;
  final DateTime lastConnected;

  const ConnectionProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.authMethod = 'password',
    this.privateKeyId,
    this.timeout = 10000,
    this.keepalive = 0,
    required this.createdAt,
    required this.lastConnected,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'authMethod': authMethod,
      'privateKeyId': privateKeyId,
      'timeout': timeout,
      'keepalive': keepalive,
      'createdAt': createdAt.toIso8601String(),
      'lastConnected': lastConnected.toIso8601String(),
    };
  }

  factory ConnectionProfile.fromMap(Map<String, dynamic> map) {
    return ConnectionProfile(
      id: map['id'],
      name: map['name'],
      host: map['host'],
      port: map['port'],
      username: map['username'],
      authMethod: map['authMethod'],
      privateKeyId: map['privateKeyId'],
      timeout: map['timeout'],
      keepalive: map['keepalive'],
      createdAt: DateTime.parse(map['createdAt']),
      lastConnected: DateTime.parse(map['lastConnected']),
    );
  }

  ConnectionProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? authMethod,
    String? privateKeyId,
    int? timeout,
    int? keepalive,
    DateTime? createdAt,
    DateTime? lastConnected,
  }) {
    return ConnectionProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      privateKeyId: privateKeyId ?? this.privateKeyId,
      timeout: timeout ?? this.timeout,
      keepalive: keepalive ?? this.keepalive,
      createdAt: createdAt ?? this.createdAt,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }
}
