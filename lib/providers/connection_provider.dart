import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/connection_profile.dart';
import '../repositories/database_service.dart';

class ConnectionProfileState {
  final List<ConnectionProfile> profiles;
  final bool isLoading;
  final String? error;

  ConnectionProfileState({
    this.profiles = const [],
    this.isLoading = true,
    this.error,
  });

  ConnectionProfileState copyWith({
    List<ConnectionProfile>? profiles,
    bool? isLoading,
    String? error,
  }) {
    return ConnectionProfileState(
      profiles: profiles ?? this.profiles,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class ConnectionProfileNotifier extends Notifier<ConnectionProfileState> {
  @override
  ConnectionProfileState build() {
    // We cannot do async in build() directly without returning AsyncValue, 
    // but we can kick off a load and return initial state.
    Future.microtask(() => loadProfiles());
    return ConnectionProfileState();
  }

  Future<void> loadProfiles() async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final profiles = await DatabaseService.instance.getAllProfiles();
      state = state.copyWith(profiles: profiles, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<void> addProfile(ConnectionProfile profile) async {
    await DatabaseService.instance.insertProfile(profile);
    await loadProfiles();
  }

  Future<void> updateProfile(ConnectionProfile profile) async {
    await DatabaseService.instance.updateProfile(profile);
    await loadProfiles();
  }

  Future<void> deleteProfile(String id) async {
    await DatabaseService.instance.deleteProfile(id);
    await loadProfiles();
  }
}

final connectionProfilesProvider = NotifierProvider<ConnectionProfileNotifier, ConnectionProfileState>(() {
  return ConnectionProfileNotifier();
});
