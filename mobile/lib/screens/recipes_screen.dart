import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/page_back_button.dart';

const _tags = ['All', 'Protein', 'Low Carb', 'Quick Prep', 'Balanced'];
const _tagColors = {
  'Protein': AppColors.green100,
  'Low Carb': AppColors.yellow100,
  'Quick Prep': AppColors.purple100,
  'Balanced': AppColors.blue100,
};
const _cardBgs = [AppColors.green100, AppColors.blue100, AppColors.yellow100, AppColors.purple100, AppColors.blue50];

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  List<dynamic> _recipes = [];
  String _tag = 'All';
  String _search = '';
  String? _error;
  bool _loading = true;
  bool _searchingOnline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    try {
      final data = await api.recipes(auth.token!, tag: _tag, search: _search);
      if (mounted) setState(() { _recipes = data['recipes']; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchOnline() async {
    final q = _search.trim();
    if (q.length < 2) return;
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    setState(() => _searchingOnline = true);
    try {
      final data = await api.onlineRecipes(auth.token!, q);
      final found = (data['recipes'] as List);
      if (!mounted) return;
      // The server saved them, so reload the normal list and they appear like any other recipe.
      await _load();
      messenger.showSnackBar(SnackBar(content: Text(found.isEmpty ? 'No online recipes found for "$q"' : 'Added ${found.length} recipes from online search')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _searchingOnline = false);
    }
  }

  Widget _onlineSearchCard() {
    final q = _search.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        background: Colors.white,
        onTap: _searchingOnline ? null : _searchOnline,
        child: Row(children: [
          const Text('🌐', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Search online for "$q"', style: const TextStyle(fontWeight: FontWeight.w800)),
              const Text('Find more recipes with ingredients and cooking steps', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
          if (_searchingOnline)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            const Icon(Icons.chevron_right, color: AppColors.muted),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showOnline = _search.trim().length >= 2;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PageBackButton(),
                  const SizedBox(height: 12),
                  const Text('Recipes 🍽️', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: const InputDecoration(hintText: 'Search recipes or ingredients...', prefixIcon: Icon(Icons.search)),
                    onChanged: (v) { _search = v; _debouncedLoad(); },
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _tags.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final t = _tags[i];
                        final selected = _tag == t;
                        return ChoiceChip(
                          label: Text(t == 'All' ? '🥗 All' : t),
                          selected: selected,
                          onSelected: (_) { setState(() => _tag = t); _load(); },
                          selectedColor: AppColors.green600,
                          labelStyle: TextStyle(color: selected ? Colors.white : AppColors.ink, fontWeight: FontWeight.w700),
                          backgroundColor: Colors.white,
                          shape: const StadiumBorder(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: AppColors.red600))),
            if (_loading) const Expanded(child: Center(child: CircularProgressIndicator())),
            if (!_loading)
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                  itemCount: _recipes.length + (showOnline ? 1 : 0) + (_recipes.isEmpty ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_recipes.isEmpty && index == 0) {
                      return const Padding(
                        padding: EdgeInsets.fromLTRB(8, 8, 8, 16),
                        child: Text('No saved recipes match your search.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                      );
                    }
                    final offset = _recipes.isEmpty ? 1 : 0;
                    if (showOnline && index == _recipes.length + offset) return _onlineSearchCard();
                    final i = index - offset;
                    final r = _recipes[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: AppCard(
                        background: _cardBgs[i % _cardBgs.length],
                        onTap: () => Navigator.of(context).pushNamed('/scale/${r['id']}'),
                        child: Row(
                          children: [
                            Container(
                              width: 54, height: 54,
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                              child: Center(child: Text(r['emoji'] ?? '🍽️', style: const TextStyle(fontSize: 24))),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 4),
                                  Text('${r['baseProtein']}g P · ${r['baseCarbs']}g C · ${r['baseFat']}g F', style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
                                  const SizedBox(height: 4),
                                  Text('${r['baseCalories']} kcal', style: const TextStyle(color: AppColors.green700, fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                            if (r['tag'] != null)
                              StatusPill(label: r['tag'], background: _tagColors[r['tag']] ?? Colors.white, textColor: AppColors.ink),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 1),
    );
  }

  DateTime? _lastKeystroke;
  void _debouncedLoad() {
    final now = DateTime.now();
    _lastKeystroke = now;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (_lastKeystroke == now) _load();
    });
  }
}
