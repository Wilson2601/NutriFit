import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/in_app_notifier.dart';
import '../theme.dart';

/// Bottom bar for coach pages: Dashboard, Clients, Messages and Profile.
class CoachNav extends StatelessWidget {
  final int currentIndex;
  const CoachNav({super.key, required this.currentIndex});

  static const _tabs = [
    {'icon': '🏠', 'label': 'Dashboard', 'route': '/coach'},
    {'icon': '👥', 'label': 'Clients', 'route': '/coach/clients'},
    {'icon': '💬', 'label': 'Messages', 'route': '/coach/messages'},
    {'icon': '👤', 'label': 'Profile', 'route': '/coach/profile'},
  ];

  @override
  Widget build(BuildContext context) {
    final chatUnread = context.watch<InAppNotifier>().chatUnread;
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEEF1EC)))),
      padding: const EdgeInsets.only(top: 10, bottom: 18),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final tab = _tabs[i];
          final active = i == currentIndex;
          return Expanded(
            child: InkWell(
              onTap: () async {
                if (!active) {
                  Navigator.of(context).pushReplacementNamed(tab['route']!);
                }
              },
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Badge(
                  isLabelVisible: i == 2 && chatUnread > 0,
                  label: Text('$chatUnread'),
                  child: Text(tab['icon']!, style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(height: 3),
                Text(tab['label']!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? AppColors.blue600 : AppColors.muted)),
              ]),
            ),
          );
        }),
      ),
    );
  }
}
