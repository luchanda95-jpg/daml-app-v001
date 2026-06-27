// lib/screens/branch/widgets/collected_allocation_card.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'collected_allocation_mode.dart';

class CollectedAllocationCard extends StatelessWidget {
  final CollectedAllocationMode mode;
  final ValueChanged<CollectedAllocationMode> onModeChanged;
  final double computedTotalClosing;
  final double netMovement;

  const CollectedAllocationCard({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.computedTotalClosing,
    required this.netMovement,
  });

  @override
  Widget build(BuildContext context) {
    // ignore: duplicate_ignore
    // ignore: deprecated_member_use
    Color mutedFor(BuildContext c) => Theme.of(c).textTheme.bodySmall?.color?.withOpacity(0.75) ?? Colors.grey;

    return Card(
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Collected allocation', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          RadioListTile<CollectedAllocationMode>(
            dense: true,
            title: const Text('Proportional (split across channels by opening)'),
            value: CollectedAllocationMode.proportional,
            groupValue: mode,
            onChanged: (v) => onModeChanged(v ?? CollectedAllocationMode.proportional),
          ),
          RadioListTile<CollectedAllocationMode>(
            dense: true,
            title: const Text('Cash only (all collected -> Airtel)'),
            value: CollectedAllocationMode.cashOnly,
            groupValue: mode,
            onChanged: (v) => onModeChanged(v ?? CollectedAllocationMode.proportional),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Text('Computed total closing', overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium)),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140, minWidth: 70),
                child: Text(
                  'ZMW ${computedTotalClosing.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Text('Net movement', overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium)),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140, minWidth: 70),
                child: Text(
                  'ZMW ${netMovement.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: mutedFor(context)),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}
