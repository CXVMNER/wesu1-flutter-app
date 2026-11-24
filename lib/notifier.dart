import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Phone notifications raised by this app (connection, motion, watch alarms).
class Notifier {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _nextId = 10;

  /// Set when the system will not show a notification. The UI reads this.
  String? lastError;
  bool? permissionGranted;

  static const AndroidNotificationChannel _alarmChannel =
      AndroidNotificationChannel(
    'watch_alarm_v3',
    'Watch alarms',
    description: 'Button and fall alarms from the WESU1 watch',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  Future<void> init() async {
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _plugin.initialize(settings);
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        permissionGranted = await android.requestNotificationsPermission();
        await android.createNotificationChannel(_alarmChannel);
        if (permissionGranted == false) {
          lastError =
              'Notifications are blocked. Allow them for this app in system settings.';
        }
      }
      _ready = true;
    } catch (e) {
      lastError = 'Notifications failed to start: $e';
      debugPrint('Notifier init failed: $e');
    }
  }

  Future<void> _show(int id, String channelId, String channelName,
      String title, String body,
      {bool alarm = false}) async {
    if (!_ready) {
      lastError ??= 'Notifications are not initialized.';
      return;
    }
    if (alarm && permissionGranted == false) {
      lastError =
          'Notifications are blocked. Allow them for this app in system settings.';
      return;
    }
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            alarm ? _alarmChannel.id : channelId,
            alarm ? _alarmChannel.name : channelName,
            channelDescription:
                alarm ? _alarmChannel.description : null,
            importance: alarm ? Importance.max : Importance.high,
            priority: alarm ? Priority.max : Priority.high,
            category: alarm ? AndroidNotificationCategory.alarm : null,
            visibility: NotificationVisibility.public,
            playSound: true,
            enableVibration: true,
            ticker: title,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
      );
    } catch (e) {
      lastError = 'Notification failed: $e';
      debugPrint('Notification failed: $e');
    }
  }

  Future<void> connection(String title, String body) =>
      _show(1, 'watch_connection', 'Watch connection', title, body);

  Future<void> motion(String title, String body) =>
      _show(2, 'watch_motion', 'Motion alerts', title, body);

  /// Always a new notification id so Android does not silently replace
  /// the previous one without a heads-up.
  Future<void> fall(String title, String body) =>
      _show(_nextId++, _alarmChannel.id, _alarmChannel.name, title, body,
          alarm: true);

  Future<void> test() =>
      _show(3, _alarmChannel.id, _alarmChannel.name, 'Test notification',
          'Notifications from the WESU1 app are working.',
          alarm: true);
}
