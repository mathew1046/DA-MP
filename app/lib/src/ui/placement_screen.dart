import 'package:flutter/material.dart';

import 'theme.dart';

class PlacementScreen extends StatelessWidget {
  const PlacementScreen({super.key, this.firstTime = false});

  final bool firstTime;

  static const _steps = [
    ('Put the phone in a waist pouch or belt clip', 'At the middle of your lower back, or at your side on the belt line.'),
    ('Keep it upright', 'Top of the phone pointing up, screen facing away from your body.'),
    ('Make sure it does not wobble', 'A loose phone adds movement that is not yours.'),
    ('Press Start, then walk normally', 'The phone will vibrate in a steady rhythm if it notices a freeze.'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Wearing your phone')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              'The app learned from a sensor worn at the lower back, so phone position matters.',
              style: theme.textTheme.bodyLarge?.copyWith(color: Palette.muted),
            ),
            const SizedBox(height: 24),
            for (final (index, step) in _steps.indexed) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Palette.accentSoft, shape: BoxShape.circle),
                    child: Text('${index + 1}', style: theme.textTheme.titleMedium?.copyWith(color: Palette.accent)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(step.$1, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(step.$2, style: theme.textTheme.bodyMedium?.copyWith(color: Palette.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            if (firstTime) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 72,
                child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('I am ready')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
