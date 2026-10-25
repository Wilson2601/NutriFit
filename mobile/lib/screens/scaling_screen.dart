import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/page_back_button.dart';

const List<String> kMealTypes = ['Breakfast', 'Lunch', 'Dinner', 'Supper', 'Other'];
const Map<String, String> kFutureLabels = {'yes': 'Yes', 'no': 'No', 'not_sure': 'Not sure'};

/// Route: /scale (step 1-4: nutrition left, meal type, next-meal question, recipe)
///        /scale/:id (step 5-8: optimise, review, confirm). `arguments` may carry mealType / futureMeal.
class ScalingScreen extends StatelessWidget {
  final String? recipeId;
  final String mealType;
  final String futureMeal;
  const ScalingScreen({super.key, this.recipeId, this.mealType = 'Lunch', this.futureMeal = 'not_sure'});

  @override
  Widget build(BuildContext context) {
    if (recipeId == null) return const _RecipePicker();
    return _OptimizedDetail(recipeId: recipeId!, mealType: mealType, futureMeal: futureMeal);
  }
}

String _n(dynamic v, [int digits = 0]) => v == null ? '-' : (v as num).toStringAsFixed(digits);

/// "Meal type" chips + "Will you have another meal today?" chips.
class _MealContextPicker extends StatelessWidget {
  final String mealType;
  final String futureMeal;
  final ValueChanged<String> onMealType;
  final ValueChanged<String> onFutureMeal;
  const _MealContextPicker({required this.mealType, required this.futureMeal, required this.onMealType, required this.onFutureMeal});

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: active ? AppColors.green600 : const Color(0xFFEEF2EC), borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: active ? Colors.white : AppColors.inkSoft)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Meal type', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final m in kMealTypes) _chip(m, m == mealType, () => onMealType(m))]),
        const SizedBox(height: 14),
        const Text('Will you have another meal today?', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in kFutureLabels.entries) _chip(e.value, e.key == futureMeal, () => onFutureMeal(e.key)),
        ]),
      ],
    );
  }
}

class _RecipePicker extends StatefulWidget {
  const _RecipePicker();
  @override
  State<_RecipePicker> createState() => _RecipePickerState();
}

class _RecipePickerState extends State<_RecipePicker> {
  List<dynamic> _recipes = [];
  Map<String, dynamic>? _summary;
  bool _loading = true;
  String? _error;
  String _mealType = 'Lunch';
  String _futureMeal = 'not_sure';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    try {
      final data = await api.recipes(auth.token!);
      final summary = await api.nutritionSummary(auth.token!);
      if (mounted) setState(() { _recipes = data['recipes']; _summary = summary; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  Widget _remainingCard() {
    final s = _summary;
    if (s == null) return const SizedBox.shrink();
    final rem = s['remaining'] as Map<String, dynamic>;
    final over = (s['components'] as Map<String, dynamic>)['calories']['over'] as num;
    Widget cell(String label, String value) => Expanded(
          child: Column(children: [
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        );
    return AppCard(
      background: AppColors.green600,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Remaining today', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(children: [
          cell('kcal', _n(rem['calories'])),
          cell('Protein g', _n(rem['protein'])),
          cell('Carbs g', _n(rem['carbs'])),
          cell('Fat g', _n(rem['fat'])),
        ]),
        if (over > 0) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('You are ${_n(over)} kcal over today\'s target.', style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
        const SizedBox(height: 4),
        const Text('Only meals you confirmed as eaten are counted.', style: TextStyle(color: Colors.white70, fontSize: 11)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    const PageBackButton(),
                    const SizedBox(height: 12),
                    const Text('⚖️ Optimize a Recipe', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text(
                      'Each ingredient is adjusted separately so the meal fits what you still need today.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 16),
                    if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.red600)),
                    _remainingCard(),
                    const SizedBox(height: 18),
                    _MealContextPicker(
                      mealType: _mealType,
                      futureMeal: _futureMeal,
                      onMealType: (v) => setState(() => _mealType = v),
                      onFutureMeal: (v) => setState(() => _futureMeal = v),
                    ),
                    const SizedBox(height: 20),
                    const Text('Choose a recipe', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    const SizedBox(height: 10),
                    for (final r in _recipes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppCard(
                          background: AppColors.green50,
                          onTap: () => Navigator.of(context).pushNamed(
                            '/scale/${r['id']}',
                            arguments: {'mealType': _mealType, 'futureMeal': _futureMeal},
                          ),
                          child: Row(children: [
                            Text(r['emoji'] ?? '🍽️', style: const TextStyle(fontSize: 24)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(r['name'], style: const TextStyle(fontWeight: FontWeight.w800)),
                                Text('${r['baseCalories']} kcal original recipe', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                              ]),
                            ),
                            const Icon(Icons.chevron_right, color: AppColors.green600),
                          ]),
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
        ),
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 2),
    );
  }
}

class _OptimizedDetail extends StatefulWidget {
  final String recipeId;
  final String mealType;
  final String futureMeal;
  const _OptimizedDetail({required this.recipeId, required this.mealType, required this.futureMeal});
  @override
  State<_OptimizedDetail> createState() => _OptimizedDetailState();
}

class _OptimizedDetailState extends State<_OptimizedDetail> {
  Map<String, dynamic>? _data;
  String? _error;
  String? _status; // saving | planned | logged
  bool _original = false;
  late String _mealType = widget.mealType;
  late String _futureMeal = widget.futureMeal;
  String _requestId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    setState(() { _error = null; _status = null; });
    try {
      final data = await api.optimizeRecipe(auth.token!, widget.recipeId, _mealType, _futureMeal);
      if (mounted) {
        setState(() {
          _data = data;
          // One id per optimisation result: a double tap on "I ate this" can never log the meal twice.
          _requestId = '${widget.recipeId}-${DateTime.now().microsecondsSinceEpoch}';
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Map<String, dynamic> _recordPayload() {
    final result = _data!['result'] as Map<String, dynamic>;
    final payload = <String, dynamic>{
      'recipeId': widget.recipeId,
      'mealType': _mealType,
      'futureMeal': _futureMeal,
      'requestId': _requestId,
    };
    if (result['method'] == 'ingredient_optimization') {
      payload['ingredients'] = [
        for (final i in result['ingredients'] as List) {'name': i['name'], 'amount': i['optimizedAmount']},
      ];
    } else {
      payload['portionFactor'] = result['factor'];
    }
    return payload;
  }

  Future<void> _savePlan() async {
    setState(() => _status = 'saving');
    try {
      final auth = context.read<AuthService>();
      final api = context.read<ApiService>();
      final payload = _recordPayload()..remove('requestId');
      await api.planMeal(auth.token!, payload);
      if (mounted) setState(() => _status = 'planned');
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _status = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: AppColors.green100, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.arrow_back, size: 18),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      _data == null ? 'Loading…' : '${_data!['recipe']['emoji']} ${_data!['recipe']['name']}',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                    const Text('Optimized Recipe', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ]),
                ),
              ]),
              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: const TextStyle(color: AppColors.red600))),
              if (_data == null && _error == null) const Expanded(child: Center(child: CircularProgressIndicator())),
              if (_data != null) Expanded(child: _detail(_data!)),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 2),
    );
  }

  Widget _detail(Map<String, dynamic> data) {
    final result = data['result'] as Map<String, dynamic>;
    final alloc = data['allocation'] as Map<String, dynamic>;
    final warnings = (result['warnings'] as List).cast<String>();
    final ingredients = result['ingredients'] as List;
    final comparison = result['comparison'] as Map<String, dynamic>;
    final fallback = result['method'] != 'ingredient_optimization';
    final busy = _status == 'saving';

    Widget row(String label, String target, String recipe, String diff, bool met, {bool header = false}) {
      final style = TextStyle(fontWeight: header ? FontWeight.w800 : FontWeight.w600, fontSize: 13, color: header ? AppColors.muted : AppColors.ink);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(flex: 3, child: Text(label, style: style)),
          Expanded(flex: 2, child: Text(target, style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text(recipe, style: style, textAlign: TextAlign.right)),
          Expanded(
            flex: 3,
            child: Text(diff, textAlign: TextAlign.right,
                style: style.copyWith(color: header ? AppColors.muted : (met ? AppColors.green700 : AppColors.red600))),
          ),
        ]),
      );
    }

    String diffText(Map<String, dynamic> c) {
      final d = (c['difference'] as num).toDouble();
      final sign = d > 0 ? '+' : '';
      final pct = c['differencePct'];
      return '$sign${d.toStringAsFixed(1)}${pct == null ? '' : ' (${(pct as num) > 0 ? '+' : ''}${pct.toStringAsFixed(1)}%)'}';
    }

    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      children: [
        _MealContextPicker(
          mealType: _mealType,
          futureMeal: _futureMeal,
          onMealType: (v) { setState(() => _mealType = v); _load(); },
          onFutureMeal: (v) { setState(() => _futureMeal = v); _load(); },
        ),
        const SizedBox(height: 16),
        AppCard(
          background: AppColors.green50,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Meal target', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              '${_n(alloc['allocated']['calories'])} kcal · P ${_n(alloc['allocated']['protein'])} g · C ${_n(alloc['allocated']['carbs'])} g · F ${_n(alloc['allocated']['fat'])} g',
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.green700),
            ),
            const SizedBox(height: 4),
            Text('Left today: ${_n(alloc['remaining']['calories'])} kcal · reserved for later: ${_n(alloc['reserved']['calories'])} kcal',
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            for (final note in (alloc['notes'] as List)) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $note', style: const TextStyle(fontSize: 12, color: AppColors.inkSoft))),
          ]),
        ),
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.orange100, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('⚠️ Heads up', style: TextStyle(fontWeight: FontWeight.w800)),
              for (final w in warnings) Padding(padding: const EdgeInsets.only(top: 4), child: Text(w, style: const TextStyle(fontSize: 12.5, height: 1.35))),
            ]),
          ),
        ],
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(fallback ? 'Ingredients (portion ×${result['factor']})' : 'Ingredients', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Row(children: [
            _toggleChip('Original', _original, () => setState(() => _original = true)),
            const SizedBox(width: 6),
            _toggleChip('Optimized ✨', !_original, () => setState(() => _original = false)),
          ]),
        ]),
        const SizedBox(height: 12),
        for (final ing in ingredients)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFEEF2EC))),
              child: Row(children: [
                Text(ing['emoji'] ?? '🥗', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(ing['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (ing['adjustable'] == false) const Text('kept as written', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                    if (ing['limit'] != null) Text('at its ${ing['limit']} limit', style: const TextStyle(color: AppColors.orange600, fontSize: 11)),
                  ]),
                ),
                if (!_original) ...[
                  Text('${_n(ing['originalAmount'], 0)}${ing['unit']}', style: const TextStyle(color: Color(0xFFC3CCC0), decoration: TextDecoration.lineThrough, fontSize: 13)),
                  const SizedBox(width: 8),
                  StatusPill(label: '${_n(ing['optimizedAmount'], 0)}${ing['unit']}', background: AppColors.green100, textColor: AppColors.green700),
                ] else
                  StatusPill(label: '${_n(ing['originalAmount'], 0)}${ing['unit']}', background: const Color(0xFFEEF2EC), textColor: AppColors.ink),
              ]),
            ),
          ),
        const SizedBox(height: 14),
        const Text('Nutritional comparison', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        AppCard(
          background: Colors.white,
          child: Column(children: [
            row('Nutrition', 'Target', 'Recipe', 'Difference', true, header: true),
            for (final e in const [['calories', 'Calories', 'kcal'], ['protein', 'Protein', 'g'], ['carbs', 'Carbs', 'g'], ['fat', 'Fat', 'g']])
              row(
                e[1],
                '${_n(comparison[e[0]]['target'], 0)} ${e[2]}',
                '${_n(comparison[e[0]]['recipe'], 0)} ${e[2]}',
                diffText(comparison[e[0]] as Map<String, dynamic>),
                comparison[e[0]]['met'] == true,
              ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                fallback
                    ? 'Estimated: this recipe has no ingredient-level nutrition data, so only the portion size was changed.'
                    : (result['status'] == 'exact' ? '✅ All four targets are within 5%.' : 'Closest recipe possible within the ingredient limits.'),
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          ]),
        ),
        ..._cookingSteps(data),
        const SizedBox(height: 12),
        if (_status == 'planned')
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.green100, borderRadius: BorderRadius.circular(16)),
            child: const Text(
              '📅 Planned! It is now in Today\'s Meals on Home and the ingredients were added to your Grocery List. Open it from Home when you are ready to cook. It only counts as eaten after you log it.',
              style: TextStyle(fontWeight: FontWeight.w600, height: 1.35),
            ),
          ),
        const SizedBox(height: 12),
        if (_status == 'planned')
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pushNamed('/grocery'), child: const Text('🛒 Grocery List'))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false), child: const Text('🏠 Today\'s Meals'))),
          ])
        else
          ElevatedButton(onPressed: busy ? null : _savePlan, child: Text(busy ? 'Saving…' : '📅 Plan to eat')),
      ],
    );
  }

  List<Widget> _cookingSteps(Map<String, dynamic> data) {
    final steps = (data['steps'] as List?) ?? const [];
    if (steps.isEmpty) return const [];
    final minutes = data['readyInMinutes'];
    final source = data['source'];
    return [
      const SizedBox(height: 20),
      Row(children: [
        const Text('How to Cook', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(width: 10),
        if (minutes != null) Text('⏱ $minutes min', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
      ]),
      const SizedBox(height: 4),
      const Text('Use the optimized amounts above.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
      const SizedBox(height: 12),
      ...List.generate(steps.length, (i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFEEF2EC))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 26, height: 26,
                  decoration: const BoxDecoration(color: AppColors.green100, shape: BoxShape.circle),
                  child: Center(child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.green700, fontSize: 13))),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(steps[i].toString(), style: const TextStyle(height: 1.4))),
              ]),
            ),
          )),
      if (source != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('Recipe data from $source', style: const TextStyle(color: AppColors.muted, fontSize: 11))),
    ];
  }

  Widget _toggleChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: active ? AppColors.green600 : const Color(0xFFEEF2EC), borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? Colors.white : AppColors.inkSoft)),
      ),
    );
  }
}
