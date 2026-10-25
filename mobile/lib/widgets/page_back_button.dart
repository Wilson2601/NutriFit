import 'package:flutter/material.dart';
import '../theme.dart';

/// Round back button for pages that can be opened from the bottom bar. Goes back when there is a
/// previous page, otherwise to Home.
class PageBackButton extends StatelessWidget {
  final String fallbackRoute;
  const PageBackButton({super.key, this.fallbackRoute = '/home'});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () {
          final nav = Navigator.of(context);
          if (nav.canPop()) {
            nav.pop();
          } else {
            nav.pushReplacementNamed(fallbackRoute);
          }
        },
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: AppColors.green100, borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.arrow_back, size: 18),
        ),
      ),
    );
  }
}
