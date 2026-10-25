import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

/// Wraps any screen that requires a signed-in user. Handles the case where
/// Flutter web reloads directly into a deep-linked route (e.g. the browser's
/// last URL was /home or /coach/clients/xyz) — which skips SplashScreen's
/// session restore entirely. This widget makes sure a session is restored
/// (or the user is redirected to sign in) before its child ever builds,
/// so no screen has to defensively null-check auth.token itself.
class AuthGate extends StatefulWidget {
  final Widget child;
  final String? requiredRole; // null = any signed-in role is fine

  const AuthGate({super.key, required this.child, this.requiredRole});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _ensureSession();
  }

  Future<void> _ensureSession() async {
    final auth = context.read<AuthService>();
    if (!auth.isSignedIn) {
      await auth.restoreSession();
    }
    if (mounted) setState(() => _checked = true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (!_checked || auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final roleMismatch = widget.requiredRole != null && auth.role != widget.requiredRole;
    if (!auth.isSignedIn || roleMismatch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/role', (route) => false);
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    return widget.child;
  }
}
