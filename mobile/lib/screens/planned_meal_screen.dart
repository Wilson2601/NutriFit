import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme.dart';

/// Route: /planned/<id>. Shows the planned recipe (ingredient weights + cooking steps).
/// After cooking, "Log meal" counts it as eaten, then the camera photo is taken on the Daily Mission page.
class PlannedMealScreen extends StatefulWidget {
  final String plannedId;
  const PlannedMealScreen({super.key, required this.plannedId});
  @override
  State<PlannedMealScreen> createState() => _PlannedMealScreenState();
}

class _PlannedMealScreenState extends State<PlannedMealScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  bool _logged = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    try {
      final data = await api.plannedMeal(auth.token!, widget.plannedId);
      if (mounted) setState(() { _data = data; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _logMeal() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log this meal?'),
        content: const Text('Do this after you have cooked and eaten it. It will be added to today\'s intake.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not yet')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Yes, log it')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final plan = _data!['planned'] as Map<String, dynamic>;
    final payload = <String, dynamic>{
      'recipeId': plan['recipeId'],
      'mealType': plan['mealType'] ?? 'Lunch',
      'plannedId': widget.plannedId,
      'requestId': 'planned-${widget.plannedId}', // logging the same plan twice is ignored
    };
    if (plan['ingredients'] != null) {
      payload['ingredients'] = [
        for (final i in plan['ingredients'] as List) {'name': i['name'], 'amount': i['amount']},
      ];
    } else {
      payload['portionFactor'] = plan['portionFactor'];
    }

    setState(() { _busy = true; _error = null; });
    try {
      final auth = context.read<AuthService>();
      final api = context.read<ApiService>();
      await api.consumeMeal(auth.token!, payload);
      if (mounted) setState(() { _logged = true; _busy = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _busy = false; });
    }
  }

  Future<void> _removePlan() async {
    setState(() => _busy = true);
    try {
      final auth = context.read<AuthService>();
      final api = context.read<ApiService>();
      await api.deletePlannedMeal(auth.token!, widget.plannedId);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _busy = false; });
    }
  }

  static String _n(dynamic v) => v is num ? v.toStringAsFixed(0) : '-';

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
                      _data == null ? 'Loading…' : '${_data!['planned']['recipeEmoji'] ?? ''} ${_data!['planned']['recipeName']}',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                    const Text('Planned meal', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ]),
                ),
              ]),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: const TextStyle(color: AppColors.red600))),
              if (_data == null && _error == null) const Expanded(child: Center(child: CircularProgressIndicator())),
              if (_data != null) Expanded(child: _content(_data!)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(Map<String, dynamic> data) {
    final plan = data['planned'] as Map<String, dynamic>;
    final ingredients = data['ingredients'] as List;
    final steps = (data['steps'] as List?) ?? const [];
    final minutes = data['readyInMinutes'];

    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 28),
      children: [
        AppCard(
          background: AppColors.green50,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${plan['mealType'] ?? ''} · ${_n(plan['calories'])} kcal', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Protein ${_n(plan['protein'])} g · Carbs ${_n(plan['carbs'])} g · Fat ${_n(plan['fat'])} g', style: const TextStyle(color: AppColors.green700, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 20),
        const Text('Ingredients to use', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        for (final ing in ingredients)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFEEF2EC))),
              child: Row(children: [
                Text(ing['emoji'] ?? '🥗', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(child: Text(ing['name'], style: const TextStyle(fontWeight: FontWeight.w700))),
                StatusPill(label: '${_n(ing['amount'])}${ing['unit']}', background: AppColors.green100, textColor: AppColors.green700),
              ]),
            ),
          ),
        if (steps.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(children: [
            const Text('How to Cook', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            if (minutes != null) Text('⏱ $minutes min', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ]),
          const SizedBox(height: 10),
          for (var i = 0; i < steps.length; i++)
            Padding(
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
            ),
        ],
        const SizedBox(height: 14),
        if (_logged) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.green100, borderRadius: BorderRadius.circular(16)),
            child: const Text('✅ Meal logged. Now take a photo of your cooked meal with the camera to complete today\'s mission.', style: TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
          ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: () => Navigator.of(context).pushReplacementNamed('/mission'), child: const Text('📸 Take meal photo')),
        ] else ...[
          ElevatedButton(onPressed: _busy ? null : _logMeal, child: Text(_busy ? 'Saving…' : '✅ I cooked it · Log meal')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _busy ? null : _removePlan, child: const Text('Remove from plan')),
        ],
      ],
    );
  }
}
