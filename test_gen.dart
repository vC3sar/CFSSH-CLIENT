import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';

void main() async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
  final publicKey = await keyPair.extractPublicKey();
  final publicKeyBytes = publicKey.bytes;

  final pem = _generateOpenSSHEd25519Pem(privateKeyBytes, publicKeyBytes, comment: 'test@cfssh');
  print('PEM:');
  print(pem);

  try {
    final parsed = SSHKeyPair.fromPem(pem);
    print('Successfully parsed: \${parsed.length} keys');
  } catch (e, st) {
    print('Failed to parse: \$e');
    print(st);
  }
}

String _generateOpenSSHEd25519Pem(List<int> seed32, List<int> pub32, {String comment = 'cfssh'}) {
  final builder = BytesBuilder();

  void writeUint32(int val) {
    builder.add([
      (val >> 24) & 0xFF,
      (val >> 16) & 0xFF,
      (val >> 8) & 0xFF,
      val & 0xFF,
    ]);
  }

  void writeString(String s) {
    final bytes = utf8.encode(s);
    writeUint32(bytes.length);
    builder.add(bytes);
  }

  void writeBytes(List<int> bytes) {
    writeUint32(bytes.length);
    builder.add(bytes);
  }

  // 1. Header magic
  builder.add(utf8.encode('openssh-key-v1\x00'));

  // 2. Cipher, KDF, Num Keys
  writeString('none');
  writeString('none');
  writeString('');
  writeUint32(1);

  // 3. Public Key 0
  final pubKeyBlob = BytesBuilder();
  final typeBytes = utf8.encode('ssh-ed25519');
  pubKeyBlob.add([
    (typeBytes.length >> 24) & 0xFF,
    (typeBytes.length >> 16) & 0xFF,
    (typeBytes.length >> 8) & 0xFF,
    typeBytes.length & 0xFF,
  ]);
  pubKeyBlob.add(typeBytes);
  pubKeyBlob.add([
    (pub32.length >> 24) & 0xFF,
    (pub32.length >> 16) & 0xFF,
    (pub32.length >> 8) & 0xFF,
    pub32.length & 0xFF,
  ]);
  pubKeyBlob.add(pub32);

  writeBytes(pubKeyBlob.toBytes());

  // 4. Private Key Block
  final privKeyBuilder = BytesBuilder();
  final checkint = DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF;
  
  void writePrivUint32(int val) {
    privKeyBuilder.add([
      (val >> 24) & 0xFF,
      (val >> 16) & 0xFF,
      (val >> 8) & 0xFF,
      val & 0xFF,
    ]);
  }

  void writePrivBytes(List<int> bytes) {
    writePrivUint32(bytes.length);
    privKeyBuilder.add(bytes);
  }

  void writePrivString(String s) {
    writePrivBytes(utf8.encode(s));
  }

  writePrivUint32(checkint);
  writePrivUint32(checkint);

  writePrivString('ssh-ed25519');
  writePrivBytes(pub32); // pubkey
  writePrivBytes([...seed32, ...pub32]); // secretkey (seed + pubkey)
  writePrivString(comment);

  // Padding
  int padLen = 8 - (privKeyBuilder.length % 8);
  if (padLen == 0) padLen = 8;
  for (int i = 1; i <= padLen; i++) {
    privKeyBuilder.addByte(i);
  }

  writeBytes(privKeyBuilder.toBytes());

  final b64 = base64.encode(builder.toBytes());
  final lines = <String>[];
  for (int i = 0; i < b64.length; i += 64) {
    lines.add(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
  }

  return '-----BEGIN OPENSSH PRIVATE KEY-----\n${lines.join("\n")}\n-----END OPENSSH PRIVATE KEY-----';
}
