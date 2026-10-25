import 'package:flutter/material.dart';
import '../widgets/coach_nav.dart';
import '../widgets/user_avatar.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme.dart';

class SetTargetsScreen extends StatefulWidget {
  final String clientId;
  const SetTargetsScreen({super.key, required this.clientId});
  @override
  State<SetTargetsScreen> createState() => _SetTargetsScreenState();
}

class _SetTargetsScreenState extends State<SetTargetsScreen> {
  Map<String, dynamic>? _client;
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _calories = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    try {
      final data = await api.clientDetail(auth.token!, widget.clientId);
      final client = data['client'];
      final target = client['target'];
      if (mounted) {
        setState(() {
          _client = client;
          if (target != null) {
            _protein.text = '${target['proteinG']}';
            _carbs.text = '${target['carbsG']}';
            _fat.text = '${target['fatG']}';
            _calories.text = '${target['calories']}';
          }
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final auth = context.read<AuthService>();
      final api = context.read<ApiService>();
      await api.setClientTargets(auth.token!, widget.clientId, {
        'proteinG': double.tryParse(_protein.text) ?? 0,
        'carbsG': double.tryParse(_carbs.text) ?? 0,
        'fatG': double.tryParse(_fat.text) ?? 0,
        'calories': double.tryParse(_calories.text) ?? 0,
      });
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
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
                    const Text('Set Macro Targets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    if (_client != null)
                      Text('${_client!['name']} · ${(_client!['goal'] as String).replaceAll('_', ' ')}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 20),
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(_error!, style: const TextStyle(color: AppColors.red600))),
            if (_client != null)
              AppCard(
                background: AppColors.blue50,
                child: Row(children: [
                  PersonAvatar(data: _client, size: 50, color: AppColors.blue600),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_client!['name'], style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${_client!['weightKg']} kg current', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ],
                  ),
                ]),
              ),
            const SizedBox(height: 22),
            const Text('DAILY MACRO TARGETS', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)),
            const SizedBox(height: 14),
            _macroField('🥩', 'Protein', 'For muscle synthesis', AppColors.green100, AppColors.green700, _protein, 'g'),
            const SizedBox(height: 14),
            _macroField('🌾', 'Carbohydrates', 'Primary energy source', AppColors.orange100, AppColors.orange600, _carbs, 'g'),
            const SizedBox(height: 14),
            _macroField('🥑', 'Dietary Fat', 'Hormonal balance', AppColors.blue100, AppColors.blue700, _fat, 'g'),
            const SizedBox(height: 14),
            _macroField('⚡', 'Total Calories', 'Drives the recipe scaling engine', AppColors.purple100, AppColors.purple600, _calories, 'kcal'),
            const SizedBox(height: 22),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue600),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : '💾 Save & Notify Client'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }

  Widget _macroField(String icon, String label, String sub, Color bg, Color color, TextEditingController controller, String unit) {
    return AppCard(
      background: bg,
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(sub, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
              ],
            ),
          ),
          SizedBox(
            width: 70,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
              decoration: const InputDecoration(border: InputBorder.none, filled: false, contentPadding: EdgeInsets.zero, isDense: true),
            ),
          ),
          Text(unit, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
