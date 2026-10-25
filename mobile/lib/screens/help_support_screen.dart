import 'package:flutter/material.dart';

import '../theme.dart';

const _faqs = [
  [
    'How are my recipes scaled?',
    'Your coach sets a daily calorie target. NutriFit divides it by the recipe\'s reference calories to get a scaling factor, then multiplies every ingredient by that factor so the meal matches your plan.',
  ],
  [
    'How do I pass the daily mission?',
    'Log your meals, take a live camera photo of each one from the Daily Mission screen, and keep your calories (70–115% of target) and protein (at least 75%) on track.',
  ],
  [
    'Why can\'t I choose a photo from my gallery?',
    'Mission photos must be taken at the moment you eat. The app only opens the camera, so photos from your gallery are not accepted.',
  ],
  [
    'I did not get a notification.',
    'Check Notification Prefs in your profile and make sure notifications are allowed for this app or site in your device or browser settings.',
  ],
  [
    'How do I contact my coach?',
    'Use Chat with Coach on the Home screen, or open Coach Info from your profile.',
  ],
];

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text('Help & Support', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ..._faqs.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  background: Colors.white,
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      title: Text(f[0], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                      children: [Align(alignment: Alignment.centerLeft, child: Text(f[1], style: const TextStyle(color: AppColors.inkSoft, fontSize: 13.5)))],
                    ),
                  ),
                ),
              )),
          const SizedBox(height: 10),
          const Text('Still stuck? Message your coach from the Home screen.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ),
    );
  }
}
