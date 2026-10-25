import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/page_back_button.dart';
import '../widgets/user_avatar.dart';

const _goalLabels = {
  'muscle_gain': '💪 Bulking Phase', 'weight_loss': '🔥 Cutting Phase',
  'maintain': '⚡ Maintaining', 'performance': '🏆 Performance Phase',
};

const _menu = [
  {'icon': '⚙️', 'label': 'Account Settings', 'bg': AppColors.green100, 'route': '/settings/account'},
  {'icon': '🧑‍🏫', 'label': 'Coach Info', 'bg': AppColors.blue100, 'route': '/settings/coach'},
  {'icon': '🔔', 'label': 'Notification Prefs', 'bg': AppColors.orange100, 'route': '/settings/notifications'},
  {'icon': '🔒', 'label': 'Privacy & Security', 'bg': AppColors.purple100, 'route': '/settings/privacy'},
  {'icon': '❓', 'label': 'Help & Support', 'bg': AppColors.blue50, 'route': '/settings/help'},
];

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 12), child: PageBackButton()),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
              decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.green500, AppColors.green600])),
              child: Column(
                children: [
                  const EditableAvatar(),
                  const SizedBox(height: 6),
                  const Text('Tap the picture to change it', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 10),
                  Text(user?['name'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(user?['email'] ?? '', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 14),
                  StatusPill(label: _goalLabels[user?['goal']] ?? '🎯 ${user?['goal']}', background: Colors.white.withValues(alpha: 0.22), textColor: Colors.white),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(children: [
                    Expanded(child: _statBox(AppColors.green100, '${user?['weightKg'] ?? '—'} kg', 'Weight', AppColors.green700)),
                    const SizedBox(width: 10),
                    Expanded(child: _statBox(AppColors.orange100, '${user?['goalWeightKg'] ?? '—'} kg', 'Goal', AppColors.orange600)),
                    const SizedBox(width: 10),
                    Expanded(child: _statBox(AppColors.purple100, '${user?['streakDays'] ?? 0}d 🔥', 'Streak', AppColors.purple600)),
                  ]),
                  const SizedBox(height: 20),
                  ..._menu.map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppCard(
                          background: Colors.white,
                          onTap: () => Navigator.of(context).pushNamed(m['route'] as String),
                          child: Row(
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(color: m['bg'] as Color, borderRadius: BorderRadius.circular(12)),
                                child: Center(child: Text(m['icon'] as String, style: const TextStyle(fontSize: 20))),
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: Text(m['label'] as String, style: const TextStyle(fontWeight: FontWeight.w700))),
                              const Icon(Icons.chevron_right, color: AppColors.muted),
                            ],
                          ),
                        ),
                      )),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.red600, side: const BorderSide(color: AppColors.red100)),
                    onPressed: () async {
                      await auth.logout();
                      if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil('/role', (r) => false);
                    },
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 4),
    );
  }

  Widget _statBox(Color bg, String value, String label, Color color) {
    return AppCard(
      background: bg,
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
        ],
      ),
    );
  }
}
