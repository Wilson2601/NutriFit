import 'package:flutter/material.dart';
import '../widgets/coach_nav.dart';
import '../widgets/page_back_button.dart';
import '../widgets/user_avatar.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme.dart';

const _filters = ['All', 'On Track', 'Review'];
const _statusStyle = {
  'low': {'bg': AppColors.yellow100, 'text': Color(0xFF8A6D16)},
  'off_track': {'bg': AppColors.red100, 'text': AppColors.red600},
  'on_track': {'bg': AppColors.green100, 'text': AppColors.green700},
  'no_data': {'bg': Color(0xFFEEF0F3), 'text': Color(0xFF6B7280)},
};

class ClientListScreen extends StatefulWidget {
  const ClientListScreen({super.key});
  @override
  State<ClientListScreen> createState() => _ClientListScreenState();
}

class _ClientListScreenState extends State<ClientListScreen> {
  List<dynamic> _clients = [];
  String _filter = 'All';
  String _search = '';
  String? _error;
  bool _loading = true;
  bool _showAdd = false;
  final _emailController = TextEditingController();
  String? _addError;
  bool _adding = false;

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
      final data = await api.coachClients(auth.token!, status: _filter, search: _search);
      if (mounted) setState(() { _clients = data['clients']; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addClient() async {
    setState(() { _adding = true; _addError = null; });
    try {
      final auth = context.read<AuthService>();
      final api = context.read<ApiService>();
      await api.addClient(auth.token!, _emailController.text.trim());
      _emailController.clear();
      setState(() => _showAdd = false);
      await _load();
    } on ApiException catch (e) {
      setState(() => _addError = e.message);
    } finally {
      setState(() => _adding = false);
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
            const PageBackButton(fallbackRoute: '/coach'),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('My Clients', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                TextButton(
                  onPressed: () => setState(() => _showAdd = !_showAdd),
                  style: TextButton.styleFrom(backgroundColor: AppColors.blue100, shape: const StadiumBorder()),
                  child: const Text('+ Add', style: TextStyle(color: AppColors.blue700, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if (_showAdd) ...[
              const SizedBox(height: 14),
              AppCard(
                background: AppColors.blue50,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Add client by email', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    if (_addError != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_addError!, style: const TextStyle(color: AppColors.red600))),
                    TextField(controller: _emailController, decoration: const InputDecoration(labelText: "Client's registered email", filled: true, fillColor: Colors.white)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue600),
                      onPressed: _adding ? null : _addClient,
                      child: Text(_adding ? 'Adding…' : 'Add to Roster'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(hintText: 'Search clients...', prefixIcon: Icon(Icons.search)),
              onChanged: (v) { _search = v; _load(); },
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final f = _filters[i];
                  final selected = _filter == f;
                  return ChoiceChip(
                    label: Text(f),
                    selected: selected,
                    onSelected: (_) { setState(() => _filter = f); _load(); },
                    selectedColor: AppColors.blue600,
                    labelStyle: TextStyle(color: selected ? Colors.white : AppColors.ink, fontWeight: FontWeight.w700),
                    backgroundColor: Colors.white,
                    shape: const StadiumBorder(),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.red600)),
            if (_loading) const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator())),
            if (!_loading && _clients.isEmpty)
              const AppCard(background: AppColors.blue50, child: Center(child: Text('No clients match. Try "+ Add" to link a client by their registered email.', style: TextStyle(color: AppColors.muted), textAlign: TextAlign.center))),
            if (!_loading)
              ..._clients.map((c) {
                final style = (_statusStyle[c['status']] ?? _statusStyle['no_data']!);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: AppCard(
                    background: style['bg'] as Color,
                    onTap: () => Navigator.of(context).pushNamed('/coach/clients/${c['id']}'),
                    child: Row(
                      children: [
                        PersonAvatar(data: c, size: 50, color: style['text'] as Color),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c['name'], style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text('${(c['goal'] as String).replaceAll('_', ' ')} · ${c['weightKg']} kg', style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                              Text('Protein: ${c['protein']}/${c['proteinTarget']}g · Carbs: ${c['carbs']}/${c['carbsTarget']}g', style: TextStyle(color: style['text'] as Color, fontWeight: FontWeight.w700, fontSize: 12)),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            StatusPill(label: '${c['statusIcon']} ${c['statusLabel']}', background: Colors.white, textColor: style['text'] as Color),
                            const SizedBox(height: 8),
                            const Icon(Icons.chevron_right, color: AppColors.muted),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
