import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'camera_capture_screen.dart';

/// Today's mission: photograph every meal with the camera and hit the macro targets.
class MissionScreen extends StatefulWidget {
  const MissionScreen({super.key});

  @override
  State<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends State<MissionScreen> {
  Map<String, dynamic>? _mission;
  String? _error;
  String? _uploadingMealId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    try {
      final data = await api.missionToday(auth.token!);
      if (mounted) setState(() { _mission = data; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _takePhoto(Map<String, dynamic> meal) async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    final messenger = ScaffoldMessenger.of(context);

    final shot = await Navigator.of(context).push<CapturedPhoto>(
      MaterialPageRoute(builder: (_) => CameraCaptureScreen(mealName: (meal['recipeName'] ?? 'Meal') as String)),
    );
    if (shot == null) return;

    setState(() => _uploadingMealId = meal['id'] as String);
    try {
      final res = await api.submitMealPhoto(auth.token!, meal['id'] as String, shot.bytes, shot.capturedAt);
      if (!mounted) return;
      setState(() => _mission = res['mission'] as Map<String, dynamic>);
      if (res['accepted'] == true) {
        messenger.showSnackBar(SnackBar(
          content: Text(_mission!['passed'] == true ? '🏆 Mission complete for today!' : '✅ Photo accepted'),
        ));
      } else {
        final reasons = (res['reasons'] as List).cast<String>();
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Photo not accepted'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: reasons.map((r) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $r'))).toList(),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _uploadingMealId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _mission;
    final passed = m?['passed'] == true;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text("Today's Mission", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.red600)),
            if (m == null && _error == null) const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator())),
            if (m != null) ...[
              AppCard(
                background: passed ? AppColors.green100 : AppColors.orange100,
                child: Row(children: [
                  Text(passed ? '🏆' : '🎯', style: const TextStyle(fontSize: 34)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(passed ? 'Mission passed' : 'Mission in progress',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                      const SizedBox(height: 2),
                      Text(
                        passed ? 'Great work. Your coach has been told.' : 'Meet all three goals below to pass today.',
                        style: const TextStyle(color: AppColors.inkSoft, fontSize: 13),
                      ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              ...(m['criteria'] as List).map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      background: Colors.white,
                      child: Row(children: [
                        Icon(c['met'] == true ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: c['met'] == true ? AppColors.green600 : AppColors.muted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c['label'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(c['detail'] as String, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                          ]),
                        ),
                      ]),
                    ),
                  )),
              const SizedBox(height: 10),
              const Text('Meals to photograph', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if ((m['meals'] as List).isEmpty)
                const Text('Log a meal from the Recipes tab first, then come back to photograph it.', style: TextStyle(color: AppColors.muted)),
              ...(m['meals'] as List).map((meal) {
                final has = meal['hasPhoto'] == true;
                final uploading = _uploadingMealId == meal['id'];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    background: Colors.white,
                    child: Row(children: [
                      Text((meal['recipeEmoji'] ?? '🍽️') as String, style: const TextStyle(fontSize: 26)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text((meal['recipeName'] ?? 'Meal') as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${meal['mealType'] ?? ''} · ${meal['calories']} kcal', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        ]),
                      ),
                      if (has)
                        const Icon(Icons.verified, color: AppColors.green600)
                      else if (uploading)
                        const Row(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 8),
                          Text('Checking…', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        ])
                      else
                        ElevatedButton.icon(
                          onPressed: () => _takePhoto(meal as Map<String, dynamic>),
                          icon: const Icon(Icons.photo_camera, size: 18),
                          label: const Text('Take photo'),
                        ),
                    ]),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
