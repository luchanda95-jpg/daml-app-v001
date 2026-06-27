// lib/screens/branch/widgets/action_buttons.dart
import 'package:flutter/material.dart';

class ActionButtonsRow extends StatelessWidget {
  final VoidCallback onApplyComputedClosings;
  final VoidCallback onApplyAllocToClosings;
  final VoidCallback onRecompute;

  const ActionButtonsRow({
    super.key,
    required this.onApplyComputedClosings,
    required this.onApplyAllocToClosings,
    required this.onRecompute,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        ElevatedButton.icon(
          onPressed: onApplyComputedClosings,
          icon: const Icon(Icons.auto_fix_high),
          label: const Text('Apply computed closings'),
        ),
        ElevatedButton.icon(
          onPressed: onApplyAllocToClosings,
          icon: const Icon(Icons.subdirectory_arrow_right),
          label: const Text('Apply alloc → closings'),
        ),
        OutlinedButton.icon(
          onPressed: onRecompute,
          icon: const Icon(Icons.refresh),
          label: const Text('Recompute (no write)'),
        ),
      ],
    );
  }
}
