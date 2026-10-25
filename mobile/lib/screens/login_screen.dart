import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController(text: 'wilson@example.com');
  final _passwordController = TextEditingController(text: 'password123');
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      await auth.login(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            role: 'user',
          );
      if (!mounted) return;
      context.read<NotificationService>().init(auth.token!);
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Sign in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.green500, AppColors.green600]),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
                  child: const Center(child: Text('🥗', style: TextStyle(fontSize: 28))),
                ),
                const SizedBox(height: 16),
                const Text('Welcome back! 👋', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 6),
                Text('Sign in to your account', style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Sign In', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.red100, borderRadius: BorderRadius.circular(12)),
                          child: Text(_error!, style: const TextStyle(color: AppColors.red600, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email Address'),
                        validator: (v) => (v == null || v.isEmpty) ? 'Enter your email' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Password'),
                        validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Sign In  →'),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pushNamed('/register'),
                          child: const Text.rich(TextSpan(children: [
                            TextSpan(text: 'New here? ', style: TextStyle(color: AppColors.muted)),
                            TextSpan(text: 'Create account', style: TextStyle(color: AppColors.green700, fontWeight: FontWeight.w800)),
                          ])),
                        ),
                      ),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pushReplacementNamed('/coach-login'),
                          child: const Text.rich(TextSpan(children: [
                            TextSpan(text: 'Are you a coach? ', style: TextStyle(color: AppColors.muted)),
                            TextSpan(text: 'Coach login', style: TextStyle(color: AppColors.blue600, fontWeight: FontWeight.w800)),
                          ])),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
