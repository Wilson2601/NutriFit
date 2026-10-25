import 'package:flutter/material.dart';
import '../theme.dart';

class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              const Center(child: Text('👋', style: TextStyle(fontSize: 52))),
              const SizedBox(height: 12),
              const Text('Welcome to NutriFit',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 10),
              const Text('Who are you signing in as?',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: AppColors.muted)),
              const SizedBox(height: 36),
              _RoleCard(
                icon: '🏋️',
                iconBg: AppColors.green600,
                title: "I'm a User",
                subtitle: "Track nutrition & follow your coach's targets",
                background: AppColors.green50,
                borderColor: AppColors.green600,
                accentColor: AppColors.green600,
                onTap: () => Navigator.of(context).pushNamed('/login'),
              ),
              const SizedBox(height: 18),
              _RoleCard(
                icon: '🧑‍🏫',
                iconBg: AppColors.blue500,
                title: "I'm a Coach",
                subtitle: 'Manage clients & set macro targets',
                background: AppColors.blue50,
                borderColor: AppColors.blue500,
                accentColor: AppColors.blue600,
                onTap: () => Navigator.of(context).pushNamed('/coach-login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final Color background;
  final Color borderColor;
  final Color accentColor;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.background,
    required this.borderColor,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(16)),
                child: Center(child: Text(icon, style: const TextStyle(fontSize: 26))),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 13.5, color: AppColors.inkSoft)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: accentColor),
            ],
          ),
        ),
      ),
    );
  }
}
