import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';

const _mealTypes = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

/// Search free online food databases (USDA + Open Food Facts) and log any food by weight.
/// Foods that are not in the databases (for example a hawker dish) can be added by hand.
class FoodSearchScreen extends StatefulWidget {
  const FoodSearchScreen({super.key});

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  List<String> _warnings = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.length < 2) return;
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    FocusScope.of(context).unfocus();
    setState(() { _loading = true; _error = null; });
    try {
      final res = await api.searchFoods(auth.token!, q);
      if (!mounted) return;
      setState(() {
        _items = (res['items'] as List).cast<Map<String, dynamic>>();
        _warnings = (res['warnings'] as List).cast<String>();
        _searched = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Opens the amount picker. [food] is null when adding a custom food by hand.
  Future<void> _openLogSheet(Map<String, dynamic>? food) async {
    final logged = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _LogFoodSheet(food: food),
    );
    if (logged == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Food logged')));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text('Find Foods', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'Search a food, e.g. chicken breast, nasi lemak',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDFE6DB))),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18)),
              onPressed: _loading ? null : _search,
              child: const Text('Search'),
            ),
          ]),
        ),
        Expanded(child: _results()),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.green600,
        foregroundColor: Colors.white,
        onPressed: () => _openLogSheet(null),
        icon: const Icon(Icons.edit_note),
        label: const Text('Add custom food'),
      ),
    );
  }

  Widget _results() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: AppColors.red600))));
    if (!_searched) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Search millions of foods from USDA and Open Food Facts, or add your own.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
      children: [
        ..._warnings.map((w) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('⚠️ $w', style: const TextStyle(color: AppColors.orange600, fontSize: 12)))),
        if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No results. Try a simpler word, or add it with "Add custom food".', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          ),
        ..._items.map((f) {
          final p = f['per100g'] as Map<String, dynamic>;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              background: Colors.white,
              onTap: () => _openLogSheet(f),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(f['name'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      '${f['brand'] != null ? '${f['brand']} · ' : ''}${f['source']}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text('per 100 g: ${p['calories']} kcal · P ${p['protein']} · C ${p['carbs']} · F ${p['fat']}',
                        style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                  ]),
                ),
                const Icon(Icons.add_circle_outline, color: AppColors.green600),
              ]),
            ),
          );
        }),
      ],
    );
  }
}

class _LogFoodSheet extends StatefulWidget {
  final Map<String, dynamic>? food;
  const _LogFoodSheet({required this.food});

  @override
  State<_LogFoodSheet> createState() => _LogFoodSheetState();
}

class _LogFoodSheetState extends State<_LogFoodSheet> {
  late final TextEditingController _name;
  late final TextEditingController _grams;
  final _cal = TextEditingController();
  final _pro = TextEditingController();
  final _carb = TextEditingController();
  final _fat = TextEditingController();
  String _mealType = 'Lunch';
  bool _saving = false;
  String? _error;

  bool get _custom => widget.food == null;

  @override
  void initState() {
    super.initState();
    final f = widget.food;
    _name = TextEditingController(text: (f?['name'] ?? '') as String);
    _grams = TextEditingController(text: '${f?['servingG'] ?? 100}');
    final hour = DateTime.now().hour;
    _mealType = hour < 11 ? 'Breakfast' : hour < 16 ? 'Lunch' : hour < 21 ? 'Dinner' : 'Snack';
    _grams.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_name, _grams, _cal, _pro, _carb, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _n(TextEditingController c) => double.tryParse(c.text.trim());

  /// Nutrients per 100 g: from the database item, or typed in for a custom food.
  Map<String, double?> get _per100g {
    final p = widget.food?['per100g'] as Map<String, dynamic>?;
    if (p != null) {
      return {for (final k in ['calories', 'protein', 'carbs', 'fat']) k: (p[k] as num).toDouble()};
    }
    return {'calories': _n(_cal), 'protein': _n(_pro), 'carbs': _n(_carb), 'fat': _n(_fat)};
  }

  // One id per form, so pressing Save twice cannot log the same food twice.
  final String _requestId = 'food-${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _save() async {
    final grams = _n(_grams);
    final per = _per100g;
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Enter a food name.');
    if (grams == null || grams < 1) return setState(() => _error = 'Enter the amount in grams.');
    if (per.values.any((v) => v == null)) return setState(() => _error = 'Fill in calories, protein, carbs and fat.');

    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final navigator = Navigator.of(context);
    setState(() { _saving = true; _error = null; });
    try {
      await api.logFood(auth.token!, {
        'name': _name.text.trim(),
        'grams': grams,
        'mealType': _mealType,
        'source': widget.food?['source'] ?? 'custom',
        'requestId': _requestId,
        'caloriesPer100g': per['calories'],
        'proteinPer100g': per['protein'],
        'carbsPer100g': per['carbs'],
        'fatPer100g': per['fat'],
      });
      navigator.pop(true);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _saving = false; });
    }
  }

  Widget _numField(String label, TextEditingController c) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final grams = _n(_grams) ?? 0;
    final per = _per100g;
    String scaled(String k) => per[k] == null ? '–' : (per[k]! * grams / 100).toStringAsFixed(0);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_custom ? 'Add custom food' : 'Log food', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Food name')),
          const SizedBox(height: 12),
          Row(children: [
            _numField('Amount (g)', _grams),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _mealType,
                decoration: const InputDecoration(labelText: 'Meal'),
                items: _mealTypes.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => setState(() => _mealType = v ?? _mealType),
              ),
            ),
          ]),
          if (_custom) ...[
            const SizedBox(height: 12),
            const Text('Nutrition per 100 g (check the food label)', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 6),
            Row(children: [_numField('kcal', _cal), _numField('Protein', _pro), _numField('Carbs', _carb), _numField('Fat', _fat)]),
          ],
          const SizedBox(height: 14),
          AppCard(
            background: AppColors.green50,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _stat(scaled('calories'), 'kcal'),
              _stat(scaled('protein'), 'protein g'),
              _stat(scaled('carbs'), 'carbs g'),
              _stat(scaled('fat'), 'fat g'),
            ]),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: AppColors.red600))),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Log this food'))),
        ]),
      ),
    );
  }

  Widget _stat(String v, String l) => Column(children: [
        Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.green700)),
        Text(l, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
      ]);
}
