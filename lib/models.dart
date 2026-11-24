import 'dart:math' as math;
import 'dart:typed_data';

String _two(int n) => n.toString().padLeft(2, '0');

String fmtTime(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';

String fmtAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// One 12-byte notification from the watch's IMU characteristic.
///
/// Layout (little-endian int16 x6), matching `read_motion()` in the firmware:
///   [0..1] accel X  [2..3] accel Y  [4..5] accel Z
///   [6..7] gyro  X  [8..9] gyro  Y  [10..11] gyro Z
class ImuSample {
  ImuSample({
    required this.time,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.raw,
  });

  final DateTime time;
  final int ax, ay, az, gx, gy, gz;
  final Uint8List raw;

  // LSM6DS3 sensitivities for the firmware's settings:
  // accel +/-2 g  -> 0.061 mg/LSB, gyro 250 dps -> 8.75 mdps/LSB
  static const double gPerLsb = 0.000061;
  static const double dpsPerLsb = 0.00875;

  double get axG => ax * gPerLsb;
  double get ayG => ay * gPerLsb;
  double get azG => az * gPerLsb;
  double get gxDps => gx * dpsPerLsb;
  double get gyDps => gy * dpsPerLsb;
  double get gzDps => gz * dpsPerLsb;

  double get accelMagnitudeG =>
      math.sqrt(axG * axG + ayG * ayG + azG * azG);

  String get hex => raw
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  static ImuSample? parse(List<int> data) {
    if (data.length < 12) return null;
    final bytes = Uint8List.fromList(data);
    final v = ByteData.sublistView(bytes);
    return ImuSample(
      time: DateTime.now(),
      ax: v.getInt16(0, Endian.little),
      ay: v.getInt16(2, Endian.little),
      az: v.getInt16(4, Endian.little),
      gx: v.getInt16(6, Endian.little),
      gy: v.getInt16(8, Endian.little),
      gz: v.getInt16(10, Endian.little),
      raw: bytes,
    );
  }

  String toLogLine() =>
      '${fmtTime(time)}  a=[$ax $ay $az]  g=[$gx $gy $gz]  $hex';
}

/// A watch the app remembers between launches.
class SavedDevice {
  SavedDevice({
    required this.id,
    required this.name,
    required this.lastConnected,
  });

  final String id; // MAC address on Android, UUID on iOS
  String name;
  DateTime lastConnected;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lastConnected': lastConnected.millisecondsSinceEpoch,
      };

  factory SavedDevice.fromJson(Map<String, dynamic> j) => SavedDevice(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Unknown',
        lastConnected: DateTime.fromMillisecondsSinceEpoch(
            (j['lastConnected'] as num?)?.toInt() ?? 0),
      );
}

class AppSettings {
  bool connectionAlerts = true;
  bool motionAlerts = false;
  double motionThresholdG = 1.8;
  bool autoConnect = true;
  bool onlyWesu = true;

  Map<String, dynamic> toJson() => {
        'connectionAlerts': connectionAlerts,
        'motionAlerts': motionAlerts,
        'motionThresholdG': motionThresholdG,
        'autoConnect': autoConnect,
        'onlyWesu': onlyWesu,
      };

  static AppSettings fromJson(Map<String, dynamic> j) {
    final s = AppSettings();
    s.connectionAlerts = (j['connectionAlerts'] as bool?) ?? s.connectionAlerts;
    s.motionAlerts = (j['motionAlerts'] as bool?) ?? s.motionAlerts;
    s.motionThresholdG =
        (j['motionThresholdG'] as num?)?.toDouble() ?? s.motionThresholdG;
    s.autoConnect = (j['autoConnect'] as bool?) ?? s.autoConnect;
    s.onlyWesu = (j['onlyWesu'] as bool?) ?? s.onlyWesu;
    return s;
  }
}
