import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/alarm_service.dart';
import '../theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/user_avatar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _suggestions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    // Defends against Flutter web's deep-link behavior: if the browser reloaded
    // directly into /home (skipping the splash screen's session restore, e.g.
    // because that was the last URL from a previous run), recover here instead
    // of crashing on a null token.
    if (!auth.isSignedIn) {
      await auth.restoreSession();
    }
    if (!auth.isSignedIn) {
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/role', (route) => false);
      return;
    }

    final api = context.read<ApiService>();
    try {
      context.read<AlarmService>().start(auth.token!, () => auth.isSignedIn);
    } catch (_) {}
    try {
      final data = await api.progressToday(auth.token!);
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    try {
      final suggestions = await api.suggestedRecipes(auth.token!);
      if (mounted) setState(() => _suggestions = suggestions);
    } on ApiException {
      // Suggestions are a nice-to-have — don't block the rest of the dashboard if this fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    final firstName = (user?['name'] as String? ?? 'there').split(' ').first;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_greeting(), style: const TextStyle(color: AppColors.muted)),
                        Text('$firstName 👋', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => Navigator.of(context).pushNamed('/profile'),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 160),
                      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
                      decoration: BoxDecoration(color: AppColors.green100, borderRadius: BorderRadius.circular(999)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        UserAvatar(user: user, size: 32, fontSize: 12),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            (user?['name'] as String?) ?? 'Profile',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.green700),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.red100, borderRadius: BorderRadius.circular(12)),
                  child: Text(_error!, style: const TextStyle(color: AppColors.red600)),
                ),
              if (_data == null && _error == null)
                const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator())),
              if (_data != null) _progressCard(_data!),
              const SizedBox(height: 26),
              if (_suggestions != null && (_suggestions!['suggestions'] as List).isNotEmpty) ...[
                const Text('Suggested for You', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Best macro fit for what you still need today', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 12),
                _suggestionsList(context, _suggestions!),
                const SizedBox(height: 26),
              ],
              const Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _quickActions(context),
              const SizedBox(height: 26),
              const Text("Today's Meals", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (_data != null) ..._mealsList(_data!),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 0),
    );
  }

  /// Greeting that follows the real clock.
  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Good night,';
    if (h < 12) return 'Good morning,';
    if (h < 18) return 'Good afternoon,';
    return 'Good evening,';
  }

  String _rem(Map<String, dynamic> data, String key) {
    final remaining = data['remaining'] as Map<String, dynamic>?;
    final v = remaining == null ? null : remaining[key];
    return v is num ? v.toStringAsFixed(0) : '-';
  }

  Widget _progressCard(Map<String, dynamic> data) {
    final target = data['target'] as Map<String, dynamic>;
    final totals = data['totals'] as Map<String, dynamic>;
    final pct = (data['percent_complete'] as num).toDouble().clamp(0, 100);

    Widget macro(String key, String label, Color color) {
      final val = (totals[key] as num).toDouble();
      final tgt = (target['${key}G'] as num).toDouble();
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${val.toStringAsFixed(0)}g', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color)),
            Text('$label / ${tgt.toStringAsFixed(0)}g', style: const TextStyle(fontSize: 11, color: Colors.white70)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: (val / (tgt == 0 ? 1 : tgt)).clamp(0, 1),
                minHeight: 6,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ),
      );
    }

    return AppCard(
      background: AppColors.green600,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Today's Progress", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              StatusPill(label: '${pct.toStringAsFixed(0)}%', background: Colors.white24, textColor: Colors.white),
            ],
          ),
          Text('${totals['calories']} / ${target['calories']} kcal', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: pct / 100, minHeight: 8, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(Colors.white)),
          ),
          const SizedBox(height: 6),
          Text(
            'Remaining: ${_rem(data, 'calories')} kcal · P ${_rem(data, 'protein')} g · C ${_rem(data, 'carbs')} g · F ${_rem(data, 'fat')} g',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 18),
          Row(children: [
            macro('protein', 'Protein', Colors.white),
            const SizedBox(width: 14),
            macro('carbs', 'Carbs', const Color(0xFFFFE58A)),
            const SizedBox(width: 14),
            macro('fat', 'Fat', const Color(0xFFA9D4FF)),
          ]),
        ],
      ),
    );
  }

  Widget _suggestionsList(BuildContext context, Map<String, dynamic> data) {
    final suggestions = data['suggestions'] as List;
    return SizedBox(
      height: 172,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final s = suggestions[i];
          final macros = s['macros'] as Map<String, dynamic>;
          return SizedBox(
            width: 160,
            child: AppCard(
              background: AppColors.green50,
              onTap: () => Navigator.of(context).pushNamed('/scale/${s['id']}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(s['emoji'] ?? '🍽️', style: const TextStyle(fontSize: 22)),
                      StatusPill(label: '${s['matchPct']}%', background: AppColors.green600, textColor: Colors.white),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(s['name'], maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const Spacer(),
                  Text('${macros['calories']} kcal', style: const TextStyle(color: AppColors.green700, fontWeight: FontWeight.w700, fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _quickActions(BuildContext context) {
    final actions = [
      {'icon': '🔬', 'label': 'Optimize Recipe', 'bg': AppColors.green100, 'route': '/scale'},
      {'icon': '📊', 'label': 'Nutrition & Adherence', 'bg': AppColors.blue100, 'route': '/nutrition'},
      {'icon': '🔎', 'label': 'Find Foods', 'bg': AppColors.orange100, 'route': '/foods'},
      {'icon': '🛒', 'label': 'Grocery List', 'bg': AppColors.blue100, 'route': '/grocery'},
      {'icon': '⏰', 'label': 'Reminders', 'bg': AppColors.purple100, 'route': '/reminders'},
      {'icon': '📸', 'label': 'Daily Mission', 'bg': AppColors.orange100, 'route': '/mission'},
      {'icon': '💬', 'label': 'Chat with Coach', 'bg': AppColors.green50, 'route': '/chat'},
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: 1.7,
      children: actions.map((a) {
        return AppCard(
          background: a['bg'] as Color,
          onTap: () => Navigator.of(context).pushNamed(a['route'] as String).then((_) => _load()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a['icon'] as String, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 8),
              Text(a['label'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<Widget> _mealsList(Map<String, dynamic> data) {
    final meals = data['meals'] as List;
    final planned = (data['planned'] as List?) ?? const [];
    if (meals.isEmpty && planned.isEmpty) {
      return [
        const AppCard(
          background: AppColors.green50,
          child: Center(child: Text('Nothing planned yet. Open Optimize Recipe, pick a recipe and tap "Plan to eat".', style: TextStyle(color: AppColors.muted), textAlign: TextAlign.center)),
        ),
      ];
    }

    Widget tile({
      required Map m,
      required Color bg,
      required String pill,
      required Color pillBg,
      required Color pillText,
      required String hint,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppCard(
          background: bg,
          onTap: onTap,
          child: Row(
            children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Center(child: Text(m['recipeEmoji'] ?? '🍽️', style: const TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m['recipeName'] ?? 'Meal', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('P:${m['protein']}g · C:${m['carbs']}g · F:${m['fat']}g', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    Text('${m['calories']} kcal', style: const TextStyle(color: AppColors.green700, fontWeight: FontWeight.w800)),
                    Text(hint, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ],
                ),
              ),
              StatusPill(label: pill, background: pillBg, textColor: pillText),
            ],
          ),
        ),
      );
    }

    return [
      for (final m in planned)
        tile(
          m: m,
          bg: AppColors.blue50,
          pill: '📅 ${m['mealType'] ?? 'Planned'}',
          pillBg: AppColors.blue100,
          pillText: AppColors.blue700,
          hint: 'Planned · tap to view recipe and cook',
          onTap: () => Navigator.of(context).pushNamed('/planned/${m['id']}').then((_) => _load()),
        ),
      for (final m in meals)
        tile(
          m: m,
          bg: AppColors.green50,
          pill: '✓ ${m['mealType']}',
          pillBg: Colors.white,
          pillText: AppColors.green700,
          hint: 'Logged · tap to add your meal photo',
          onTap: () => Navigator.of(context).pushNamed('/mission').then((_) => _load()),
        ),
    ];
  }
}
