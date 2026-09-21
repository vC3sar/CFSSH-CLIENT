import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/connection_profile.dart';
import '../repositories/database_service.dart';

enum ServerStatus { checking, online, offline }

class ConnectionProfileState {
  final List<ConnectionProfile> profiles;
  final Map<String, ServerStatus> statuses;
  final bool isLoading;
  final String? error;

  ConnectionProfileState({
    this.profiles = const [],
    this.statuses = const {},
    this.isLoading = true,
    this.error,
  });

  ConnectionProfileState copyWith({
    List<ConnectionProfile>? profiles,
    Map<String, ServerStatus>? statuses,
    bool? isLoading,
    String? error,
  }) {
    return ConnectionProfileState(
      profiles: profiles ?? this.profiles,
      statuses: statuses ?? this.statuses,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class ConnectionProfileNotifier extends Notifier<ConnectionProfileState> {
  @override
  ConnectionProfileState build() {
    Future.microtask(() => loadProfiles());
    return ConnectionProfileState();
  }

  Future<void> loadProfiles() async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final profiles = await DatabaseService.instance.getAllProfiles();
      
      // Initialize statuses to 'checking'
      final Map<String, ServerStatus> initialStatuses = {};
      for (var p in profiles) {
        initialStatuses[p.id] = ServerStatus.checking;
      }
      
      state = state.copyWith(profiles: profiles, statuses: initialStatuses, isLoading: false);
      
      // Kick off background ping check
      _pingServers(profiles);
      
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  void _pingServers(List<ConnectionProfile> profiles) {
    for (var profile in profiles) {
      _checkStatus(profile);
    }
  }

  Future<void> _checkStatus(ConnectionProfile profile) async {
    try {
      final socket = await Socket.connect(profile.host, profile.port, timeout: const Duration(seconds: 3));
      socket.destroy();
      
      // Make sure profile still exists before updating state
      final newStatuses = Map<String, ServerStatus>.from(state.statuses);
      if (newStatuses.containsKey(profile.id)) {
        newStatuses[profile.id] = ServerStatus.online;
        state = state.copyWith(statuses: newStatuses);
      }
    } catch (_) {
      final newStatuses = Map<String, ServerStatus>.from(state.statuses);
      if (newStatuses.containsKey(profile.id)) {
        newStatuses[profile.id] = ServerStatus.offline;
        state = state.copyWith(statuses: newStatuses);
      }
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
