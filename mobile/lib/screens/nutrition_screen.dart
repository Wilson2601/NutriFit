import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/page_back_button.dart';

/// Route: /nutrition - today's target / consumed / remaining, meals eaten, planned meals,
/// and adherence over 7 or 30 days (same rules the coach sees).
class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});
  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _report;
  List<dynamic> _planned = [];
  int _days = 7;
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
      final summary = await api.nutritionSummary(auth.token!);
      final report = await api.adherence(auth.token!, _days);
      final planned = await api.plannedMeals(auth.token!);
      if (mounted) setState(() { _summary = summary; _report = report; _planned = planned['planned'] as List; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _deleteMeal(String id) async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    try {
      await api.deleteMeal(auth.token!, id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _deletePlanned(String id) async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    try {
      await api.deletePlannedMeal(auth.token!, id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  static String _f(dynamic v) => v is num ? v.toStringAsFixed(0) : '-';

  Color _stateColor(String state) {
    switch (state) {
      case 'within': return AppColors.green700;
      case 'below': return AppColors.orange600;
      case 'above': return AppColors.red600;
      default: return AppColors.muted;
    }
  }

  String _stateLabel(String state) {
    switch (state) {
      case 'within': return 'On target';
      case 'below': return 'Below';
      case 'above': return 'Above';
      default: return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              const PageBackButton(),
              const SizedBox(height: 12),
              const Text('📊 Nutrition & Adherence', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Planned meals are not counted. A meal counts only after you cook it and tap Log meal.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
              const SizedBox(height: 16),
              if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.red600)),
              if (_summary == null && _error == null) const Padding(padding: EdgeInsets.symmetric(vertical: 50), child: Center(child: CircularProgressIndicator())),
              if (_summary != null) ..._today(_summary!),
              if (_planned.isNotEmpty) ..._plannedSection(),
              if (_report != null) ..._adherence(_report!),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 0),
    );
  }

  List<Widget> _today(Map<String, dynamic> s) {
    final comps = s['components'] as Map<String, dynamic>;
    final meals = (s['meals'] as List?) ?? const [];

    Widget head(String a, String b, String c, String d, String e) {
      const st = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.muted);
      return Row(children: [
        Expanded(flex: 3, child: Text(a, style: st)),
        Expanded(flex: 2, child: Text(b, style: st, textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text(c, style: st, textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text(d, style: st, textAlign: TextAlign.right)),
        Expanded(flex: 3, child: Text(e, style: st, textAlign: TextAlign.right)),
      ]);
    }

    Widget line(String label, String key, String unit) {
      final c = comps[key] as Map<String, dynamic>;
      final over = (c['over'] as num) > 0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(flex: 3, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(flex: 2, child: Text(_f(c['target']), textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text(_f(c['consumed']), textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text(over ? '0 (+${_f(c['over'])})' : _f(c['remaining']), textAlign: TextAlign.right, style: TextStyle(color: over ? AppColors.red600 : AppColors.ink))),
          Expanded(
            flex: 3,
            child: Text(
              c['percent'] == null ? '-' : '${_f(c['percent'])}% ${_stateLabel(c['state'] as String)}',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: _stateColor(c['state'] as String)),
            ),
          ),
        ]),
      );
    }

    return [
      AppCard(
        background: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Today', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          head('', 'Target', 'Eaten', 'Left', 'Achieved'),
          line('Calories', 'calories', 'kcal'),
          line('Protein (g)', 'protein', 'g'),
          line('Carbs (g)', 'carbs', 'g'),
          line('Fat (g)', 'fat', 'g'),
          const SizedBox(height: 6),
          Text(
            s['hasRecords'] == true
                ? (s['adherent'] == true ? '✅ Today is on target so far.' : 'Today is not on target yet.')
                : 'No meals confirmed yet today (this is not counted against you).',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      const Text('Logged today (eaten)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 8),
      if (meals.isEmpty) const Text('Nothing logged yet.', style: TextStyle(color: AppColors.muted)),
      for (final m in meals)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFEEF2EC))),
            child: Row(children: [
              Text(m['recipeEmoji'] ?? '🍽️', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${m['recipeName']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${m['mealType'] ?? ''} · ${_f(m['calories'])} kcal · P ${_f(m['protein'])} C ${_f(m['carbs'])} F ${_f(m['fat'])}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
              ),
              IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.red600), onPressed: () => _deleteMeal(m['id'] as String)),
            ]),
          ),
        ),
    ];
  }

  List<Widget> _plannedSection() {
    return [
      const SizedBox(height: 16),
      const Text('Planned (not eaten yet)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 8),
      for (final p in _planned)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            background: AppColors.blue50,
            onTap: () => Navigator.of(context).pushNamed('/planned/${p['id']}').then((_) => _load()),
            child: Row(children: [
              Text(p['recipeEmoji'] ?? '🍽️', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p['recipeName']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${p['mealType']} · ${_f(p['calories'])} kcal · tap to view recipe and log it after cooking', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
              ),
              IconButton(icon: const Icon(Icons.close, color: AppColors.muted), onPressed: () => _deletePlanned(p['id'] as String)),
            ]),
          ),
        ),
    ];
  }

  List<Widget> _adherence(Map<String, dynamic> r) {
    final history = r['history'] as List;
    final cfg = r['config']['ranges'] as Map<String, dynamic>;
    Widget stat(String value, String label) => Expanded(
          child: Column(children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.green700)),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ]),
        );
    Widget period(int d) => GestureDetector(
          onTap: () { setState(() => _days = d); _load(); },
          child: Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: _days == d ? AppColors.green600 : const Color(0xFFEEF2EC), borderRadius: BorderRadius.circular(999)),
            child: Text('$d days', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _days == d ? Colors.white : AppColors.inkSoft)),
          ),
        );
    String range(String k) => '${_f((cfg[k] as List)[0])}-${_f((cfg[k] as List)[1])}%';

    return [
      const SizedBox(height: 22),
      Row(children: [
        const Expanded(child: Text('Adherence', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        period(7),
        period(30),
      ]),
      const SizedBox(height: 10),
      AppCard(
        background: AppColors.green50,
        child: Column(children: [
          Row(children: [
            stat('${r['adherenceRate']}%', 'Adherence rate\n(${r['adherentDays']} of ${r['observationDays']} days)'),
            stat('${r['loggingCompleteness']}%', 'Logging completeness\n(${r['loggedDays']} days logged)'),
            stat('${r['noRecordDays']}', 'Days with\nno records'),
          ]),
          const SizedBox(height: 10),
          Text(
            'A day is on target when all four are inside the range: Calories ${range('calories')}, Protein ${range('protein')}, Carbs ${range('carbs')}, Fat ${range('fat')}. Days without records are shown separately and are not treated as failures. Ends yesterday; today is still in progress.',
            style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft, height: 1.35),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      for (final h in history.reversed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Text(h['status'] == 'adherent' ? '✅' : (h['status'] == 'no_records' ? '➖' : '❌')),
            const SizedBox(width: 10),
            Expanded(child: Text('${h['date']}', style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(
              h['hasRecords'] == true
                  ? '${_f(h['components']['calories']['percent'])}% kcal · ${_f(h['components']['protein']['percent'])}% protein'
                  : 'no records',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ]),
        ),
    ];
  }
}
