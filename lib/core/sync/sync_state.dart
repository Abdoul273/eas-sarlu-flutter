import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'op_queue.dart';

enum SyncStatus { idle, syncing, offline, error, conflict }

class ConflictInfo {
  final String operationId;
  final String type;
  final Map<String, dynamic> localPayload;
  final Map<String, dynamic> serverRecord;

  ConflictInfo({
    required this.operationId,
    required this.type,
    required this.localPayload,
    required this.serverRecord,
  });
}

class SyncState {
  final SyncStatus status;
  final int pendingCount;
  final String? errorMessage;
  final DateTime? lastSync;
  final ConflictInfo? conflict;

  /// Opérations que le serveur a refusées faute de droit, en attente d'être
  /// annoncées à l'utilisateur.
  ///
  /// Elles ne sont pas des erreurs : elles ne repartiront pas, et l'écran a
  /// déjà repris l'état du serveur. Mais quelqu'un a saisi quelque chose qui
  /// n'a pas été retenu — il doit l'apprendre, et savoir pourquoi.
  final List<String> refus;

  SyncState({
    this.status = SyncStatus.idle,
    this.pendingCount = 0,
    this.errorMessage,
    this.lastSync,
    this.conflict,
    this.refus = const [],
  });

  SyncState copyWith({
    SyncStatus? status,
    int? pendingCount,
    String? errorMessage,
    DateTime? lastSync,
    ConflictInfo? conflict,
    bool clearConflict = false,
    List<String>? refus,
  }) {
    return SyncState(
      status: status ?? this.status,
      pendingCount: pendingCount ?? this.pendingCount,
      errorMessage: errorMessage,
      lastSync: lastSync ?? this.lastSync,
      conflict: clearConflict ? null : (conflict ?? this.conflict),
      refus: refus ?? this.refus,
    );
  }
}

class SyncStateNotifier extends StateNotifier<SyncState> {
  StreamSubscription? _sub;

  SyncStateNotifier(Stream<int> pendingCountStream) : super(SyncState()) {
    _sub = pendingCountStream.listen((count) {
      if (state.pendingCount != count) {
        state = state.copyWith(pendingCount: count);
      }
    });
  }

  void updateStatus(SyncStatus status,
      {int? pendingCount, String? errorMessage}) {
    state = state.copyWith(
      status: status,
      pendingCount: pendingCount ?? state.pendingCount,
      errorMessage: errorMessage,
      lastSync: status == SyncStatus.idle ? DateTime.now() : state.lastSync,
    );
  }

  /// Le serveur a refusé des opérations faute de droit.
  void signalerRefus(List<String> messages) {
    state = state.copyWith(refus: messages);
  }

  /// L'utilisateur a vu les refus : on ne les lui redit pas à chaque cycle.
  void accuserReceptionRefus() {
    if (state.refus.isEmpty) return;
    state = state.copyWith(refus: const []);
  }

  void setConflict(ConflictInfo conflict) {
    state = state.copyWith(status: SyncStatus.conflict, conflict: conflict);
  }

  void resolveConflict() {
    state = state.copyWith(clearConflict: true, status: SyncStatus.idle);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final syncStateProvider =
    StateNotifierProvider<SyncStateNotifier, SyncState>((ref) {
  final opQueue = ref.watch(opQueueProvider);
  return SyncStateNotifier(opQueue.watchPendingCount());
});
