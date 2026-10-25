import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/coach_nav.dart';
import '../widgets/page_back_button.dart';
import '../widgets/user_avatar.dart';

/// Coach profile: photo (tap to change), name, email and sign out.
const _menu = [
  {'icon': '⚙️', 'label': 'Account Settings', 'bg': AppColors.green100, 'route': '/settings/account'},
  {'icon': '🔔', 'label': 'Notification Prefs', 'bg': AppColors.orange100, 'route': '/settings/notifications'},
  {'icon': '🔒', 'label': 'Privacy & Security', 'bg': AppColors.purple100, 'route': '/settings/privacy'},
];

class CoachProfileScreen extends StatefulWidget {
  const CoachProfileScreen({super.key});
  @override
  State<CoachProfileScreen> createState() => _CoachProfileScreenState();
}

class _CoachProfileScreenState extends State<CoachProfileScreen> {
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final token = context.read<AuthService>().token;
      if (token == null) return;
      final d = await context.read<ApiService>().coachDashboard(token);
      if (mounted) setState(() => _stats = d['stats'] as Map<String, dynamic>?);
    } catch (_) {/* stats are optional */}
  }

  Widget _statBox(Color bg, String value, String label, Color color) => AppCard(
        background: bg,
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    return Scaffold(
      backgroundColor: AppColors.paper,
      bottomNavigationBar: const CoachNav(currentIndex: 3),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 12), child: PageBackButton(fallbackRoute: '/coach')),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
              decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.blue600, AppColors.blue700])),
              child: Column(children: [
                const EditableAvatar(),
                const SizedBox(height: 6),
                const Text('Tap the picture to change it', style: TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(height: 10),
                Text(user?['name'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 4),
                Text(user?['email'] ?? '', style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 14),
                StatusPill(label: '🧑‍🏫 Coach', background: Colors.white.withValues(alpha: 0.22), textColor: Colors.white),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Row(children: [
                  Expanded(child: _statBox(AppColors.blue100, '${_stats?['clients'] ?? '—'}', 'Clients', AppColors.blue700)),
                  const SizedBox(width: 10),
                  Expanded(child: _statBox(AppColors.green100, '${_stats?['on_track'] ?? '—'}', 'On Track', AppColors.green700)),
                  const SizedBox(width: 10),
                  Expanded(child: _statBox(AppColors.orange100, '${_stats?['review'] ?? '—'}', 'Review', AppColors.orange600)),
                ]),
                const SizedBox(height: 20),
                ..._menu.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppCard(
                        background: Colors.white,
                        onTap: () => Navigator.of(context).pushNamed(m['route'] as String),
                        child: Row(children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(color: m['bg'] as Color, borderRadius: BorderRadius.circular(12)),
                            child: Center(child: Text(m['icon'] as String, style: const TextStyle(fontSize: 20))),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Text(m['label'] as String, style: const TextStyle(fontWeight: FontWeight.w700))),
                          const Icon(Icons.chevron_right, color: AppColors.muted),
                        ]),
                      ),
                    )),
                const SizedBox(height: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.red600, side: const BorderSide(color: AppColors.red100)),
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    await auth.logout();
                    nav.pushNamedAndRemoveUntil('/role', (r) => false);
                  },
                  child: const Text('Sign Out'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
