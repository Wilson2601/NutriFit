import 'package:flutter/material.dart';
import '../widgets/coach_nav.dart';
import '../widgets/user_avatar.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme.dart';

class ClientProgressScreen extends StatefulWidget {
  final String clientId;
  const ClientProgressScreen({super.key, required this.clientId});
  @override
  State<ClientProgressScreen> createState() => _ClientProgressScreenState();
}

class _ClientProgressScreenState extends State<ClientProgressScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  int _days = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    try {
      final data = await api.clientProgress(auth.token!, widget.clientId, days: _days);
      if (mounted) setState(() { _data = data; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      bottomNavigationBar: const CoachNav(currentIndex: 1),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: AppColors.blue100, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.arrow_back, size: 18),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Client Progress', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    if (_data != null) Text('${_data!['client']['name']} · Last $_days days', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 18),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.red600)),
            if (_data == null && _error == null) const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator())),
            if (_data != null) ..._content(_data!),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(Map<String, dynamic> data) {
    final client = data['client'];
    final macros = data['macroAdherence'] as Map<String, dynamic>;

    Widget macroRow(String key, String label, Color color) {
      final m = macros[key];
      final pct = ((m['pct'] as num).toDouble()).clamp(0, 100);
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: AppCard(
          background: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${m['value']}${key == 'calories' ? ' kcal' : 'g'}', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                  TextSpan(text: ' / ${m['target']}${key == 'calories' ? ' kcal' : 'g'}', style: const TextStyle(color: AppColors.muted)),
                ])),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: pct / 100, minHeight: 8, backgroundColor: const Color(0xFFE6EDE4), valueColor: AlwaysStoppedAnimation(color)),
              ),
              const SizedBox(height: 8),
              Text('${m['pct']}% of target', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    final mission = data['todayMission'] as Map<String, dynamic>?;
    final missionCard = mission == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: AppCard(
              background: mission['passed'] == true ? AppColors.green100 : AppColors.orange100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mission['passed'] == true ? "🏆 Today's mission: passed" : "📸 Today's mission: not passed yet",
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ...(mission['criteria'] as List).map((c) => Text(
                        '${c['met'] == true ? '✅' : '⬜'} ${c['label']} — ${c['detail']}',
                        style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                      )),
                ],
              ),
            ),
          );

    return [
      missionCard,
      AppCard(
        background: AppColors.green50,
        child: Column(
          children: [
            Row(children: [
              PersonAvatar(data: client, size: 54, color: AppColors.green600),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(client['name'], style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('${(client['goal'] as String).replaceAll('_', ' ')} · ${client['weightKg']} kg → ${client['goalWeightKg']} kg goal', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
              StatusPill(label: '${_statusIcon(data['statusKey'])} ${data['status']}', background: Colors.white, textColor: AppColors.green700),
            ]),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.2,
              children: [
                _miniCard('${data['daysAdhered']} / ${data['daysTracked']}', 'Days adhered'),
                _miniCard('${data['avgCompliance']}%', 'Avg compliance', AppColors.blue600),
                _miniCard('${data['avgProtein']}g', 'Avg protein', AppColors.orange600),
                _miniCard('${data['streakDays']} days 🔥', 'Streak', AppColors.purple600),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 26),
      ..._adherenceSection(data),
      const SizedBox(height: 26),
      Text('AVERAGE INTAKE ($_days DAYS, LOGGED DAYS ONLY)', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)),
      const SizedBox(height: 14),
      macroRow('protein', 'Protein', AppColors.green600),
      macroRow('carbs', 'Carbohydrates', AppColors.orange600),
      macroRow('fat', 'Fat', AppColors.blue600),
      macroRow('calories', 'Calories', AppColors.purple600),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: () => Navigator.of(context).pushNamed('/chat/${widget.clientId}'),
        child: const Text('💬 Message Client'),
      ),
      const SizedBox(height: 10),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue600),
        onPressed: () => Navigator.of(context).pushNamed('/coach/clients/${widget.clientId}/targets'),
        child: const Text('🎯 Adjust Targets'),
      ),
    ];
  }

  String _statusIcon(dynamic key) {
    switch (key) {
      case 'on_track': return '✅';
      case 'low': return '⚠️';
      case 'off_track': return '❌';
      default: return '➖';
    }
  }

  static String _f(dynamic v) => v is num ? v.toStringAsFixed(0) : '-';

  List<Widget> _adherenceSection(Map<String, dynamic> data) {
    final a = data['adherence'] as Map<String, dynamic>;
    final today = data['today'] as Map<String, dynamic>;
    final comps = today['components'] as Map<String, dynamic>;
    final history = data['history'] as List;

    Widget period(int d) => GestureDetector(
          onTap: () { setState(() => _days = d); _load(); },
          child: Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: _days == d ? AppColors.blue600 : const Color(0xFFEEF2EC), borderRadius: BorderRadius.circular(999)),
            child: Text('$d days', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _days == d ? Colors.white : AppColors.inkSoft)),
          ),
        );
    Widget stat(String value, String label) => Expanded(
          child: Column(children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.blue600)),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ]),
        );
    Widget compRow(String label, String key) {
      final c = comps[key] as Map<String, dynamic>;
      final state = c['state'] as String;
      final color = state == 'within' ? AppColors.green700 : (state == 'below' ? AppColors.orange600 : (state == 'above' ? AppColors.red600 : AppColors.muted));
      final arrow = state == 'below' ? '▼ below' : (state == 'above' ? '▲ above' : (state == 'within' ? '✓ on target' : '-'));
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(flex: 3, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(flex: 4, child: Text('${_f(c['consumed'])} / ${_f(c['target'])}', textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text(c['percent'] == null ? '-' : '${_f(c['percent'])}%', textAlign: TextAlign.right, style: TextStyle(color: color, fontWeight: FontWeight.w700))),
          Expanded(flex: 3, child: Text(arrow, textAlign: TextAlign.right, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700))),
        ]),
      );
    }

    return [
      Row(children: [
        const Expanded(child: Text('NUTRITION ADHERENCE', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1))),
        period(7),
        period(30),
      ]),
      const SizedBox(height: 14),
      AppCard(
        background: AppColors.blue50,
        child: Column(children: [
          Row(children: [
            stat('${a['adherenceRate']}%', 'Adherence rate\n(${a['adherentDays']} of ${a['observationDays']} days)'),
            stat('${a['loggingCompleteness']}%', 'Logging completeness\n(${a['loggedDays']} days logged)'),
            stat('${a['noRecordDays']}', 'Days with\nno records'),
          ]),
          const SizedBox(height: 8),
          const Text('Days without records are shown separately; they are not treated as proof the plan was ignored. A period ends yesterday.', style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.35)),
        ]),
      ),
      const SizedBox(height: 14),
      AppCard(
        background: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Today (eaten / target)', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          compRow('Calories', 'calories'),
          compRow('Protein', 'protein'),
          compRow('Carbs', 'carbs'),
          compRow('Fat', 'fat'),
        ]),
      ),
      const SizedBox(height: 14),
      const Text('History', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      for (final h in history.reversed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Text(h['status'] == 'adherent' ? '✅' : (h['status'] == 'no_records' ? '➖' : '❌')),
            const SizedBox(width: 10),
            Expanded(child: Text('${h['date']}  ·  target ${_f(h['target']['calories'])} kcal', style: const TextStyle(fontSize: 12.5))),
            Text(
              h['hasRecords'] == true ? '${_f(h['components']['calories']['percent'])}% kcal · ${_f(h['components']['protein']['percent'])}% P' : 'no records',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ]),
        ),
    ];
  }

  Widget _miniCard(String value, String label, [Color color = AppColors.green600]) {
    return AppCard(
      background: Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
        ],
      ),
    );
  }
}
