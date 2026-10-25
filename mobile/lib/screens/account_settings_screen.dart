import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';

const _goals = {
  'muscle_gain': '💪 Build muscle',
  'weight_loss': '🔥 Lose weight',
  'maintain': '⚡ Maintain',
  'performance': '🏆 Performance',
};

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _weight;
  late final TextEditingController _goalWeight;
  late String _goal;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthService>().user ?? {};
    _name = TextEditingController(text: (u['name'] ?? '') as String);
    _phone = TextEditingController(text: (u['phone'] ?? '') as String);
    _weight = TextEditingController(text: u['weightKg']?.toString() ?? '');
    _goalWeight = TextEditingController(text: u['goalWeightKg']?.toString() ?? '');
    _goal = _goals.containsKey(u['goal']) ? u['goal'] as String : 'maintain';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _weight.dispose();
    _goalWeight.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final isCoach = auth.role == 'coach';
    final changes = <String, dynamic>{
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      if (!isCoach) 'goal': _goal,
    };
    final w = isCoach ? null : double.tryParse(_weight.text.trim());
    final gw = isCoach ? null : double.tryParse(_goalWeight.text.trim());
    if (!isCoach && _weight.text.trim().isNotEmpty && w == null) return setState(() => _error = 'Weight must be a number.');
    if (!isCoach && _goalWeight.text.trim().isNotEmpty && gw == null) return setState(() => _error = 'Goal weight must be a number.');
    if (w != null) changes['weightKg'] = w;
    if (gw != null) changes['goalWeightKg'] = gw;

    setState(() { _saving = true; _error = null; });
    try {
      final res = await api.updateProfile(auth.token!, changes);
      auth.updateUser(res['user'] as Map<String, dynamic>);
      messenger.showSnackBar(const SnackBar(content: Text('Profile saved')));
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController c, {TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(controller: c, keyboardType: type, decoration: InputDecoration(labelText: label)),
      );

  @override
  Widget build(BuildContext context) {
    final email = (context.read<AuthService>().user?['email'] ?? '') as String;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(backgroundColor: Colors.white, foregroundColor: AppColors.ink, elevation: 0,
          title: const Text('Account Settings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _field('Full name', _name),
          _field('Phone', _phone, type: TextInputType.phone),
          if (context.read<AuthService>().role != 'coach') ...[
          _field('Current weight (kg)', _weight, type: const TextInputType.numberWithOptions(decimal: true)),
          _field('Goal weight (kg)', _goalWeight, type: const TextInputType.numberWithOptions(decimal: true)),
          DropdownButtonFormField<String>(
            value: _goal,
            decoration: const InputDecoration(labelText: 'Goal'),
            items: _goals.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => setState(() => _goal = v ?? _goal),
          ),
          ],
          const SizedBox(height: 14),
          Text('Email: $email (cannot be changed here)', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: AppColors.red600))),
          const SizedBox(height: 22),
          ElevatedButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save changes')),
        ],
      ),
    );
  }
}
