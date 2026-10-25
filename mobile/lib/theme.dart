import 'package:flutter/material.dart';

/// Central design tokens. Per the thesis's UI design section: a nature-inspired
/// green scheme for the user-facing tracking environment, and an authoritative
/// blue scheme for the coach management portal.
class AppColors {
  AppColors._();

  static const green900 = Color(0xFF12321D);
  static const green700 = Color(0xFF227A45);
  static const green600 = Color(0xFF2F9E5C);
  static const green500 = Color(0xFF43B876);
  static const green100 = Color(0xFFE3F5E9);
  static const green50 = Color(0xFFEEF8F0);

  static const blue700 = Color(0xFF2F5FD0);
  static const blue600 = Color(0xFF3F7CE8);
  static const blue500 = Color(0xFF4A8BFA);
  static const blue100 = Color(0xFFE8EFFE);
  static const blue50 = Color(0xFFF1F5FF);

  static const orange100 = Color(0xFFFDEBDD);
  static const orange600 = Color(0xFFE08A2C);
  static const yellow100 = Color(0xFFFBF3D2);
  static const purple100 = Color(0xFFEDE8FB);
  static const purple600 = Color(0xFF5B4BB0);
  static const red100 = Color(0xFFFBDEDE);
  static const red600 = Color(0xFFD64545);

  static const ink = Color(0xFF17241A);
  static const inkSoft = Color(0xFF4A5A4D);
  static const muted = Color(0xFF8A9A8D);
  static const paper = Color(0xFFF6FAF5);
}

class AppTheme {
  AppTheme._();

  static ThemeData get userTheme => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.paper,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.green600,
          primary: AppColors.green600,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.green600,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.green50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
      );

  static ThemeData get coachTheme => userTheme.copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.blue600, primary: AppColors.blue600),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.blue600,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
      );
}

/// A rounded "card" container matching the mockups' soft, colored panels.
class AppCard extends StatelessWidget {
  final Widget child;
  final Color background;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.background = Colors.white,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(22), onTap: onTap, child: content),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String label;
  final Color background;
  final Color textColor;

  const StatusPill({super.key, required this.label, required this.background, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}
