import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

const _goals = [
  {'key': 'muscle_gain', 'icon': '💪', 'label': 'Build Muscle'},
  {'key': 'weight_loss', 'icon': '🔥', 'label': 'Lose Weight'},
  {'key': 'maintain', 'icon': '⚡', 'label': 'Maintain'},
  {'key': 'performance', 'icon': '🏆', 'label': 'Performance'},
];

class _RegisterScreenState extends State<RegisterScreen> {
  int _step = 1;
  String? _error;
  bool _busy = false;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _weightController = TextEditingController();
  final _goalWeightController = TextEditingController();
  String _goal = 'muscle_gain';

  void _next() {
    setState(() => _error = null);
    if (_step == 1) {
      if (_nameController.text.isEmpty || _emailController.text.isEmpty || _passwordController.text.isEmpty) {
        setState(() => _error = 'Please fill in your name, email, and password.');
        return;
      }
    }
    setState(() => _step = (_step + 1).clamp(1, 3));
  }

  void _back() => setState(() => _step = (_step - 1).clamp(1, 3));

  Future<void> _finish() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      await auth.register(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
            phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
            role: 'user',
            goal: _goal,
            weightKg: double.tryParse(_weightController.text),
            goalWeightKg: double.tryParse(_goalWeightController.text),
          );
      if (!mounted) return;
      context.read<NotificationService>().init(auth.token!);
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Registration failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.green500, AppColors.green600])),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Create Account 🌱', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                SizedBox(height: 6),
                Text('Join NutriFit today', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: List.generate(3, (i) => Expanded(
                            child: Container(
                              height: 5,
                              margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                              decoration: BoxDecoration(
                                color: i < _step ? AppColors.green600 : const Color(0xFFE4ECE2),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          )),
                    ),
                    const SizedBox(height: 14),
                    Text('Step $_step of 3 — ${_step == 1 ? 'Personal Info' : _step == 2 ? 'Body Stats' : 'Review'}',
                        style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 18),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.red100, borderRadius: BorderRadius.circular(12)),
                        child: Text(_error!, style: const TextStyle(color: AppColors.red600, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_step == 1) _stepOne(),
                    if (_step == 2) _stepTwo(),
                    if (_step == 3) _stepThree(),
                    const SizedBox(height: 20),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pushReplacementNamed('/login'),
                        child: const Text.rich(TextSpan(children: [
                          TextSpan(text: 'Already have an account? ', style: TextStyle(color: AppColors.muted)),
                          TextSpan(text: 'Sign in', style: TextStyle(color: AppColors.green700, fontWeight: FontWeight.w800)),
                        ])),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepOne() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Full Name')),
        const SizedBox(height: 14),
        TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email Address')),
        const SizedBox(height: 14),
        TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number')),
        const SizedBox(height: 14),
        TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
        const SizedBox(height: 20),
        const Text('Your fitness goal', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: _goals.map((g) {
            final selected = _goal == g['key'];
            return Material(
              color: AppColors.green50,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _goal = g['key']!),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: selected ? AppColors.green600 : Colors.transparent, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g['icon']!, style: const TextStyle(fontSize: 20)),
                      const SizedBox(height: 6),
                      Text(g['label']!, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? AppColors.green700 : AppColors.ink)),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 22),
        ElevatedButton(onPressed: _next, child: const Text('Next Step  →')),
      ],
    );
  }

  Widget _stepTwo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(controller: _weightController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Current Weight (kg)')),
        const SizedBox(height: 14),
        TextField(controller: _goalWeightController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Goal Weight (kg)')),
        const SizedBox(height: 16),
        const Text(
          "This helps your coach calibrate your starting macro targets. You can update it anytime from your profile.",
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: _back, child: const Text('Back'))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: ElevatedButton(onPressed: _next, child: const Text('Next Step  →'))),
          ],
        ),
      ],
    );
  }

  Widget _stepThree() {
    final goalLabel = _goals.firstWhere((g) => g['key'] == _goal)['label'];
    final rows = <List<String>>[
      ['Name', _nameController.text],
      ['Email', _emailController.text],
      ['Phone', _phoneController.text.isEmpty ? '—' : _phoneController.text],
      ['Goal', goalLabel!],
      ['Current weight', _weightController.text.isEmpty ? '—' : '${_weightController.text} kg'],
      ['Goal weight', _goalWeightController.text.isEmpty ? '—' : '${_goalWeightController.text} kg'],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          background: AppColors.green50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Review your details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 10),
              ...rows.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(r[0], style: const TextStyle(color: AppColors.muted)),
                        Flexible(child: Text(r[1], style: const TextStyle(fontWeight: FontWeight.w700), textAlign: TextAlign.end)),
                      ],
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          "Your coach will set your protein, carb, and fat targets once you're linked — until then, NutriFit starts you on a sensible default plan.",
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: _busy ? null : _back, child: const Text('Back'))),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _busy ? null : _finish,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Create Account 🌱'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
