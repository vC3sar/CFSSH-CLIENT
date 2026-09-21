import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ssh_key_model.dart';
import '../repositories/database_service.dart';
import '../security/secure_storage.dart';

class KeysState {
  final List<SshKeyModel> keys;
  final bool isLoading;
  final String? error;

  const KeysState({
    this.keys = const [],
    this.isLoading = false,
    this.error,
  });

  KeysState copyWith({
    List<SshKeyModel>? keys,
    bool? isLoading,
    String? error,
  }) {
    return KeysState(
      keys: keys ?? this.keys,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class KeysNotifier extends Notifier<KeysState> {
  final DatabaseService _dbService = DatabaseService.instance;
  final SecureStorage _secureStorage = SecureStorage();

  @override
  KeysState build() {
    Future.microtask(() => loadKeys());
    return const KeysState();
  }

  Future<void> loadKeys() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final keys = await _dbService.getAllSshKeys();
      state = state.copyWith(keys: keys, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> saveKey({
    required SshKeyModel keyModel,
    required String privateKeyPem,
    String? passphrase,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _secureStorage.savePrivateKey(
        keyModel.id,
        privateKeyPem,
        passphrase: passphrase,
      );
      await _dbService.insertSshKey(keyModel);
      await loadKeys();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> deleteKey(String keyId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _secureStorage.deletePrivateKey(keyId);
      await _dbService.deleteSshKey(keyId);
      await loadKeys();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<String?> getPrivateKeyPem(String keyId) async {
    return await _secureStorage.getPrivateKey(keyId);
  }

  Future<String?> getPassphrase(String keyId) async {
    return await _secureStorage.getPassphrase(keyId);
  }
}

final keysProvider = NotifierProvider<KeysNotifier, KeysState>(() {
  return KeysNotifier();
});
