import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decideRoute());
  }

  Future<void> _decideRoute() async {
    final auth = context.read<AuthService>();
    await auth.restoreSession();
    if (!mounted) return;
    if (auth.isSignedIn) {
      // Fire-and-forget: shouldn't block navigation if notification setup is slow/fails.
      context.read<NotificationService>().init(auth.token!);
      Navigator.of(context).pushReplacementNamed(auth.role == 'coach' ? '/coach' : '/home');
    } else {
      Navigator.of(context).pushReplacementNamed('/role');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.green500, AppColors.green600, AppColors.green700],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
                  ),
                  child: const Center(child: Text('🥗', style: TextStyle(fontSize: 56))),
                ),
                const SizedBox(height: 28),
                const Text('NutriFit',
                    style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 10),
                Text('SMART RECIPE SCALING',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: Colors.white.withValues(alpha: 0.85),
                    )),
                const SizedBox(height: 48),
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                ),
                const SizedBox(height: 20),
                Text('Loading your nutrition plan...',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.95))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
