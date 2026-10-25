import 'package:flutter/material.dart';
import '../widgets/coach_nav.dart';
import '../widgets/user_avatar.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';

/// Coach inbox: every client with the latest message and an unread badge.
class CoachInboxScreen extends StatefulWidget {
  const CoachInboxScreen({super.key});

  @override
  State<CoachInboxScreen> createState() => _CoachInboxScreenState();
}

class _CoachInboxScreenState extends State<CoachInboxScreen> {
  List<Map<String, dynamic>>? _threads;
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
      final data = await api.chatThreads(auth.token!);
      if (mounted) setState(() { _threads = (data['threads'] as List).cast<Map<String, dynamic>>(); _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      bottomNavigationBar: const CoachNav(currentIndex: 2),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text('Messages', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null
            ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: AppColors.red600)))])
            : _threads == null
                ? const Center(child: CircularProgressIndicator())
                : _threads!.isEmpty
                    ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No clients yet. Add a client to start chatting.', style: TextStyle(color: AppColors.muted))))])
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _threads!.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final t = _threads![i];
                          final unread = (t['unread'] as num).toInt();
                          return AppCard(
                            background: Colors.white,
                            onTap: () async {
                              await Navigator.of(context).pushNamed('/chat/${t['clientId']}');
                              _load();
                            },
                            child: Row(children: [
                              PersonAvatar(data: t, size: 40, color: AppColors.blue700, background: AppColors.blue100),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(t['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 2),
                                  Text(
                                    (t['lastMessage'] ?? 'No messages yet') as String,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: unread > 0 ? AppColors.ink : AppColors.muted, fontSize: 13, fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w400),
                                  ),
                                ]),
                              ),
                              if (unread > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: AppColors.blue600, borderRadius: BorderRadius.circular(99)),
                                  child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                                ),
                            ]),
                          );
                        },
                      ),
      ),
    );
  }
}
