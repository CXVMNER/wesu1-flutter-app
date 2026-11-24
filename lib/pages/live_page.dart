import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../watch_service.dart';
import '../widgets/sensor_chart.dart';

class LivePage extends StatelessWidget {
  const LivePage({super.key, required this.service});
  final WatchService service;

  @override
  Widget build(BuildContext context) {
    final s = service;
    final latest = s.latest;
    final textTheme = Theme.of(context).textTheme;

    if (s.link != LinkState.connected && latest == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Not connected.\nConnect to your watch on the Devices tab to see '
            'its data here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                s.link == LinkState.connected
                    ? '${s.rateHz.toStringAsFixed(1)} Hz  •  '
                        '${s.packetCount} packets'
                        '${s.badPackets > 0 ? '  •  ${s.badPackets} bad' : ''}'
                    : 'Disconnected (showing last data)',
                style: textTheme.bodyMedium,
              ),
            ),
            IconButton(
              tooltip: s.paused ? 'Resume' : 'Pause',
              icon: Icon(s.paused ? Icons.play_arrow : Icons.pause),
              onPressed: s.togglePause,
            ),
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: s.clearData,
            ),
          ],
        ),
        if (s.lastError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(s.lastError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (latest == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Waiting for the first packet…')),
          )
        else ...[
          _ValueCard(
            title: 'Accelerometer',
            unit: 'g',
            rows: [
              _Row('X', latest.axG, latest.ax),
              _Row('Y', latest.ayG, latest.ay),
              _Row('Z', latest.azG, latest.az),
            ],
            footer: '|a| = ${latest.accelMagnitudeG.toStringAsFixed(3)} g',
          ),
          _ValueCard(
            title: 'Gyroscope',
            unit: '°/s',
            rows: [
              _Row('X', latest.gxDps, latest.gx),
              _Row('Y', latest.gyDps, latest.gy),
              _Row('Z', latest.gzDps, latest.gz),
            ],
          ),
          SensorChart(
            title: 'Accelerometer (g)',
            x: s.history.map((e) => e.axG).toList(),
            y: s.history.map((e) => e.ayG).toList(),
            z: s.history.map((e) => e.azG).toList(),
            maxAbs: 2.2,
            window: WatchService.historyLimit,
          ),
          SensorChart(
            title: 'Gyroscope (°/s)',
            x: s.history.map((e) => e.gxDps).toList(),
            y: s.history.map((e) => e.gyDps).toList(),
            z: s.history.map((e) => e.gzDps).toList(),
            maxAbs: 300,
            window: WatchService.historyLimit,
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Last raw packet', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SelectableText(latest.hex,
                      style: const TextStyle(fontFamily: 'monospace')),
                  const SizedBox(height: 4),
                  Text('${latest.raw.length} bytes: six little-endian int16 '
                      '(ax ay az gx gy gz)',
                      style: textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
        Card(
          child: ExpansionTile(
            title: Text('Packet log (${s.log.length})'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy all'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(
                          text: s.log.map((e) => e.toLogLine()).join('\n')));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Log copied')));
                      }
                    },
                  ),
                ),
              ),
              SizedBox(
                height: 280,
                child: ListView.builder(
                  reverse: true,
                  itemCount: s.log.length,
                  itemBuilder: (_, i) {
                    final e = s.log[s.log.length - 1 - i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 2),
                      child: Text(e.toLogLine(),
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Card(
          child: ExpansionTile(
            title: const Text('Protocol details'),
            childrenPadding: const EdgeInsets.all(16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                'Service:\n00FFEEDD-CCBB-AA99-8877-665544332211\n\n'
                'IMU characteristic (Read + Notify):\n'
                '01FFEEDD-CCBB-AA99-8877-665544332211\n'
                '14 bytes: six little-endian int16 (ax ay az gx gy gz) '
                'plus a uint16 sequence\n\n'
                'Alert characteristic (Read + Notify):\n'
                '02FFEEDD-CCBB-AA99-8877-665544332211\n'
                '1 byte: 0x01 fall, 0x00 canceled\n\n'
                'Scales: accel 0.061 mg/LSB (±2 g), gyro 8.75 mdps/LSB '
                '(250 dps)',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row {
  _Row(this.axis, this.value, this.raw);
  final String axis;
  final double value;
  final int raw;
}

class _ValueCard extends StatelessWidget {
  const _ValueCard(
      {required this.title,
      required this.unit,
      required this.rows,
      this.footer});
  final String title;
  final String unit;
  final List<_Row> rows;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(width: 24, child: Text(r.axis)),
                    Expanded(
                      child: Text('${r.value.toStringAsFixed(3)} $unit',
                          style: textTheme.titleMedium?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                    ),
                    Text('raw ${r.raw}', style: textTheme.bodySmall),
                  ],
                ),
              ),
            if (footer != null) ...[
              const SizedBox(height: 4),
              Text(footer!, style: textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
