import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models.dart';
import 'notifier.dart';
import 'storage.dart';

enum LinkState { disconnected, connecting, connected }

/// GATT UUIDs from the firmware. BlueNRG takes 128-bit UUIDs little-endian,
/// so the bytes 11 22 33 ... FF 00 in the firmware are the UUID below, reversed.
/// The second pair is the un-reversed form, tried automatically as a fallback
/// in case the stack exposes them the other way round.
final List<(Uuid, Uuid)> kUuidCandidates = [
  (
    Uuid.parse('00FFEEDD-CCBB-AA99-8877-665544332211'),
    Uuid.parse('01FFEEDD-CCBB-AA99-8877-665544332211')
  ),
  (
    Uuid.parse('11223344-5566-7788-99AA-BBCCDDEEFF00'),
    Uuid.parse('11223344-5566-7788-99AA-BBCCDDEEFF01')
  ),
];

/// Alert characteristic (...FF02). Same endianness pair as the IMU
/// characteristic: reversed form first, raw firmware bytes second.
/// Payload is one byte: 0x01 fall, 0x00 canceled.
final List<Uuid> kAlertUuids = [
  Uuid.parse('02FFEEDD-CCBB-AA99-8877-665544332211'),
  Uuid.parse('11223344-5566-7788-99AA-BBCCDDEEFF02'),
];

class WatchService extends ChangeNotifier {
  WatchService({FlutterReactiveBle? ble}) : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;
  final Storage _storage = Storage();
  final Notifier _notifier = Notifier();

  // ---- state shown in the UI ----
  AppSettings settings = AppSettings();
  List<SavedDevice> saved = [];
  BleStatus bleStatus = BleStatus.unknown;
  bool scanning = false;
  final Map<String, DiscoveredDevice> found = {};

  LinkState link = LinkState.disconnected;
  String? activeId; // the watch we want to stay connected to
  String? activeName;
  String? lastError;
  bool reconnecting = false;

  ImuSample? latest;
  final List<ImuSample> history = []; // for charts
  final List<ImuSample> log = []; // raw packet log
  static const int historyLimit = 200;
  static const int logLimit = 300;
  int packetCount = 0;
  int badPackets = 0;
  double rateHz = 0;
  bool paused = false;

  /// On-screen alarm. Set for every alert packet, including the button
  /// byte 0x00. Cleared only when the user dismisses it.
  bool fallAlert = false;
  String? alarmText;

  /// How many non-IMU notify characteristics were subscribed.
  int alertChars = 0;
  final List<String> alarmLog = [];

  String? get notificationProblem => _notifier.lastError;

  // ---- internals ----
  bool _inited = false;
  StreamSubscription<BleStatus>? _statusSub;
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<List<int>>? _alertSub;
  final List<StreamSubscription<List<int>>> _alertSubs = [];
  Timer? _alertRetryTimer;
  Timer? _scanTimer;
  Timer? _reconnectTimer;
  Timer? _subRetryTimer;
  Timer? _notifyTimer;
  int _retry = 0;
  int _candidateIndex = 0;
  int _subAttempts = 0;
  int _bondWaits = 0;
  bool _alertFallbackTried = false;
  DateTime _lastMotionAlert = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFallNotify = DateTime.fromMillisecondsSinceEpoch(0);
  final List<DateTime> _recent = [];

  List<DiscoveredDevice> get visibleFound {
    final list = found.values.where((d) {
      if (!settings.onlyWesu) return true;
      return d.name.toUpperCase().startsWith('WESU');
    }).toList();
    list.sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  // ------------------------------------------------------------------
  // Startup
  // ------------------------------------------------------------------
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    settings = await _storage.loadSettings();
    saved = await _storage.loadDevices();
    await _notifier.init();
    if (_notifier.lastError != null) lastError = _notifier.lastError;
    await requestPermissions();
    _statusSub = _ble.statusStream.listen(_onStatus);

    if (settings.autoConnect && saved.isNotEmpty) {
      final sorted = [...saved]
        ..sort((a, b) => b.lastConnected.compareTo(a.lastConnected));
      activeId = sorted.first.id;
      activeName = sorted.first.name;
    }
    notifyListeners();
  }

  Future<void> requestPermissions() async {
    try {
      // Results are intentionally ignored: which of these exist depends on the
      // Android version, and BleStatus tells us if Bluetooth is usable.
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
        Permission.notification,
      ].request();
    } catch (e) {
      debugPrint('Permission request failed: $e');
    }
  }

  void _onStatus(BleStatus s) {
    bleStatus = s;
    if (s != BleStatus.ready && scanning) stopScan();
    if (s == BleStatus.ready &&
        activeId != null &&
        link == LinkState.disconnected &&
        _connSub == null &&
        _reconnectTimer == null) {
      _connect(activeId!, activeName);
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Scanning
  // ------------------------------------------------------------------
  Future<void> startScan() async {
    if (scanning) return;
    await requestPermissions();
    found.clear();
    scanning = true;
    lastError = null;
    notifyListeners();

    _scanSub = _ble
        .scanForDevices(
          withServices: const [], // the watch doesn't advertise its service UUID
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: false,
        )
        .listen(
      (d) {
        found[d.id] = d;
        _notifySoon();
      },
      onError: (Object e) {
        lastError = 'Scan failed: $e';
        stopScan();
      },
    );
    _scanTimer = Timer(const Duration(seconds: 12), stopScan);
  }

  void stopScan() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanSub?.cancel();
    _scanSub = null;
    if (scanning) {
      scanning = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------
  // Connection
  // ------------------------------------------------------------------
  /// User-initiated connect (from the UI).
  void connect(String id, {String? name}) {
    _retry = 0;
    _connect(id, name);
  }

  void _connect(String id, String? name) {
    stopScan();
    _teardownLink();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    activeId = id;
    activeName = name ?? _nameFor(id);
    link = LinkState.connecting;
    reconnecting = false;
    notifyListeners();

    _connSub = _ble
        .connectToDevice(
          id: id,
          connectionTimeout: const Duration(seconds: 12),
        )
        .listen(
          _onConnUpdate,
          onError: (Object e) => _onDrop('$e'),
        );
  }

  /// User-initiated disconnect. Stops auto-reconnecting.
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    activeId = null;
    activeName = null;
    reconnecting = false;
    _retry = 0;
    _teardownLink();
    link = LinkState.disconnected;
    notifyListeners();
  }

  void _teardownLink() {
    _dataSub?.cancel();
    _dataSub = null;
    _alertSub?.cancel();
    _alertSub = null;
    for (final sub in _alertSubs) {
      sub.cancel();
    }
    _alertSubs.clear();
    alertChars = 0;
    _alertRetryTimer?.cancel();
    _alertRetryTimer = null;
    _connSub?.cancel();
    _connSub = null;
    _subRetryTimer?.cancel();
    _subRetryTimer = null;
  }

  void _onConnUpdate(ConnectionStateUpdate u) {
    switch (u.connectionState) {
      case DeviceConnectionState.connecting:
        link = LinkState.connecting;
        _notifySoon();
        break;
      case DeviceConnectionState.connected:
        _onConnected(u.deviceId);
        break;
      case DeviceConnectionState.disconnecting:
        break;
      case DeviceConnectionState.disconnected:
        _onDrop(u.failure?.message);
        break;
    }
  }

  void _onConnected(String id) {
    _retry = 0;
    reconnecting = false;
    link = LinkState.connected;
    lastError = null;
    _remember(id);
    if (settings.connectionAlerts) {
      _notifier.connection('Watch connected', 'Connected to ${_nameFor(id)}');
    }
    _candidateIndex = 0;
    _subAttempts = 0;
    _bondWaits = 0;
    _alertFallbackTried = false;
    _subscribe(id);
    notifyListeners();
  }

  void _onDrop(String? reason) {
    final wasConnected = link == LinkState.connected;
    _teardownLink();
    link = LinkState.disconnected;
    if (reason != null && reason.isNotEmpty) lastError = reason;
    if (wasConnected && settings.connectionAlerts) {
      _notifier.connection('Watch disconnected',
          '${activeName ?? 'Your watch'} lost connection. Reconnecting…');
    }
    final id = activeId;
    if (id != null) {
      _scheduleReconnect(id);
    } else {
      notifyListeners();
    }
  }

  void _scheduleReconnect(String id) {
    reconnecting = true;
    _retry++;
    final secs = math.min(3 * _retry, 20);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: secs), () {
      _reconnectTimer = null;
      if (activeId == id) _connect(id, activeName);
    });
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Data
  // ------------------------------------------------------------------
  Future<void> _subscribe(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (activeId != id || link != LinkState.connected) return;

    _alertFallbackTried = false;
    // Discover and hook the alarm characteristic before the IMU stream.
    await _subscribeAlert(id);
    if (activeId != id || link != LinkState.connected) return;

    final pair = kUuidCandidates[_candidateIndex];
    _dataSub?.cancel();
    _dataSub = _ble
        .subscribeToCharacteristic(QualifiedCharacteristic(
          serviceId: pair.$1,
          characteristicId: pair.$2,
          deviceId: id,
        ))
        .listen(_onData, onError: (Object e) => _onSubscribeError(id, e));
  }

  bool _isAlertUuid(Uuid id) {
    for (final candidate in kAlertUuids) {
      if (candidate == id) return true;
    }
    return false;
  }

  bool _isImuUuid(Uuid id) {
    for (final pair in kUuidCandidates) {
      if (pair.$2 == id) return true;
    }
    return false;
  }

  void _rememberAlarm(String line) {
    alarmLog.insert(0, '${fmtTime(DateTime.now())}  $line');
    if (alarmLog.length > 30) alarmLog.removeLast();
  }

  /// Subscribe to every notify characteristic that is not the IMU stream.
  /// Discovery avoids guessing the alert UUID. The hardcoded UUID is only
  /// a fallback when discovery finds nothing.
  Future<void> _subscribeAlert(String id) async {
    _alertRetryTimer?.cancel();
    _alertSub?.cancel();
    _alertSub = null;
    for (final sub in _alertSubs) {
      sub.cancel();
    }
    _alertSubs.clear();
    alertChars = 0;
    if (activeId != id || link != LinkState.connected) return;

    var hooked = 0;
    try {
      await _ble.discoverAllServices(id);
      if (activeId != id || link != LinkState.connected) return;
      final services = await _ble.getDiscoveredServices(id);
      for (final service in services) {
        for (final c in service.characteristics) {
          if (!_isAlertUuid(c.id)) continue;
          if (!c.isNotifiable && !c.isIndicatable) continue;
          hooked++;
          _alertSubs.add(c.subscribe().listen(
                (data) => _onAlert(data, from: c.id.toString()),
                onError: (Object e) => _onAlertSubscribeError(id, e),
              ));
        }
      }
    } catch (e) {
      debugPrint('service discovery failed: $e');
      _onAlertSubscribeError(id, e);
    }

    alertChars = hooked;
    if (hooked == 0) {
      _subscribeHardcodedAlert(id);
    } else {
      notifyListeners();
    }
  }

  void _subscribeHardcodedAlert(String id) {
    if (activeId != id || link != LinkState.connected) return;
    final serviceId = kUuidCandidates[_candidateIndex].$1;
    final alertId = kAlertUuids[_candidateIndex];
    _alertSub?.cancel();
    _alertSub = _ble
        .subscribeToCharacteristic(QualifiedCharacteristic(
          serviceId: serviceId,
          characteristicId: alertId,
          deviceId: id,
        ))
        .listen((data) => _onAlert(data, from: alertId.toString()),
            onError: (Object e) => _onAlertSubscribeError(id, e));
    alertChars = 1;
    notifyListeners();
  }

  /// Alert notify is a different characteristic from the IMU stream.
  /// A failure here must not rotate the IMU UUID (that would drop live data).
  void _onAlertSubscribeError(String id, Object e) {
    debugPrint('ALERT RAW: $data');
    debugPrint('alert subscribe failed: $e');
    if (activeId != id || link != LinkState.connected) return;
    final full = e.toString();
    if (full.contains('Bonding is in progress')) {
      lastError = 'Pairing with the watch… accept the pairing request if '
          'Android shows one.';
      _alertRetryTimer?.cancel();
      _alertRetryTimer = Timer(const Duration(milliseconds: 1500), () {
        _alertRetryTimer = null;
        if (activeId == id && link == LinkState.connected) _subscribeAlert(id);
      });
      notifyListeners();
      return;
    }
    if (_alertFallbackTried) {
      lastError = 'Could not listen for the alarm characteristic.';
      notifyListeners();
      return;
    }
    _alertFallbackTried = true;
    final other = (_candidateIndex + 1) % kAlertUuids.length;
    final serviceId = kUuidCandidates[_candidateIndex].$1;
    _alertSub?.cancel();
    _alertSub = _ble
        .subscribeToCharacteristic(QualifiedCharacteristic(
          serviceId: serviceId,
          characteristicId: kAlertUuids[other],
          deviceId: id,
        ))
        .listen((data) => _onAlert(data, from: kAlertUuids[other].toString()),
            onError: (Object e2) {
      lastError = 'Could not listen for the alarm characteristic.';
      debugPrint('alert fallback failed: $e2');
      notifyListeners();
    });
    notifyListeners();
  }

  void _onAlert(List<int> data, {String? from}) {
    if (data.isEmpty) return;
    final hex = data
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    final code = data[0];
    // The watch button sends 0x00. The on-watch fall detector sends 0x01.
    // Either one must show up. 0x00 used to be ignored unless a fall was
    // already on screen, so a button press did nothing.
    final text = switch (code) {
    0x01 => 'Fall detected',
    0x00 => 'Fall canceled on the watch',
    0x02 => 'Button pressed on the watch',
    _ => 'Watch alarm',
  };
    alarmText = '$text ($hex)';
    fallAlert = true;
    _rememberAlarm(from == null ? alarmText! : '$alarmText  $from');

    final now = DateTime.now();
    if (now.difference(_lastFallNotify).inMilliseconds > 800) {
      _lastFallNotify = now;
      _notifier.fall('WESU1', alarmText!);
      if (_notifier.lastError != null) lastError = _notifier.lastError;
    }
    notifyListeners();
  }

  void clearFallAlert() {
    fallAlert = false;
    alarmText = null;
    notifyListeners();
  }

  void _onSubscribeError(String id, Object e) {
    final full = e.toString();

    // The watch asks to pair as soon as it connects. Android refuses GATT
    // operations until bonding finishes, so just wait and try again.
    if (full.contains('Bonding is in progress')) {
      _bondWaits++;
      if (_bondWaits > 40) {
        lastError = 'Pairing seems stuck. In Android Bluetooth settings, '
            'forget "WESU1-Lab", then reconnect from this app.';
        notifyListeners();
        return;
      }
      lastError = 'Pairing with the watch… accept the pairing request if '
          'Android shows one.';
      _subRetryTimer?.cancel();
      _subRetryTimer =
          Timer(const Duration(milliseconds: 1500), () => _subscribe(id));
      notifyListeners();
      return;
    }

    var short = full.split('\n').first;
    if (short.length > 200) short = '${short.substring(0, 200)}…';
    lastError = 'Could not subscribe to the IMU characteristic: $short';
    _subAttempts++;
    if (_subAttempts >= 6) {
      notifyListeners();
      return;
    }
    _candidateIndex = (_candidateIndex + 1) % kUuidCandidates.length;
    _subRetryTimer?.cancel();
    _subRetryTimer = Timer(const Duration(seconds: 1), () => _subscribe(id));
    notifyListeners();
  }

  void _onData(List<int> data) {
    // The alert characteristic is 1 byte. If that notify lands on this
    // callback it used to be counted as a bad packet and ignored.
    if (data.length == 1) {
      _onAlert(data);
      return;
    }
    final s = ImuSample.parse(data);
    if (s == null) {
      badPackets++;
      _notifySoon();
      return;
    }
    packetCount++;
    if (lastError != null) lastError = null;

    _recent.add(s.time);
    if (_recent.length > 20) _recent.removeAt(0);
    if (_recent.length >= 2) {
      final dt = _recent.last.difference(_recent.first).inMicroseconds / 1e6;
      rateHz = dt > 0 ? (_recent.length - 1) / dt : 0;
    }

    if (!paused) {
      latest = s;
      history.add(s);
      if (history.length > historyLimit) history.removeAt(0);
      log.add(s);
      if (log.length > logLimit) log.removeAt(0);
    }

    // Motion alert (with a cooldown so the phone isn't spammed).
    if (settings.motionAlerts &&
        s.accelMagnitudeG >= settings.motionThresholdG &&
        DateTime.now().difference(_lastMotionAlert).inSeconds >= 15) {
      _lastMotionAlert = DateTime.now();
      _notifier.motion('Motion detected',
          'Acceleration reached ${s.accelMagnitudeG.toStringAsFixed(2)} g');
    }

    notifyListeners();
  }

  void clearData() {
    history.clear();
    log.clear();
    latest = null;
    packetCount = 0;
    badPackets = 0;
    rateHz = 0;
    _recent.clear();
    notifyListeners();
  }

  void togglePause() {
    paused = !paused;
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Remembered devices & settings
  // ------------------------------------------------------------------
  String _nameFor(String id) {
    final n = found[id]?.name;
    if (n != null && n.isNotEmpty) return n;
    for (final d in saved) {
      if (d.id == id) return d.name;
    }
    return id;
  }

  void _remember(String id) {
    final name = _nameFor(id);
    final idx = saved.indexWhere((d) => d.id == id);
    if (idx >= 0) {
      saved[idx].lastConnected = DateTime.now();
      if (name != id) saved[idx].name = name;
    } else {
      saved.add(SavedDevice(
          id: id, name: name, lastConnected: DateTime.now()));
    }
    _storage.saveDevices(saved);
  }

  void forget(String id) {
    if (activeId == id) disconnect();
    saved.removeWhere((d) => d.id == id);
    _storage.saveDevices(saved);
    notifyListeners();
  }

  void updateSettings(void Function(AppSettings) change) {
    change(settings);
    _storage.saveSettings(settings);
    notifyListeners();
  }

  Future<void> sendTestNotification() async {
    await _notifier.test();
    if (_notifier.lastError != null) lastError = _notifier.lastError;
    alarmText = 'Test notification';
    fallAlert = true;
    notifyListeners();
  }

  // ------------------------------------------------------------------
  void _notifySoon() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 150), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    stopScan();
    _teardownLink();
    _reconnectTimer?.cancel();
    _notifyTimer?.cancel();
    super.dispose();
  }
}
