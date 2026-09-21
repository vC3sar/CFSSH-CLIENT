import 'package:uuid/uuid.dart';

class ConnectionHistory {
  final String id;
  final String profileId;
  final DateTime timestamp;

  ConnectionHistory({
    String? id,
    required this.profileId,
    required this.timestamp,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'profileId': profileId,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ConnectionHistory.fromMap(Map<String, dynamic> map) {
    return ConnectionHistory(
      id: map['id'],
      profileId: map['profileId'],
      timestamp: DateTime.parse(map['timestamp']),
    );
  }
}
