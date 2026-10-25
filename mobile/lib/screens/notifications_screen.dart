import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/in_app_notifier.dart';
import '../theme.dart';
import '../widgets/page_back_button.dart';

/// List of recent notifications for the signed-in user or coach.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<InAppNotifier>().refresh();
  }

  String _icon(dynamic type) {
    switch (type) {
      case 'chat': return '💬';
      case 'meal_logged': return '🍽️';
      case 'mission_passed': return '🏆';
      case 'targets_updated': return '🎯';
      default: return '🔔';
    }
  }

  String _ago(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<InAppNotifier>();
    final isCoach = context.read<AuthService>().role == 'coach';
    final items = notifier.items;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: notifier.refresh,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(children: [
                PageBackButton(fallbackRoute: isCoach ? '/coach' : '/home'),
                const SizedBox(width: 14),
                const Expanded(child: Text('Notifications', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
                if (notifier.unread > 0) TextButton(onPressed: notifier.markAllRead, child: const Text('Mark all read')),
              ]),
              const SizedBox(height: 16),
              if (items.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: Text('No notifications yet.', style: TextStyle(color: AppColors.muted)))),
              ...items.map((n) {
                final unread = n['read'] != true;
                final route = notifier.routeFor(n);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    background: unread ? AppColors.blue50 : Colors.white,
                    onTap: () {
                      notifier.markRead(n);
                      if (route != null) Navigator.of(context).pushNamed(route);
                    },
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_icon(n['type']), style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(((n['title'] ?? '') as String).replaceFirst(RegExp(r'^[^\w]+'), ''), style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                          if (((n['body'] ?? '') as String).isNotEmpty)
                            Text(n['body'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(_ago((n['createdAt'] ?? '') as String), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                        ]),
                      ),
                      if (unread) const Padding(padding: EdgeInsets.only(top: 6), child: CircleAvatar(radius: 5, backgroundColor: AppColors.blue600)),
                    ]),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
