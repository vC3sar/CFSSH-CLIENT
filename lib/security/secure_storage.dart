import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  final FlutterSecureStorage _storage;

  SecureStorage() : _storage = const FlutterSecureStorage();

  String _getPasswordKey(String profileId) => 'pwd_$profileId';
  String _getPassphraseKey(String keyId) => 'pp_$keyId';
  String _getPrivateKeyKey(String keyId) => 'pk_$keyId';

  Future<void> savePassword(String profileId, String password) async {
    await _storage.write(key: _getPasswordKey(profileId), value: password);
  }

  Future<String?> getPassword(String profileId) async {
    return await _storage.read(key: _getPasswordKey(profileId));
  }

  Future<void> deletePassword(String profileId) async {
    await _storage.delete(key: _getPasswordKey(profileId));
  }

  Future<void> savePrivateKey(String keyId, String privateKey, {String? passphrase}) async {
    await _storage.write(key: _getPrivateKeyKey(keyId), value: privateKey);
    if (passphrase != null && passphrase.isNotEmpty) {
      await _storage.write(key: _getPassphraseKey(keyId), value: passphrase);
    }
  }

  Future<String?> getPrivateKey(String keyId) async {
    return await _storage.read(key: _getPrivateKeyKey(keyId));
  }

  Future<String?> getPassphrase(String keyId) async {
    return await _storage.read(key: _getPassphraseKey(keyId));
  }

  Future<void> deletePrivateKey(String keyId) async {
    await _storage.delete(key: _getPrivateKeyKey(keyId));
    await _storage.delete(key: _getPassphraseKey(keyId));
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
