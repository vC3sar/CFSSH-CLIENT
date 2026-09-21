import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/connection_history.dart';
import '../repositories/database_service.dart';

class HistoryNotifier extends Notifier<List<ConnectionHistory>> {
  @override
  List<ConnectionHistory> build() {
    Future.microtask(() => loadHistory());
    return [];
  }

  Future<void> loadHistory() async {
    try {
      final history = await DatabaseService.instance.getRecentHistory(limit: 10);
      state = history;
    } catch (e) {
      // Return empty list on error for now
      state = [];
    }
  }

  Future<void> addHistory(String profileId) async {
    final entry = ConnectionHistory(
      profileId: profileId,
      timestamp: DateTime.now(),
    );
    await DatabaseService.instance.insertHistory(entry);
    await loadHistory();
  }
}

final historyProvider = NotifierProvider<HistoryNotifier, List<ConnectionHistory>>(() {
  return HistoryNotifier();
});
