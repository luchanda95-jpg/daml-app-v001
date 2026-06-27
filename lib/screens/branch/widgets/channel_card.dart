// lib/screens/branch/widgets/channel_card.dart
import 'package:flutter/material.dart';
import 'form_fields.dart';

/// ChannelCard displays Opening, Closing and Disbursed amount fields for a channel.
/// This is a presentational widget: all controllers come from parent.
class ChannelCard extends StatelessWidget {
  final String channel;
  final TextEditingController openingController;
  final TextEditingController closingController;
  final TextEditingController disbursedController;
  final VoidCallback? onApplyAlloc;

  const ChannelCard({
    super.key,
    required this.channel,
    required this.openingController,
    required this.closingController,
    required this.disbursedController,
    this.onApplyAlloc,
  });

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    final muted = Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.75) ?? Colors.grey;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  channel,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text('Open: ${double.tryParse(openingController.text.replaceAll(',', ''))?.toStringAsFixed(2) ?? openingController.text}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted, fontSize: 12)),
              const SizedBox(width: 8),
              Text('Close: ${double.tryParse(closingController.text.replaceAll(',', ''))?.toStringAsFixed(2) ?? closingController.text}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: AmountField(controller: openingController, label: '$channel Opening')),
            const SizedBox(width: 12),
            Expanded(child: AmountField(controller: closingController, label: '$channel Closing')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: AmountField(
                controller: disbursedController,
                label: 'Disbursed (amount)',
                // keep validation minimal here; parent also validates before submit
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final cleaned = v.replaceAll(',', '').trim();
                  final val = double.tryParse(cleaned);
                  if (val == null) return 'Invalid number';
                  if (val < 0) return 'Cannot be negative';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: onApplyAlloc,
              child: const Text('Apply alloc -> Closings'),
            ),
          ]),
        ]),
      ),
    );
  }
}
