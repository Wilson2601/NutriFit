import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/alarm_service.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../theme.dart';

const _cardBgs = [AppColors.blue100, AppColors.orange100, Colors.white, AppColors.purple100, Colors.white, AppColors.yellow100];

/// "HH:MM" (24-hour) <-> TimeOfDay
TimeOfDay _parse(String hhmm) => TimeOfDay(hour: int.parse(hhmm.substring(0, 2)), minute: int.parse(hhmm.substring(3, 5)));
String _format24(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Alarms: the user picks the time and name, and the app rings at that time.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<dynamic> _reminders = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    try {
      final data = await api.reminders(auth.token!);
      if (mounted) setState(() { _reminders = data['reminders']; _loading = false; _error = null; });
      await _syncDevice();
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  /// Keeps the in-app alarm clock and the phone's scheduled notifications equal to what is saved.
  Future<void> _syncDevice() async {
    if (!mounted) return;
    context.read<AlarmService>().setAlarms(_reminders);
    try {
      final notifications = context.read<NotificationService>();
      for (final r in _reminders) {
        if (r['enabled'] == true) {
          await notifications.scheduleReminder(
            reminderId: r['id'], timeLabel: r['timeLabel'], title: r['title'], subtitle: r['subtitle'] ?? '',
          );
        } else {
          await notifications.cancelReminder(r['id']);
        }
      }
    } catch (_) {
      // Phone scheduling is best effort (it is not available in the browser).
    }
  }

  Future<void> _run(Future<void> Function(String token, ApiService api) action) async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    try {
      await action(auth.token!, api);
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _toggle(Map r, bool value) async {
    setState(() => r['enabled'] = value);
    await _run((token, api) async { await api.updateReminder(token, r['id'], {'enabled': value}); });
  }

  /// Add (r == null) or edit an alarm.
  Future<void> _edit(Map? r) async {
    final name = TextEditingController(text: r == null ? '' : '${r['title']}');
    var time = r == null ? TimeOfDay.now() : _parse('${r['time']}');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(r == null ? 'New alarm' : 'Edit alarm'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: name, maxLength: 40, decoration: const InputDecoration(labelText: 'Name', hintText: 'Cook dinner')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                final picked = await showTimePicker(context: ctx, initialTime: time);
                if (picked != null) setLocal(() => time = picked);
              },
              child: Text('🕒  ${time.format(ctx)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ]),
          actions: [
            if (r != null) TextButton(onPressed: () => Navigator.of(ctx).pop('delete'), child: const Text('Delete', style: TextStyle(color: AppColors.red600))),
            TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop('save'), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;

    if (result == 'delete' && r != null) {
      final notifications = context.read<NotificationService>();
      await _run((token, api) async { await api.deleteReminder(token, r['id']); });
      try { await notifications.cancelReminder(r['id']); } catch (_) {}
      return;
    }
    final title = name.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Please give the alarm a name.');
      return;
    }
    if (r == null) {
      await _run((token, api) async { await api.createReminder(token, title, _format24(time)); });
    } else {
      await _run((token, api) async { await api.updateReminder(token, r['id'], {'title': title, 'time': _format24(time)}); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: AppColors.green100, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.arrow_back, size: 18),
                  ),
                ),
                const SizedBox(width: 14),
                const Text('Alarms ⏰', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 8),
              const Text('Tap an alarm to change its time or name. It rings at that time while NutriFit is open, and the phone app also schedules it as a notification.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.35)),
              const SizedBox(height: 14),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: const TextStyle(color: AppColors.red600))),
              if (_loading) const Expanded(child: Center(child: CircularProgressIndicator())),
              if (!_loading)
                Expanded(
                  child: _reminders.isEmpty
                      ? const Center(child: Text('No alarms yet. Tap "Add alarm" to create one.', style: TextStyle(color: AppColors.muted)))
                      : ListView.separated(
                          itemCount: _reminders.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            final r = _reminders[i] as Map;
                            final on = r['enabled'] == true;
                            return AppCard(
                              background: on ? _cardBgs[i % _cardBgs.length] : Colors.white,
                              onTap: () => _edit(r),
                              child: Row(children: [
                                Container(
                                  width: 46, height: 46,
                                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
                                  child: Center(child: Text(r['icon'] ?? '⏰', style: const TextStyle(fontSize: 20))),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(_parse('${r['time']}').format(context),
                                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: on ? AppColors.green700 : AppColors.muted)),
                                    Text('${r['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  ]),
                                ),
                                Switch(
                                  value: on,
                                  activeThumbColor: Colors.white,
                                  activeTrackColor: AppColors.green600,
                                  onChanged: (v) => _toggle(r, v),
                                ),
                              ]),
                            );
                          },
                        ),
                ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.read<AlarmService>().ringNow('Test alarm'),
                child: const Text('🔔 Test alarm sound'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: () => _edit(null), child: const Text('＋ Add alarm')),
            ],
          ),
        ),
      ),
    );
  }
}
