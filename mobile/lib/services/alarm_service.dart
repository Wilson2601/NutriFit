import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../app_keys.dart';
import 'api_service.dart';

/// Rings the user's alarms while the app is open (web and phone): a dialog with a repeating beep,
/// Stop and Snooze. On phones the same alarms are also scheduled as notifications by NotificationService.
class AlarmService {
  final ApiService api;
  AlarmService(this.api);

  Timer? _timer;
  String? _token;
  bool Function()? _signedIn;
  List<Map<String, dynamic>> _alarms = [];
  final Set<String> _fired = {};
  final Map<String, DateTime> _snoozed = {};
  final Map<String, String> _titles = {};
  bool _ringing = false;
  AudioPlayer? _player;
  Uint8List? _beep;

  Future<void> start(String token, bool Function() signedIn) async {
    _token = token;
    _signedIn = signedIn;
    await refresh();
    _timer ??= Timer.periodic(const Duration(seconds: 5), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _token = null;
    _alarms = [];
  }

  Future<void> refresh() async {
    final token = _token;
    if (token == null) return;
    try {
      final data = await api.reminders(token);
      setAlarms(data['reminders'] as List);
    } catch (_) {
      // Keep the alarms we already have if the server cannot be reached.
    }
  }

  /// Replaces the alarm list. Alarms whose time already passed today are marked as done so that
  /// opening the app (or saving the list) never rings an old alarm.
  void setAlarms(List<dynamic> list) {
    _alarms = [for (final e in list) Map<String, dynamic>.from(e as Map)];
    final now = DateTime.now();
    for (final a in _alarms) {
      _titles['${a['id']}'] = '${a['title']}';
      final minutes = _minutesOf(a['time']);
      if (minutes == null) continue;
      if (_nowMinutes(now) - minutes >= 1) _fired.add(_key(a, now));
    }
  }

  static int? _minutesOf(dynamic hhmm) {
    if (hhmm is! String || hhmm.length != 5) return null;
    final h = int.tryParse(hhmm.substring(0, 2));
    final m = int.tryParse(hhmm.substring(3, 5));
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  static int _nowMinutes(DateTime now) => now.hour * 60 + now.minute;
  static String _key(Map<String, dynamic> a, DateTime now) => '${a['id']}|${a['time']}|${now.year}-${now.month}-${now.day}';

  void _tick() {
    if (_signedIn != null && !_signedIn!()) {
      stop();
      return;
    }
    if (_ringing) return;
    final now = DateTime.now();

    for (final a in _alarms) {
      if (a['enabled'] != true) continue;
      final minutes = _minutesOf(a['time']);
      if (minutes == null) continue;
      final late = _nowMinutes(now) - minutes;
      final key = _key(a, now);
      // A background browser tab only runs timers about once a minute, so allow a short window.
      if (late >= 0 && late <= 2 && !_fired.contains(key)) {
        _fired.add(key);
        ringNow('${a['title']}', '${a['id']}', '${a['time']}');
        return;
      }
    }

    final due = _snoozed.entries.where((e) => !now.isBefore(e.value)).toList();
    if (due.isNotEmpty) {
      final id = due.first.key;
      _snoozed.remove(id);
      ringNow(_titles[id] ?? 'Alarm', id);
    }
  }

  /// Shows the alarm dialog and plays the beep. Also used by the "Test alarm" button.
  Future<void> ringNow(String title, [String? id, String? time]) async {
    if (_ringing) return;
    final context = navigatorKey.currentContext;
    if (context == null) return;
    _ringing = true;
    await _startSound();
    bool snooze = false;
    try {
      if (!context.mounted) return;
      snooze = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: Text('⏰ $title'),
              content: Text(time == null ? 'Your alarm is ringing.' : 'It is $time.'),
              actions: [
                if (id != null) TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Snooze 5 min')),
                ElevatedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Stop')),
              ],
            ),
          ) ??
          false;
    } finally {
      await _stopSound();
      _ringing = false;
    }
    if (snooze && id != null) _snoozed[id] = DateTime.now().add(const Duration(minutes: 5));
  }

  Future<void> _startSound() async {
    try {
      _player ??= AudioPlayer();
      await _player!.setReleaseMode(ReleaseMode.loop);
      await _player!.play(BytesSource(_beepBytes(), mimeType: 'audio/wav'));
    } catch (_) {
      // No sound is not fatal: the dialog is still shown.
    }
  }

  Future<void> _stopSound() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  /// Three short beeps and a pause, generated in code so no sound file is needed.
  Uint8List _beepBytes() {
    if (_beep != null) return _beep!;
    const rate = 22050;
    final pcm = <int>[];
    void tone(double seconds, double hz) {
      final n = (rate * seconds).round();
      for (var i = 0; i < n; i++) {
        final fade = math.min(1.0, math.min(i, n - i) / 200);
        pcm.add((math.sin(2 * math.pi * hz * i / rate) * 0.6 * 32767 * fade).round());
      }
    }

    void silence(double seconds) => pcm.addAll(List.filled((rate * seconds).round(), 0));
    for (var i = 0; i < 3; i++) {
      tone(0.22, 880);
      silence(0.12);
    }
    silence(0.5);

    final data = ByteData(44 + pcm.length * 2);
    void text(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    text(0, 'RIFF');
    data.setUint32(4, 36 + pcm.length * 2, Endian.little);
    text(8, 'WAVE');
    text(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    text(36, 'data');
    data.setUint32(40, pcm.length * 2, Endian.little);
    for (var i = 0; i < pcm.length; i++) {
      data.setInt16(44 + i * 2, pcm[i], Endian.little);
    }
    return _beep = data.buffer.asUint8List();
  }
}
