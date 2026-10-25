import 'package:flutter/material.dart';
import '../services/in_app_notifier.dart';
import '../widgets/coach_nav.dart';
import '../widgets/user_avatar.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme.dart';

const _statusStyle = {
  'low': {'bg': AppColors.yellow100, 'text': Color(0xFF8A6D16)},
  'off_track': {'bg': AppColors.red100, 'text': AppColors.red600},
  'on_track': {'bg': AppColors.green100, 'text': AppColors.green700},
  'no_data': {'bg': Color(0xFFEEF0F3), 'text': Color(0xFF6B7280)},
};

class CoachDashboardScreen extends StatefulWidget {
  const CoachDashboardScreen({super.key});
  @override
  State<CoachDashboardScreen> createState() => _CoachDashboardScreenState();
}

class _CoachDashboardScreenState extends State<CoachDashboardScreen> {
  Map<String, dynamic>? _data;
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
      final data = await api.coachDashboard(auth.token!);
      if (mounted) setState(() { _data = data; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      backgroundColor: AppColors.paper,
      bottomNavigationBar: const CoachNav(currentIndex: 0),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.red600)),
              if (_data == null && _error == null)
                const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator())),
              if (_data != null) ..._buildContent(context, _data!, auth),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context, Map<String, dynamic> data, AuthService auth) {
    final coach = data['coach'];
    final stats = data['stats'];
    final attention = data['clients_needing_attention'] as List;

    return [
      AppCard(
        background: AppColors.blue600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Coach Dashboard', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Builder(builder: (ctx) {
                    final unread = ctx.watch<InAppNotifier>().unread;
                    return IconButton(
                      tooltip: 'Notifications',
                      onPressed: () => Navigator.of(ctx).pushNamed('/notifications'),
                      icon: Badge(
                        isLabelVisible: unread > 0,
                        label: Text('$unread'),
                        child: const Icon(Icons.notifications_none, color: Colors.white),
                      ),
                    );
                  }),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => Navigator.of(context).pushNamed('/coach/profile'),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 150),
                    padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(999)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      UserAvatar(user: auth.user, size: 32, fontSize: 12, borderColor: Colors.white, textColor: Colors.white),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          (auth.user?['name'] as String?) ?? 'Profile',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white),
                        ),
                      ),
                    ]),
                  ),
                ),
                ]),
              ],
            ),
            Text(coach['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: _miniStat('${stats['clients']}', 'Clients')),
              Expanded(child: _miniStat('${stats['on_track']}', 'On Track', const Color(0xFFC7F5D6))),
              Expanded(child: _miniStat('${stats['review']}', 'Review', const Color(0xFFFFE58A))),
            ]),
          ],
        ),
      ),
      const SizedBox(height: 26),
      const Text('Clients Needing Attention', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 14),
      ...attention.map((c) {
        final style = (_statusStyle[c['status']] ?? _statusStyle['no_data']!);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            background: style['bg'] as Color,
            onTap: () => Navigator.of(context).pushNamed('/coach/clients/${c['id']}'),
            child: Row(
              children: [
                PersonAvatar(data: c, size: 46, color: style['text'] as Color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c['name'], style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${(c['goal'] as String).replaceAll('_', ' ')} · ${c['weightKg']} kg', style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                      Text('Protein: ${c['protein']}/${c['proteinTarget']}g', style: TextStyle(color: style['text'] as Color, fontWeight: FontWeight.w700, fontSize: 12)),
                    ],
                  ),
                ),
                StatusPill(label: '${c['statusIcon']} ${c['statusLabel']}', background: Colors.white, textColor: style['text'] as Color),
              ],
            ),
          ),
        );
      }),
      const SizedBox(height: 20),
      const Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 14),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.8,
        children: [
          _quickAction('👤➕', 'Add Client', AppColors.blue100, () => Navigator.of(context).pushNamed('/coach/clients')),
          _quickAction('📊', 'View Reports', AppColors.green100, () => Navigator.of(context).pushNamed('/coach/clients')),
          _quickAction('🎯', 'Set Targets', AppColors.orange100, () => Navigator.of(context).pushNamed('/coach/clients')),
          _quickAction('💬', 'Messages', AppColors.purple100, () => Navigator.of(context).pushNamed('/coach/messages')),
        ],
      ),
    ];
  }

  Widget _miniStat(String value, String label, [Color color = Colors.white]) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _quickAction(String icon, String label, Color bg, VoidCallback onTap) {
    return AppCard(
      background: bg,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
