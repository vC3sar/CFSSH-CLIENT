import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';

void main() async {
  // Let's create a dummy RSA key to parse
  final rsaPem = '''-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA3V4T/C...
-----END RSA PRIVATE KEY-----''';

  try {
    // Actually dartssh2 might not have a built in RSA generator, but I can check properties
    print(SSHKeyPair);
  } catch (e) {
    print(e);
  }
}
