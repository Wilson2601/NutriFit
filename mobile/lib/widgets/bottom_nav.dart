import 'package:flutter/material.dart';
import '../theme.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  const BottomNav({super.key, required this.currentIndex});

  static const _tabs = [
    {'icon': '🏠', 'label': 'Home', 'route': '/home'},
    {'icon': '📖', 'label': 'Recipes', 'route': '/recipes'},
    {'icon': '⚖️', 'label': 'Scale', 'route': '/scale'},
    {'icon': '🛒', 'label': 'Grocery', 'route': '/grocery'},
    {'icon': '👤', 'label': 'Profile', 'route': '/profile'},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEF1EC))),
      ),
      padding: const EdgeInsets.only(top: 10, bottom: 18),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final tab = _tabs[i];
          final active = i == currentIndex;
          return Expanded(
            child: InkWell(
              onTap: active
                  ? null
                  : () => Navigator.of(context).pushReplacementNamed(tab['route']!),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tab['icon']!, style: const TextStyle(fontSize: 20)),
                  const SizedBox(height: 3),
                  Text(
                    tab['label']!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: active ? AppColors.green600 : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
