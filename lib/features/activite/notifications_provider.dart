import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_state.dart';
import '../../core/services/notification_service.dart';
import 'activite_page.dart';

const _kLastReadDateKey = 'eas_last_read_activite_date';
const _kLastNotifiedDateKey = 'eas_last_notified_activite_date';

class NotificationsState {
  final List<ActiviteEntree> unreadActivities;
  final bool hasUnread;
  final DateTime? lastReadDate;

  NotificationsState({
    required this.unreadActivities,
    required this.hasUnread,
    this.lastReadDate,
  });
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, NotificationsState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final notifService = ref.watch(notificationServiceProvider);
  return NotificationsNotifier(apiClient, notifService);
});

class NotificationsNotifier extends StateNotifier<NotificationsState> {
  final ApiClient _apiClient;
  final NotificationService _notifService;
  Timer? _timer;
  DateTime? _lastReadDate;
  DateTime? _lastNotifiedDate;

  NotificationsNotifier(this._apiClient, this._notifService)
      : super(NotificationsState(unreadActivities: [], hasUnread: false)) {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    
    final lastReadStr = prefs.getString(_kLastReadDateKey);
    if (lastReadStr != null) {
      _lastReadDate = DateTime.tryParse(lastReadStr);
    }
    
    final lastNotifiedStr = prefs.getString(_kLastNotifiedDateKey);
    if (lastNotifiedStr != null) {
      _lastNotifiedDate = DateTime.tryParse(lastNotifiedStr);
    }

    _notifService.init();
    
    // Premier chargement immédiat
    await _checkNewActivities();

    // Sondage régulier toutes les 20 secondes (comme le SyncEngine)
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      _checkNewActivities();
    });
  }

  Future<void> _checkNewActivities() async {
    try {
      final response = await _apiClient.dio.get(kDataActivites);
      final List<dynamic> data = response.data;
      final activites = data.map((json) => ActiviteEntree.fromJson(json)).toList();
      
      // Trier par date décroissante (les plus récentes en premier)
      activites.sort((a, b) {
        final dateA = a.dateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = b.dateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });

      List<ActiviteEntree> unread = [];
      
      for (final activite in activites) {
        final date = activite.dateTime;
        if (date == null) continue;

        // Si la date est plus récente que la dernière date lue, c'est non lu
        if (_lastReadDate == null || date.isAfter(_lastReadDate!)) {
          unread.add(activite);
        }

        // Si la date est plus récente que la dernière date notifiée, on notifie
        if (_lastNotifiedDate == null || date.isAfter(_lastNotifiedDate!)) {
          // Ignorer les activités dont on est l'auteur (optionnel, mais utile)
          // Ici, on notifie tout ce qui est nouveau
          _notifService.showNotification(activite);
          
          if (_lastNotifiedDate == null || date.isAfter(_lastNotifiedDate!)) {
            _lastNotifiedDate = date;
          }
        }
      }

      if (_lastNotifiedDate != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kLastNotifiedDateKey, _lastNotifiedDate!.toIso8601String());
      }

      state = NotificationsState(
        unreadActivities: unread.take(10).toList(), // on garde les 10 plus récentes pour le popup
        hasUnread: unread.isNotEmpty,
        lastReadDate: _lastReadDate,
      );
    } catch (e) {
      // Erreur réseau probable, on ignore
    }
  }

  /// Marquer toutes les notifications comme lues
  Future<void> markAllAsRead() async {
    _lastReadDate = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastReadDateKey, _lastReadDate!.toIso8601String());
    
    state = NotificationsState(
      unreadActivities: [],
      hasUnread: false,
      lastReadDate: _lastReadDate,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
