import 'package:flutter/material.dart';
import '../widgets/user_avatar.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class CoachInfoScreen extends StatefulWidget {
  const CoachInfoScreen({super.key});

  @override
  State<CoachInfoScreen> createState() => _CoachInfoScreenState();
}

class _CoachInfoScreenState extends State<CoachInfoScreen> {
  Map<String, dynamic>? _coach;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    try {
      final res = await api.myCoach(auth.token!);
      if (mounted) setState(() { _coach = res['coach'] as Map<String, dynamic>?; _loaded = true; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loaded = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(backgroundColor: Colors.white, foregroundColor: AppColors.ink, elevation: 0,
          title: const Text('Coach Info', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.red600)))
              : _coach == null
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'You do not have a coach yet. Ask your coach to add you using the email you registered with.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        AppCard(
                          background: AppColors.blue50,
                          child: Column(children: [
                            PersonAvatar(data: _coach, size: 72, fontSize: 24, color: AppColors.blue700, background: AppColors.blue100),
                            const SizedBox(height: 12),
                            Text((_coach!['name'] ?? '') as String, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text((_coach!['email'] ?? '') as String, style: const TextStyle(color: AppColors.muted)),
                          ]),
                        ),
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pushNamed('/chat'),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Message my coach'),
                        ),
                      ],
                    ),
    );
  }
}
