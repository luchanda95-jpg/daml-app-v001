// lib/screens/branch/report_detail_screen.dart
// UI-only Report detail — removed LocalStorage side-effects.

// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daml/models/report_model.dart';

class ReportDetailScreen extends StatelessWidget {
  final DailyReport report;

  const ReportDetailScreen({super.key, required this.report});

  double get totalOpening =>
      (report.openingBalances ?? {}).values.fold(0.0, (a, b) => a + b);

  double get totalClosing =>
      (report.closingBalances ?? {}).values.fold(0.0, (a, b) => a + b);

  double get netMovement =>
      (report.totalCollected ?? 0) -
      (report.collectedForOtherBranches ?? 0) -
      (report.expenses ?? 0);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final titleStyle = tt.titleLarge?.copyWith(fontWeight: FontWeight.bold);
    final sectionTitleStyle = tt.titleMedium?.copyWith(fontWeight: FontWeight.bold);
    final normalStyle = tt.bodyMedium;
    tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7));

    return Scaffold(
      appBar: AppBar(
        title: Text('Report Details', style: titleStyle),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete report',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Delete report', style: sectionTitleStyle),
                  content: Text(
                    'This will remove the report from the UI (no local/server delete). Continue?',
                    style: normalStyle,
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text('Cancel', style: TextStyle(color: cs.onSurface.withOpacity(0.8)))),
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text('Delete', style: TextStyle(color: cs.error))),
                  ],
                ),
              );

              if (confirmed == true) {
                // UI-only: show a tiny progress then pop with success
                showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => const Center(child: CircularProgressIndicator()),
                );

                await Future.delayed(const Duration(milliseconds: 300));

                if (context.mounted) {
                  Navigator.of(context).pop(); // close progress
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Report removed (UI-only)', style: TextStyle(color: cs.onError)),
                      backgroundColor: cs.error,
                    ),
                  );
                  Navigator.of(context).pop(true);
                }
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDetailItem('Date', DateFormat.yMMMMd().format(report.date), context),
          _buildDetailItem('Branch', report.branch, context),
          const Divider(height: 30),

          // Opening
          ..._buildBalanceSection('Opening Balances', report.openingBalances, context),

          // Disbursed
          _buildDetailItem('Loans Disbursed (count)', '${report.totalLoans}', context),
          _buildDetailItem('Total Disbursed',
              'ZMW ${(report.totalDisbursed ?? 0).toStringAsFixed(2)}', context),
          const Divider(height: 30),

          // Collected & other
          _buildDetailItem('Total Collected',
              'ZMW ${(report.totalCollected ?? 0).toStringAsFixed(2)}', context),
          _buildDetailItem('Collected for Other Branches',
              'ZMW ${(report.collectedForOtherBranches ?? 0).toStringAsFixed(2)}', context),
          _buildDetailItem('Petty Cash @ Hand',
              'ZMW ${(report.pettyCash ?? 0).toStringAsFixed(2)}', context),
          _buildDetailItem('Expenses',
              'ZMW ${(report.expenses ?? 0).toStringAsFixed(2)}', context),
          const Divider(height: 30),

          // Computed summary
          Text('Summary', style: sectionTitleStyle),
          const SizedBox(height: 8),
          _buildDetailItem('Total Opening Balance',
              'ZMW ${totalOpening.toStringAsFixed(2)}', context,
              isTotal: true),
          _buildDetailItem('Computed Total Closing',
              'ZMW ${totalClosing.toStringAsFixed(2)}', context,
              isTotal: true),
          _buildDetailItem('Net Movement', 'ZMW ${netMovement.toStringAsFixed(2)}', context,
              isTotal: true),
          const Divider(height: 30),

          // Closing
          ..._buildBalanceSection('Closing Balances', report.closingBalances, context),
        ],
      ),
    );
  }

  List<Widget> _buildBalanceSection(
      String title, Map<String, double>? balances, BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final nonNullBalances = balances ?? {};

    if (nonNullBalances.isEmpty) {
      return [
        Text(title,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
        const SizedBox(height: 10),
        Text('No data available', style: tt.bodyMedium),
        const Divider(height: 30),
      ];
    }

    final total =
        nonNullBalances.values.fold(0.0, (sum, amt) => sum + (amt));

    return [
      Text(title,
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
      const SizedBox(height: 10),
      ...nonNullBalances.entries
          .map((e) => _buildDetailItem(e.key, 'ZMW ${e.value.toStringAsFixed(2)}', context))
          ,
      const SizedBox(height: 10),
      _buildDetailItem('Total $title', 'ZMW ${total.toStringAsFixed(2)}', context,
          isSubtotal: true),
      const Divider(height: 30),
    ];
  }

  Widget _buildDetailItem(String title, String value, BuildContext context,
      {bool isSubtotal = false, bool isTotal = false}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final titleTextStyle = tt.bodyMedium?.copyWith(
      fontSize: 15,
      fontWeight: isTotal
          ? FontWeight.bold
          : isSubtotal
              ? FontWeight.w600
              : FontWeight.normal,
      color: isTotal
          ? cs.secondary
          : isSubtotal
              ? cs.primary
              : cs.onSurface,
    );

    final valueTextStyle = tt.bodyMedium?.copyWith(
      fontSize: 15,
      fontWeight: isTotal
          ? FontWeight.bold
          : isSubtotal
              ? FontWeight.w600
              : FontWeight.normal,
      color: isTotal
          ? cs.secondary
          : isSubtotal
              ? cs.primary
              : cs.onSurface,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(title, style: titleTextStyle)),
          const SizedBox(width: 12),
          Text(value, style: valueTextStyle),
        ],
      ),
    );
  }
}
