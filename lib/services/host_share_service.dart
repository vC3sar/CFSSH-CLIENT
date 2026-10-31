import 'dart:convert';
import 'dart:io' show ZLibEncoder, ZLibDecoder;
import 'dart:math' show Random;
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:zxing2/qrcode.dart';

import '../models/connection_profile.dart';
import '../models/ssh_key_model.dart';
import '../repositories/database_service.dart';
import '../security/secure_storage.dart';

class HostShareException implements Exception {
  final String message;
  const HostShareException(this.message);

  @override
  String toString() => message;
}

class HostShareBundle {
  final String qrPayload;
  final String secretPhrase;
  final List<String> words;
  final String tokenId;
  final String authSummary;

  const HostShareBundle({
    required this.qrPayload,
    required this.secretPhrase,
    required this.words,
    required this.tokenId,
    required this.authSummary,
  });
}

class ImportedHostResult {
  final ConnectionProfile profile;
  final String? password;
  final SshKeyModel? sshKeyModel;
  final String? privateKeyPem;
  final String? keyPassphrase;

  const ImportedHostResult({
    required this.profile,
    this.password,
    this.sshKeyModel,
    this.privateKeyPem,
    this.keyPassphrase,
  });
}

class HostShareService {
  static const String _prefix = 'CFSSH1';
  static const String _consumedTokensPrefsKey = 'consumed_qr_share_tokens_v1';

  /// Curated list of short (3-4 letter), unambiguous, accent-free words
  /// designed to be easily read and typed by hand.
  static const List<String> _shortWords = [
    'sol', 'mar', 'luz', 'red', 'paz', 'voz', 'sur', 'rio',
    'oro', 'eco', 'gas', 'sal', 'pan', 'flor', 'tren', 'nube',
    'luna', 'lobo', 'puma', 'gato', 'leon', 'faro', 'pino', 'roca',
    'lago', 'vela', 'dato', 'nodo', 'ruta', 'cubo', 'rayo', 'arco',
    'onda', 'pico', 'meta', 'base', 'zona', 'cero', 'alfa', 'beta',
    'nexo', 'foco', 'mina', 'copa', 'isla', 'nave', 'muro', 'clip',
    'chip', 'byte', 'ping', 'host', 'port', 'root', 'azul', 'gris',
    'rojo', 'jade', 'onix', 'zinc', 'iris', 'aura', 'lince', 'tigre',
  ];

  /// Generates a one-time secret phrase of at most 3 short words.
  static List<String> generateThreeShortWords() {
    final rng = Random.secure();
    final selected = <String>[];
    while (selected.length < 3) {
      final candidate = _shortWords[rng.nextInt(_shortWords.length)];
      if (!selected.contains(candidate)) {
        selected.add(candidate);
      }
    }
    return selected;
  }

  /// Normalizes a user-typed 3-word phrase so spaces, hyphens, or uppercase
  /// differences are handled seamlessly.
  static String normalizePhrase(String input) {
    final cleaned = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-_,.;:]+'), '-');
    return cleaned.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  /// Generates a random one-time token ID (8 random bytes encoded in base64Url).
  static String _generateTokenId() {
    final rng = Random.secure();
    final bytes = Uint8List.fromList(List<int>.generate(8, (_) => rng.nextInt(256)));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Checks if a one-time share token ID has already been used/consumed.
  static Future<bool> isTokenConsumed(String tokenId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_consumedTokensPrefsKey) ?? const [];
    return list.contains(tokenId);
  }

  /// Marks a one-time share token ID as consumed so it cannot be reused.
  static Future<void> markTokenConsumed(String tokenId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = List<String>.from(
      prefs.getStringList(_consumedTokensPrefsKey) ?? const [],
    );
    if (!list.contains(tokenId)) {
      list.add(tokenId);
      // Keep last 500 consumed token IDs
      if (list.length > 500) {
        list.removeRange(0, list.length - 500);
      }
      await prefs.setStringList(_consumedTokensPrefsKey, list);
    }
  }

  /// Extracts the tokenId from a raw QR payload string if valid.
  static String? extractTokenId(String rawPayload) {
    final trimmed = rawPayload.trim();
    final parts = trimmed.split(':');
    if (parts.length != 3 || parts[0] != _prefix) {
      return null;
    }
    return parts[1];
  }

  /// Creates an encrypted, compressed QR payload and a 3-word one-time secret phrase
  /// for the given [profile], including its password or SSH private key.
  static Future<HostShareBundle> createShareBundle(ConnectionProfile profile) async {
    final secureStorage = SecureStorage();
    final db = DatabaseService.instance;

    final words = generateThreeShortWords();
    final normalizedPhrase = words.join('-');
    final tokenId = _generateTokenId();

    final Map<String, dynamic> payloadMap = {
      'v': 1,
      'tid': tokenId,
      'iat': DateTime.now().millisecondsSinceEpoch,
      'n': profile.name,
      'h': profile.host,
      'p': profile.port,
      'u': profile.username,
      'a': profile.authMethod,
      'to': profile.timeout,
      'ka': profile.keepalive,
    };

    String authSummary;

    if (profile.authMethod == 'private_key') {
      String? keyId = profile.privateKeyId;
      SshKeyModel? keyModel;
      String? privateKeyPem;
      String? passphrase;

      if (keyId != null) {
        keyModel = await db.getSshKeyById(keyId);
        privateKeyPem = await secureStorage.getPrivateKey(keyId);
        passphrase = await secureStorage.getPassphrase(keyId);
      }

      if (privateKeyPem == null) {
        // Fallback to first available key if none explicitly linked
        final allKeys = await db.getAllSshKeys();
        if (allKeys.isNotEmpty) {
          keyModel = allKeys.first;
          privateKeyPem = await secureStorage.getPrivateKey(keyModel.id);
          passphrase = await secureStorage.getPassphrase(keyModel.id);
        }
      }

      if (privateKeyPem == null || privateKeyPem.isEmpty) {
        throw const HostShareException(
          'No se encontró la llave privada SSH asociada a este host para poder compartirla.',
        );
      }

      payloadMap['kn'] = keyModel?.name ?? '${profile.name} Key';
      payloadMap['kt'] = keyModel?.keyType ?? 'ED25519';
      payloadMap['kp'] = keyModel?.publicKey ?? '';
      payloadMap['kf'] = keyModel?.fingerprint ?? '';
      payloadMap['pk'] = privateKeyPem;
      if (passphrase != null && passphrase.isNotEmpty) {
        payloadMap['pp'] = passphrase;
      }

      authSummary = 'SSH Key (${keyModel?.name ?? payloadMap['kt']})';
    } else {
      final password = await secureStorage.getPassword(profile.id) ?? '';
      payloadMap['pw'] = password;
      authSummary = password.isNotEmpty
          ? 'Password (incluida y cifrada)'
          : 'Password (vacía)';
    }

    // 1. Serialize & Compress with ZLib level 9 to minimize QR density
    final jsonBytes = utf8.encode(jsonEncode(payloadMap));
    final compressedBytes = ZLibEncoder(level: 9).convert(jsonBytes);

    // 2. Generate random 12-byte salt and 12-byte AES-GCM nonce
    final rng = Random.secure();
    final salt = Uint8List.fromList(List<int>.generate(12, (_) => rng.nextInt(256)));
    final nonce = Uint8List.fromList(List<int>.generate(12, (_) => rng.nextInt(256)));

    // 3. Derive 256-bit key using PBKDF2-HMAC-SHA256 from the 3-word phrase + tokenId
    final secretKey = await _deriveKey(normalizedPhrase, tokenId, salt);

    // 4. Encrypt with AES-256-GCM using tokenId as AAD
    final aesGcm = AesGcm.with256bits();
    final secretBox = await aesGcm.encrypt(
      compressedBytes,
      secretKey: secretKey,
      nonce: nonce,
      aad: utf8.encode(tokenId),
    );

    // 5. Pack salt (12) + nonce (12) + mac (16) + cipherText
    final packed = BytesBuilder(copy: false)
      ..add(salt)
      ..add(nonce)
      ..add(secretBox.mac.bytes)
      ..add(secretBox.cipherText);

    final encodedBlob = base64UrlEncode(packed.toBytes()).replaceAll('=', '');
    final qrPayload = '$_prefix:$tokenId:$encodedBlob';

    return HostShareBundle(
      qrPayload: qrPayload,
      secretPhrase: words.join(' '),
      words: words,
      tokenId: tokenId,
      authSummary: authSummary,
    );
  }

  /// Decrypts a QR payload using the 3-word secret phrase and marks the token
  /// as consumed (one-time use).
  static Future<ImportedHostResult> decryptAndConsumeShareBundle({
    required String rawQrPayload,
    required String userSecretPhrase,
  }) async {
    final trimmed = rawQrPayload.trim();
    final parts = trimmed.split(':');
    if (parts.length != 3 || parts[0] != _prefix) {
      throw const HostShareException(
        'Formato de código QR inválido. Asegúrate de escanear un código QR generado por CFSSH Client.',
      );
    }

    final tokenId = parts[1];
    final encodedBlob = parts[2];

    if (await isTokenConsumed(tokenId)) {
      throw const HostShareException(
        'Este código QR y su frase secreta son de uso único y ya fueron utilizados anteriormente.',
      );
    }

    final normalizedPhrase = normalizePhrase(userSecretPhrase);
    if (normalizedPhrase.isEmpty) {
      throw const HostShareException(
        'Ingresa la frase secreta de 3 palabras para descifrar el host.',
      );
    }

    Uint8List packedBytes;
    try {
      packedBytes = base64Url.decode(base64Url.normalize(encodedBlob));
    } catch (_) {
      throw const HostShareException('Datos del código QR corruptos.');
    }

    // Minimum size: 12 (salt) + 12 (nonce) + 16 (mac) + 1 = 41 bytes
    if (packedBytes.length < 41) {
      throw const HostShareException('Datos del código QR incompletos.');
    }

    final salt = packedBytes.sublist(0, 12);
    final nonce = packedBytes.sublist(12, 24);
    final macBytes = packedBytes.sublist(24, 40);
    final cipherText = packedBytes.sublist(40);

    final secretKey = await _deriveKey(normalizedPhrase, tokenId, salt);
    final aesGcm = AesGcm.with256bits();

    List<int> compressedBytes;
    try {
      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(macBytes),
      );
      compressedBytes = await aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
        aad: utf8.encode(tokenId),
      );
    } on SecretBoxAuthenticationError {
      throw const HostShareException(
        'Frase secreta incorrecta. Verifica las 3 palabras e inténtalo de nuevo.',
      );
    } catch (e) {
      throw HostShareException('Error al descifrar: $e');
    }

    Map<String, dynamic> map;
    try {
      final jsonBytes = ZLibDecoder().convert(compressedBytes);
      map = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const HostShareException(
        'El contenido descifrado del QR está dañado o es incompatible.',
      );
    }

    // Burn the one-time token immediately after successful decryption
    await markTokenConsumed(tokenId);

    final now = DateTime.now();
    final newProfileId = const Uuid().v4();
    final authMethod = (map['a'] as String?) ?? 'password';

    SshKeyModel? sshKeyModel;
    String? privateKeyPem;
    String? keyPassphrase;
    String? assignedKeyId;

    if (authMethod == 'private_key') {
      privateKeyPem = map['pk'] as String?;
      keyPassphrase = map['pp'] as String?;
      if (privateKeyPem != null && privateKeyPem.isNotEmpty) {
        assignedKeyId = const Uuid().v4();
        sshKeyModel = SshKeyModel(
          id: assignedKeyId,
          name: (map['kn'] as String?) ?? '${map['n'] ?? 'Shared'} Key',
          keyType: (map['kt'] as String?) ?? 'ED25519',
          publicKey: (map['kp'] as String?) ?? '',
          fingerprint: (map['kf'] as String?) ?? '',
          createdAt: now,
        );
      }
    }

    final profile = ConnectionProfile(
      id: newProfileId,
      name: (map['n'] as String?) ?? 'Shared Host',
      host: (map['h'] as String?) ?? '',
      port: (map['p'] as int?) ?? 22,
      username: (map['u'] as String?) ?? 'root',
      authMethod: authMethod,
      privateKeyId: assignedKeyId,
      timeout: (map['to'] as int?) ?? 10000,
      keepalive: (map['ka'] as int?) ?? 0,
      createdAt: now,
      lastConnected: now,
    );

    return ImportedHostResult(
      profile: profile,
      password: map['pw'] as String?,
      sshKeyModel: sshKeyModel,
      privateKeyPem: privateKeyPem,
      keyPassphrase: keyPassphrase,
    );
  }

  static Future<SecretKey> _deriveKey(
    String normalizedPhrase,
    String tokenId,
    Uint8List salt,
  ) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 10000,
      bits: 256,
    );
    return await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode('$normalizedPhrase|$tokenId')),
      nonce: salt,
    );
  }

  /// Decodes a QR code string from raw image bytes (PNG, JPG, WebP, BMP).
  static String decodeQrFromImageBytes(Uint8List bytes) {
    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) {
      throw const HostShareException('No se pudo leer el archivo de imagen.');
    }

    final width = decodedImage.width;
    final height = decodedImage.height;
    final pixels = Int32List(width * height);

    int index = 0;
    for (final pixel in decodedImage) {
      final r = pixel.r.toInt() & 0xff;
      final g = pixel.g.toInt() & 0xff;
      final b = pixel.b.toInt() & 0xff;
      pixels[index++] = (r << 16) | (g << 8) | b;
    }

    final source = RGBLuminanceSource(width, height, pixels);
    final reader = QRCodeReader();

    // Try standard HybridBinarizer first, then GlobalHistogramBinarizer and inverted
    final candidates = <Binarizer>[
      HybridBinarizer(source),
      GlobalHistogramBinarizer(source),
      HybridBinarizer(InvertedLuminanceSource(source)),
    ];

    for (final binarizer in candidates) {
      try {
        final bitmap = BinaryBitmap(binarizer);
        final result = reader.decode(bitmap);
        if (result.text.isNotEmpty) {
          return result.text;
        }
      } catch (_) {
        // Try next binarizer
      }
    }

    throw const HostShareException(
      'No se detectó ningún código QR válido en la imagen seleccionada.',
    );
  }
}

