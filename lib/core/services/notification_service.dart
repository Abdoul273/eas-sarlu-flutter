import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/activite/activite_page.dart';

/// Provider global pour le service de notifications.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

class NotificationService {
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  
  /// Callback appelé lorsqu'une notification est tapée (pour redirection).
  void Function(String? payload)? onNotificationClick;

  Future<void> init() async {
    if (_initialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (onNotificationClick != null) {
          onNotificationClick!(response.payload);
        }
      },
    );

    _initialized = true;
  }

  Future<void> showNotification(ActiviteEntree activite) async {
    await init();
    
    // Convertir l'activité en payload JSON pour le clic
    final payload = jsonEncode({
      'id': activite.id,
      'type': activite.type,
    });

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'eas_activites', // id du canal
      'Activités récentes', // nom du canal
      channelDescription: 'Notifications pour les nouvelles activités.',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _flutterLocalNotificationsPlugin.show(
      activite.id.hashCode, // un id unique pour la notification
      'Nouvelle activité : ${activite.type.toUpperCase()}',
      activite.description,
      platformChannelSpecifics,
      payload: payload,
    );
  }
}
