import 'package:flutter/material.dart';

import 'pages/devices_page.dart';
import 'pages/live_page.dart';
import 'pages/settings_page.dart';
import 'watch_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(WesuApp(service: WatchService()));
}

class WesuApp extends StatelessWidget {
  const WesuApp({super.key, required this.service});
  final WatchService service;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WESU1 Watch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: HomeShell(service: service),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.service});
  final WatchService service;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.service.init();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.service,
      builder: (context, _) {
        final s = widget.service;
        final pages = <Widget>[
          DevicesPage(service: s),
          LivePage(service: s),
          SettingsPage(service: s),
        ];
        final titles = ['Devices', 'Live data', 'Settings'];
        return Scaffold(
          appBar: AppBar(
            title: Text(titles[_index]),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Icon(
                  s.link == LinkState.connected
                      ? Icons.bluetooth_connected
                      : s.link == LinkState.connecting
                          ? Icons.bluetooth_searching
                          : Icons.bluetooth_disabled,
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (s.fallAlert)
                  _AlarmBar(
                    text: s.alarmText ?? 'Alarm from the watch',
                    problem: s.notificationProblem,
                    onDismiss: s.clearFallAlert,
                  ),
                Expanded(child: pages[_index]),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.watch_outlined),
                  selectedIcon: Icon(Icons.watch),
                  label: 'Devices'),
              NavigationDestination(
                  icon: Icon(Icons.show_chart),
                  selectedIcon: Icon(Icons.stacked_line_chart),
                  label: 'Live'),
              NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings'),
            ],
          ),
        );
      },
    );
  }
}

class _AlarmBar extends StatelessWidget {
  const _AlarmBar({
    required this.text,
    required this.onDismiss,
    this.problem,
  });
  final String text;
  final String? problem;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: scheme.onErrorContainer)),
                  if (problem != null) ...[
                    const SizedBox(height: 4),
                    Text(problem!,
                        style: TextStyle(color: scheme.onErrorContainer)),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              icon: Icon(Icons.close, color: scheme.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}
