import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  bool _busy = false;

  Future<void> _sendReset() async {
    final email = context.read<AuthService>().user?['email'] as String?;
    final messenger = ScaffoldMessenger.of(context);
    if (email == null) return;
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      messenger.showSnackBar(SnackBar(content: Text('Password reset email sent to $email')));
    } on FirebaseAuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message ?? 'Could not send the email')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text('This permanently deletes your profile, meal logs, photos and messages. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete account', style: TextStyle(color: AppColors.red600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await api.deleteAccount(auth.token!);
      await auth.logout();
      navigator.pushNamedAndRemoveUntil('/role', (r) => false);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(backgroundColor: Colors.white, foregroundColor: AppColors.ink, elevation: 0,
          title: const Text('Privacy & Security', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppCard(
            background: Colors.white,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Password', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('We will email you a secure link to choose a new password.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _busy ? null : _sendReset, child: const Text('Email me a reset link')),
            ]),
          ),
          const SizedBox(height: 14),
          AppCard(
            background: Colors.white,
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Who can see your data', style: TextStyle(fontWeight: FontWeight.w800)),
              SizedBox(height: 6),
              Text(
                'Your meal logs, progress, meal photos and chat are visible only to you and the coach assigned to you. Photos are taken live with the camera and stored as small thumbnails.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.red600, side: const BorderSide(color: AppColors.red100)),
            onPressed: _busy ? null : _deleteAccount,
            child: const Text('Delete my account'),
          ),
        ],
      ),
    );
  }
}
