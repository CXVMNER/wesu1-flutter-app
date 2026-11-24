import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../watch_service.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.service});
  final WatchService service;

  @override
  Widget build(BuildContext context) {
    final s = service;
    final st = s.settings;
    return ListView(
      children: [
        const _Header('Connection'),
        SwitchListTile(
          title: const Text('Reconnect to last watch on launch'),
          subtitle: const Text('Applies the next time the app starts'),
          value: st.autoConnect,
          onChanged: (v) => s.updateSettings((x) => x.autoConnect = v),
        ),
        const _Header('Notifications'),
        SwitchListTile(
          title: const Text('Connection alerts'),
          subtitle: const Text('Notify when the watch connects or drops'),
          value: st.connectionAlerts,
          onChanged: (v) => s.updateSettings((x) => x.connectionAlerts = v),
        ),
        SwitchListTile(
          title: const Text('Motion alerts'),
          subtitle: const Text('Notify when acceleration exceeds a threshold'),
          value: st.motionAlerts,
          onChanged: (v) => s.updateSettings((x) => x.motionAlerts = v),
        ),
        ListTile(
          enabled: st.motionAlerts,
          title: Text('Threshold: ${st.motionThresholdG.toStringAsFixed(1)} g'),
          subtitle: Slider(
            min: 1.2,
            max: 3.0,
            divisions: 18,
            value: st.motionThresholdG.clamp(1.2, 3.0).toDouble(),
            onChanged: st.motionAlerts
                ? (v) => s.updateSettings((x) => x.motionThresholdG = v)
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Send test notification'),
              onPressed: s.sendTestNotification,
            ),
          ),
        ),
        if (s.notificationProblem != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(s.notificationProblem!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: openAppSettings,
              child: const Text('Open system notification settings'),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Notifications are raised by this app on the phone. At rest the '
            'accelerometer reads about 1 g; the watch is configured for '
            '±2 g per axis.',
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
