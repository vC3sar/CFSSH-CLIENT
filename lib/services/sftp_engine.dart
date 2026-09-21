import 'package:dartssh2/dartssh2.dart';
import 'ssh_engine.dart';

class SftpEngine {
  final SshEngine sshEngine;

  SftpEngine(this.sshEngine);

  Future<SftpClient> getSftpClient(String profileId) async {
    final sessionState = sshEngine.getSession(profileId);
    if (sessionState == null || sessionState.client == null) {
      throw Exception('SSH session not active for SFTP');
    }
    
    return await sessionState.client!.sftp();
  }

  Future<List<SftpName>> listDirectory(String profileId, String path) async {
    final sftp = await getSftpClient(profileId);
    return await sftp.listdir(path);
  }

  // Future additions for upload, download, streaming, etc.
}
