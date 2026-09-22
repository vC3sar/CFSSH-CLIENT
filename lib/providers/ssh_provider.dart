import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ssh_engine.dart';

import '../services/host_key_manager.dart';

final sshEngineProvider = Provider<SshEngine>((ref) {
  final hostKeyManager = ref.read(hostKeyManagerProvider);
  return SshEngine(hostKeyManager: hostKeyManager);
});
