import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/page_back_button.dart';

const _categoryBg = {
  'Proteins': AppColors.green100,
  'Carbohydrates': AppColors.orange100,
  'Vegetables': AppColors.green50,
  'Fats & Oils': AppColors.blue100,
  'Other': Color(0xFFF2F2F2),
};
const _categoryIcon = {
  'Proteins': '🍖', 'Carbohydrates': '🌾', 'Vegetables': '🥦', 'Fats & Oils': '🫒', 'Other': '🛒',
};

class GroceryScreen extends StatefulWidget {
  const GroceryScreen({super.key});
  @override
  State<GroceryScreen> createState() => _GroceryScreenState();
}

class _GroceryScreenState extends State<GroceryScreen> {
  List<dynamic> _items = [];
  int _recipeCount = 0;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    try {
      final data = await api.grocery(auth.token!);
      if (mounted) setState(() { _items = data['items']; _recipeCount = data['recipe_count']; _loading = false; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _toggle(Map item) async {
    final wasChecked = item['checked'] as bool;
    setState(() => item['checked'] = !wasChecked);
    try {
      final auth = context.read<AuthService>();
      final api = context.read<ApiService>();
      await api.toggleGroceryItem(auth.token!, item['id'], !wasChecked);
    } on ApiException {
      setState(() => item['checked'] = wasChecked);
    }
  }

  Future<void> _clear(String scope) async {
    if (scope == 'all') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Clear the whole list?'),
          content: const Text('All items will be removed, including the ones you have not checked.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Clear all')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    try {
      final auth = context.read<AuthService>();
      final api = context.read<ApiService>();
      await api.clearGrocery(auth.token!, scope);
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<dynamic>>{};
    for (final item in _items) {
      grouped.putIfAbsent(item['category'] ?? 'Other', () => []).add(item);
    }
    final checkedCount = _items.where((i) => i['checked'] == true).length;
    final pct = _items.isEmpty ? 0 : (checkedCount / _items.length * 100);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  children: [
                    const PageBackButton(),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Grocery List 🛒', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                        StatusPill(label: '$_recipeCount recipes', background: AppColors.green100, textColor: AppColors.green700),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$checkedCount of ${_items.length} items checked', style: const TextStyle(color: AppColors.muted)),
                        Text('${pct.toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.green600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(value: pct / 100, minHeight: 8, backgroundColor: const Color(0xFFE6EDE4), valueColor: const AlwaysStoppedAnimation(AppColors.green600)),
                    ),
                    const SizedBox(height: 14),
                    if (_items.isNotEmpty)
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: checkedCount == 0 ? null : () => _clear('checked'),
                            child: Text('🧹 Clear checked ($checkedCount)'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: OutlinedButton(onPressed: () => _clear('all'), child: const Text('🗑️ Clear all'))),
                      ]),
                    const SizedBox(height: 20),
                    if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.red600)),
                    if (grouped.isEmpty && _error == null)
                      const AppCard(
                        background: AppColors.green50,
                        child: Center(child: Text('Your list is empty. Scale a recipe and tap "Add to Grocery" to fill it up.', style: TextStyle(color: AppColors.muted), textAlign: TextAlign.center)),
                      ),
                    ...grouped.entries.map((entry) {
                      final bg = _categoryBg[entry.key] ?? _categoryBg['Other']!;
                      final icon = _categoryIcon[entry.key] ?? '🛒';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: AppCard(
                          background: bg,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$icon ${entry.key}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                              const SizedBox(height: 10),
                              ...entry.value.map((it) => Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Row(
                                      children: [
                                        GestureDetector(
                                          onTap: () => _toggle(it),
                                          child: Container(
                                            width: 24, height: 24,
                                            decoration: BoxDecoration(
                                              color: it['checked'] == true ? AppColors.green600 : Colors.white,
                                              borderRadius: BorderRadius.circular(7),
                                              border: it['checked'] == true ? null : Border.all(color: const Color(0xFFD7DED4), width: 1.5),
                                            ),
                                            child: it['checked'] == true ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            it['name'],
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              decoration: it['checked'] == true ? TextDecoration.lineThrough : null,
                                              color: it['checked'] == true ? AppColors.muted : AppColors.ink,
                                            ),
                                          ),
                                        ),
                                        Text('${it['amount'] ?? ''}${it['unit'] ?? ''}', style: TextStyle(color: it['checked'] == true ? AppColors.muted : AppColors.inkSoft)),
                                      ],
                                    ),
                                  )),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 3),
    );
  }
}
