import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_time_kit/screen_time_kit.dart';

void main() => runApp(const ScreenTimeDemoApp());

class ScreenTimeDemoApp extends StatelessWidget {
  const ScreenTimeDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'screen_time_kit demo',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _screenTime = ScreenTimeKit();

  PermissionStatus? _status;
  List<AppUsageInfo> _usage = const [];
  List<UsageSummary> _dailySummaries = const [];
  List<AppLimit> _limits = const [];
  String _log = '';
  bool _busy = false;

  StreamSubscription<AppLimitEvent>? _limitSub;

  @override
  void initState() {
    super.initState();
    _limitSub = _screenTime.onLimitReached.listen((event) {
      _appendLog(
        '⛔ Limit reached: ${event.packageName} (${event.limit.inMinutes}m)',
      );
    }, onError: (Object e) => _appendLog('Limit stream error: $e'));
    _refreshStatus();
  }

  @override
  void dispose() {
    _limitSub?.cancel();
    _screenTime.dispose();
    super.dispose();
  }

  void _appendLog(String line) {
    if (!mounted) return;
    setState(() => _log = '$line\n$_log');
  }

  /// Wraps an action with busy state + typed error reporting.
  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _appendLog('✓ $label');
    } on PermissionDeniedException catch (e) {
      _appendLog('🔒 $label — permission denied: ${e.message}');
    } on PlatformNotSupportedException catch (e) {
      _appendLog('🚫 $label — not supported: ${e.message}');
    } on EntitlementMissingException catch (e) {
      _appendLog('🍏 $label — entitlement missing: ${e.message}');
    } on ScreenTimeException catch (e) {
      _appendLog('⚠️ $label — ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshStatus() => _run('Check permission', () async {
    final status = await _screenTime.checkPermissionStatus();
    setState(() => _status = status);
  });

  Future<void> _requestPermission() => _run('Request permission', () async {
    final status = await _screenTime.requestPermission();
    setState(() => _status = status);
  });

  Future<void> _loadUsage() => _run('Load 24h usage', () async {
    final since = DateTime.now().subtract(const Duration(days: 1));
    final usage = await _screenTime.getAppUsage(since: since);
    usage.sort((a, b) => b.usageDuration.compareTo(a.usageDuration));
    setState(() => _usage = usage);
  });

  Future<void> _loadSummaries() => _run('Aggregate 7-day summary', () async {
    final since = DateTime.now().subtract(const Duration(days: 7));
    final summaries = await _screenTime.getDailySummaries(since: since);
    setState(() => _dailySummaries = summaries);
  });

  Future<void> _addSampleLimit() => _run('Set 1h Instagram limit', () async {
    await _screenTime.setAppLimit(
      'com.instagram.android',
      const Duration(hours: 1),
    );
    await _refreshLimits();
  });

  Future<void> _refreshLimits() => _run('Load active limits', () async {
    final limits = await _screenTime.getActiveLimits();
    setState(() => _limits = limits);
  });

  Future<void> _clearLimits() => _run('Clear all limits', () async {
    await _screenTime.clearAllLimits();
    await _refreshLimits();
  });

  Future<void> _startFocus() => _run('Start 25m focus mode', () async {
    await _screenTime.startFocusMode(
      apps: const ['com.instagram.android', 'com.zhiliaoapp.musically'],
      duration: const Duration(minutes: 25),
    );
  });

  Future<void> _stopFocus() =>
      _run('Stop focus mode', _screenTime.stopFocusMode);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('screen_time_kit'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusCard(),
          const SizedBox(height: 12),
          _section('1 · Permission', [
            _button('Check status', _refreshStatus),
            _button('Request / open settings', _requestPermission),
          ]),
          _section('2 · Usage stats', [_button('Load last 24h', _loadUsage)]),
          if (_usage.isNotEmpty) _usageList(),
          _section('3 · Summaries (pure Dart)', [
            _button('Aggregate 7 days', _loadSummaries),
          ]),
          if (_dailySummaries.isNotEmpty) _summaryList(),
          _section('4 · App limits', [
            _button('Add 1h IG limit', _addSampleLimit),
            _button('Refresh', _refreshLimits),
            _button('Clear all', _clearLimits),
          ]),
          if (_limits.isNotEmpty) _limitsList(),
          _section('5 · Focus mode', [
            _button('Start 25m', _startFocus),
            _button('Stop', _stopFocus),
          ]),
          const SizedBox(height: 16),
          _logCard(),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final status = _status;
    final color = switch (status) {
      PermissionStatus.granted => Colors.green,
      null => Colors.grey,
      _ => Colors.orange,
    };
    return Card(
      color: color.withValues(alpha: 0.1),
      child: ListTile(
        leading: Icon(Icons.shield_outlined, color: color),
        title: const Text('Permission status'),
        subtitle: Text(status?.name ?? 'unknown'),
      ),
    );
  }

  Widget _section(String title, List<Widget> buttons) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: buttons),
        ],
      ),
    );
  }

  Widget _button(String label, Future<void> Function() onPressed) {
    return FilledButton.tonal(
      onPressed: _busy ? null : () => onPressed(),
      child: Text(label),
    );
  }

  Widget _usageList() {
    return Card(
      child: Column(
        children: [
          for (final app in _usage.take(15))
            ListTile(
              dense: true,
              title: Text(app.appName),
              subtitle: Text(app.packageName),
              trailing: Text('${app.usageDuration.inMinutes}m'),
            ),
        ],
      ),
    );
  }

  Widget _summaryList() {
    return Card(
      child: Column(
        children: [
          for (final s in _dailySummaries)
            ListTile(
              dense: true,
              title: Text('${s.start.year}-${s.start.month}-${s.start.day}'),
              subtitle: Text('${s.perApp.length} apps'),
              trailing: Text('${s.total.inMinutes}m'),
            ),
        ],
      ),
    );
  }

  Widget _limitsList() {
    return Card(
      child: Column(
        children: [
          for (final limit in _limits)
            ListTile(
              dense: true,
              leading: const Icon(Icons.timer_outlined),
              title: Text(limit.packageName),
              trailing: Text('${limit.limit.inMinutes}m/day'),
            ),
        ],
      ),
    );
  }

  Widget _logCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Log', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              _log.isEmpty ? 'Actions will appear here.' : _log,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
