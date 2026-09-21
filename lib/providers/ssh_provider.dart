import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ssh_engine.dart';

final sshEngineProvider = Provider<SshEngine>((ref) {
  return SshEngine();
});
