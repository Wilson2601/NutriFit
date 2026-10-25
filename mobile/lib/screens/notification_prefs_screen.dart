import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class NotificationPrefsScreen extends StatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  State<NotificationPrefsScreen> createState() => _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState extends State<NotificationPrefsScreen> {
  Map<String, dynamic>? _prefs;
  String? _error;

  static const _rows = [
    ['targets', 'New targets', 'When your coach updates your macro plan'],
    ['chat', 'Chat messages', 'When your coach sends you a message'],
    ['mission', 'Mission results', 'When your daily mission result is ready'],
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    try {
      final res = await api.getPreferences(auth.token!);
      if (mounted) setState(() => _prefs = res['preferences'] as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _set(String key, bool value) async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final old = _prefs!;
    setState(() => _prefs = {...old, key: value}); // optimistic update
    try {
      final res = await api.updatePreferences(auth.token!, {key: value});
      if (mounted) setState(() => _prefs = res['preferences'] as Map<String, dynamic>);
    } catch (e) {
      if (mounted) {
        setState(() => _prefs = old);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _prefs;
    final master = prefs?['push'] != false;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(backgroundColor: Colors.white, foregroundColor: AppColors.ink, elevation: 0,
          title: const Text('Notification Prefs', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.red600)))
          : prefs == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    AppCard(
                      background: Colors.white,
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Push notifications', style: TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: const Text('Master switch for everything below'),
                        value: master,
                        onChanged: (v) => _set('push', v),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ...(context.read<AuthService>().role == 'coach'
                            ? const [
                                ['chat', 'Chat messages', 'When a client sends you a message'],
                                ['mission', 'Client activity', 'When a client logs a meal or passes the daily mission'],
                              ]
                            : _rows)
                        .map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AppCard(
                            background: Colors.white,
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(r[1], style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(r[2]),
                              value: master && prefs[r[0]] != false,
                              onChanged: master ? (v) => _set(r[0], v) : null,
                            ),
                          ),
                        )),
                    const SizedBox(height: 6),
                    const Text('Meal reminders are managed on the Reminders tab.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
    );
  }
}
