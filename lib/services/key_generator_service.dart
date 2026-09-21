import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';

class GeneratedKeyResult {
  final String privateKeyPem;
  final String publicKeyOpenSSH;
  final String fingerprint;
  final String keyType;

  GeneratedKeyResult({
    required this.privateKeyPem,
    required this.publicKeyOpenSSH,
    required this.fingerprint,
    required this.keyType,
  });
}

class KeyGeneratorService {
  /// Parses an imported or generated private key PEM / OpenSSH string to validate and extract key details.
  static GeneratedKeyResult parsePrivateKey(String pemOrOpenSSH, {String? passphrase, String? comment}) {
    final keyPairs = SSHKeyPair.fromPem(pemOrOpenSSH, passphrase);
    if (keyPairs.isEmpty) {
      throw Exception('Invalid or unsupported SSH private key format.');
    }
    final keyPair = keyPairs.first;
    final publicKey = _extractPublicKey(keyPair, comment: comment ?? 'cfssh-user');
    final fingerprint = calculateFingerprint(publicKey);
    final keyType = _determineKeyType(pemOrOpenSSH, keyPair);

    return GeneratedKeyResult(
      privateKeyPem: pemOrOpenSSH,
      publicKeyOpenSSH: publicKey,
      fingerprint: fingerprint,
      keyType: keyType,
    );
  }

  /// Formats the SSHKeyPair into an OpenSSH public key line.
  static String _extractPublicKey(SSHKeyPair keyPair, {String comment = 'cfssh'}) {
    try {
      final pem = keyPair.toPem();
      final digest = sha256.convert(utf8.encode(pem));
      final b64 = base64.encode(digest.bytes);
      final keyTypeStr = _determineKeyType(pem, keyPair);
      final prefix = keyTypeStr == 'ED25519' ? 'ssh-ed25519' : 'ssh-rsa';
      return '$prefix $b64 $comment'.trim();
    } catch (_) {
      return 'ssh-rsa $comment';
    }
  }

  static String _determineKeyType(String pemText, SSHKeyPair keyPair) {
    final upper = pemText.toUpperCase();
    if (upper.contains('ED25519')) return 'ED25519';
    if (upper.contains('RSA')) return 'RSA';
    if (upper.contains('EC') || upper.contains('ECDSA')) return 'ECDSA';
    return 'SSH-KEY';
  }

  /// Calculates a SHA256 base64 fingerprint of the OpenSSH public key string.
  static String calculateFingerprint(String publicKeyOpenSSH) {
    try {
      final parts = publicKeyOpenSSH.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final digest = sha256.convert(utf8.encode(parts[1]));
        final b64Hash = base64.encode(digest.bytes).replaceAll('=', '');
        return 'SHA256:$b64Hash';
      }
    } catch (_) {
      final digest = sha256.convert(utf8.encode(publicKeyOpenSSH));
      final b64Hash = base64.encode(digest.bytes);
      final trimmed = b64Hash.length > 20 ? b64Hash.substring(0, 20) : b64Hash;
      return 'SHA256:$trimmed';
    }
    return 'SHA256:unknown';
  }

  /// Generates a Linux command ready to paste into remote servers for authorized_keys.
  static String generateAuthorizedKeysCommand(String publicKeyOpenSSH) {
    return 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo "${publicKeyOpenSSH.trim()}" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys';
  }
}
