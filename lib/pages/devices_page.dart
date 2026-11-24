import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart'
    show BleStatus;

import '../models.dart';
import '../watch_service.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key, required this.service});
  final WatchService service;

  @override
  Widget build(BuildContext context) {
    final s = service;
    final savedIds = s.saved.map((d) => d.id).toSet();
    final nearby = s.visibleFound;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (s.bleStatus != BleStatus.ready && s.bleStatus != BleStatus.unknown)
          _BluetoothBanner(status: s.bleStatus),
        if (s.activeId != null) _ActiveCard(service: s),

        Text('Saved devices', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        if (s.saved.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
                'Watches you connect to are remembered here, and the most '
                'recent one reconnects automatically on launch.'),
          ),
        for (final d in s.saved)
          Card(
            child: ListTile(
              leading: const Icon(Icons.watch),
              title: Text(d.name),
              subtitle: Text('${d.id}\nLast connected ${fmtAgo(d.lastConnected)}'),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (s.activeId == d.id)
                    TextButton(
                        onPressed: s.disconnect,
                        child: const Text('Disconnect'))
                  else
                    FilledButton.tonal(
                        onPressed: () => s.connect(d.id, name: d.name),
                        child: const Text('Connect')),
                  IconButton(
                    tooltip: 'Forget',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => s.forget(d.id),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: Text('Nearby', style: textTheme.titleMedium)),
            FilterChip(
              label: const Text('WESU1 only'),
              selected: s.settings.onlyWesu,
              onSelected: (v) => s.updateSettings((st) => st.onlyWesu = v),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: s.scanning ? s.stopScan : s.startScan,
              icon: Icon(s.scanning ? Icons.stop : Icons.search),
              label: Text(s.scanning ? 'Stop' : 'Scan'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (s.scanning) const LinearProgressIndicator(),
        if (nearby.isEmpty && !s.scanning)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Tap Scan to look for watches. Make sure the watch '
                'is powered and advertising as "WESU1-Lab".'),
          ),
        for (final d in nearby)
          Card(
            child: ListTile(
              leading: const Icon(Icons.bluetooth),
              title: Text(d.name.isEmpty ? '(no name)' : d.name),
              subtitle: Text('${d.id}\nSignal ${d.rssi} dBm'
                  '${savedIds.contains(d.id) ? '  •  saved' : ''}'),
              isThreeLine: true,
              trailing: s.activeId == d.id
                  ? const Icon(Icons.check_circle)
                  : FilledButton.tonal(
                      onPressed: () => s.connect(d.id, name: d.name),
                      child: const Text('Connect')),
            ),
          ),
      ],
    );
  }
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.service});
  final WatchService service;

  @override
  Widget build(BuildContext context) {
    final s = service;
    final scheme = Theme.of(context).colorScheme;
    final String status;
    if (s.link == LinkState.connected) {
      status = 'Connected';
    } else if (s.link == LinkState.connecting) {
      status = 'Connecting…';
    } else if (s.reconnecting) {
      status = 'Connection lost, retrying…';
    } else {
      status = 'Waiting for Bluetooth…';
    }
    return Card(
      color: scheme.primaryContainer,
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.activeName ?? s.activeId ?? '',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(status),
            if (s.fallAlert)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(s.alarmText ?? 'Alarm from the watch',
                    style: TextStyle(
                        color: scheme.error, fontWeight: FontWeight.w600)),
              ),
            if (s.link == LinkState.connected)
              Text('${s.rateHz.toStringAsFixed(1)} packets/s  •  '
                  '${s.packetCount} received\n'
                  'Listening for alarms on ${s.alertChars} characteristic'
                  '${s.alertChars == 1 ? '' : 's'}'),
            if (s.lastError != null) ...[
              const SizedBox(height: 8),
              Text(s.lastError!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                  onPressed: s.disconnect, child: const Text('Disconnect')),
            ),
          ],
        ),
      ),
    );
  }
}

class _BluetoothBanner extends StatelessWidget {
  const _BluetoothBanner({required this.status});
  final BleStatus status;

  @override
  Widget build(BuildContext context) {
    final String msg;
    switch (status) {
      case BleStatus.poweredOff:
        msg = 'Bluetooth is turned off. Turn it on to scan and connect.';
        break;
      case BleStatus.unauthorized:
        msg = 'Bluetooth permission was denied. Allow "Nearby devices" for '
            'this app in the system settings.';
        break;
      case BleStatus.locationServicesDisabled:
        msg = 'Location services are off. Android needs them for Bluetooth '
            'scanning on older versions.';
        break;
      case BleStatus.unsupported:
        msg = 'This device does not support Bluetooth Low Energy.';
        break;
      default:
        msg = 'Bluetooth is not ready.';
    }
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: Icon(Icons.warning_amber, color: scheme.onErrorContainer),
        title: Text(msg, style: TextStyle(color: scheme.onErrorContainer)),
      ),
    );
  }
}
