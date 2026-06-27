// lib/screens/branch/monthly_report_detail_screen.dart
// Monthly Report detail — REAL delete via server (/monthly_reports or /monthly_reports/:id)

// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daml/models/monthly_report_model.dart';
import 'package:daml/services/api_service.dart';

class MonthlyReportDetailScreen extends StatelessWidget {
  final MonthlyReport report;

  /// Caller can refresh list / remove item locally if needed.
  final VoidCallback onDelete;

  const MonthlyReportDetailScreen({
    super.key,
    required this.report,
    required this.onDelete,
  });

  Future<void> _deleteMonthly(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete monthly report?'),
        content: const Text('This will permanently delete the monthly report from the server. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true) return;

    // progress
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // ✅ Prefer delete-by-id if your model exposes it.
      // Many models use `id` or `_id`. Adjust the getter below to match your MonthlyReport model.
      final dynamic anyId = (report as dynamic).id ?? (report as dynamic)._id;

      if (anyId != null && anyId.toString().trim().isNotEmpty) {
        await ApiService.deleteMonthlyReportById(anyId.toString().trim());
      } else {
        // ✅ Fallback: delete by branch+date (your backend supports this)
        await ApiService.deleteMonthlyReportByBranchDate(
          branch: report.branch,
          monthDate: report.date,
        );
      }

      if (context.mounted) {
        Navigator.of(context).pop(); // close progress
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Monthly report deleted'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );

        onDelete();
        Navigator.of(context).pop(true); // tell caller it was deleted
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // close progress
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete monthly report: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Widget _buildDetailItem(
    BuildContext context,
    String title,
    String value, {
    bool isSubtotal = false,
    bool isTotal = false,
  }) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final textStyle = tt.bodyMedium?.copyWith(
      fontSize: 16,
      fontWeight: isTotal ? FontWeight.bold : isSubtotal ? FontWeight.w600 : FontWeight.normal,
      color: isTotal ? cs.primary : isSubtotal ? cs.secondary : cs.onSurface,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(title, style: textStyle)),
          const SizedBox(width: 12),
          Text(value, style: textStyle),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat.yMMMM().format(report.date);

    String updatedAtText = '-';
    try {
      updatedAtText = DateFormat.yMd().add_jm().format(report.updatedAt.toLocal());
    } catch (_) {}

    final cs = Theme.of(context).colorScheme;
    final headerStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: cs.primary,
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Report Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete monthly report',
            onPressed: () => _deleteMonthly(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDetailItem(context, 'Month', monthLabel),
          _buildDetailItem(context, 'Branch', report.branch),
          const SizedBox(height: 16),

          Text('SUMMARY', style: headerStyle),
          const SizedBox(height: 8),
          _buildDetailItem(context, 'Expected', 'ZMW ${(report.expected ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'Inputs', '${report.inputs ?? 0}'),
          _buildDetailItem(context, 'Collected (main)', 'ZMW ${(report.collected ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'Collected Input', '${report.collectedInput ?? 0}'),
          _buildDetailItem(context, 'Total Uncollected', 'ZMW ${(report.totalUncollected ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'Uncollected Inputs', '${report.uncollectedInput ?? 0}'),

          Divider(color: cs.onSurface.withOpacity(0.08), height: 30),

          Text('UNCOLLECTED BREAKDOWN', style: headerStyle),
          const SizedBox(height: 8),
          _buildDetailItem(context, 'Insufficient', 'ZMW ${(report.insufficient ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'Insufficient Input', '${report.insufficientInput ?? 0}'),
          _buildDetailItem(context, 'Unreported', 'ZMW ${(report.unreported ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'Unreported Input', '${report.unreportedInput ?? 0}'),
          _buildDetailItem(context, 'Late Collection', 'ZMW ${(report.lateCollection ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'Uncollected (Calc)', 'ZMW ${(report.uncollected ?? 0).toStringAsFixed(2)}'),

          Divider(color: cs.onSurface.withOpacity(0.08), height: 30),

          Text('NEXT MONTH PLANNING', style: headerStyle),
          const SizedBox(height: 8),
          _buildDetailItem(context, 'PERMIC Expected Next Month', 'ZMW ${(report.permicExpectedNextMonth ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'Total Inputs', '${report.totalInputs ?? 0}'),

          Divider(color: cs.onSurface.withOpacity(0.08), height: 30),

          Text('INPUTS BREAKDOWN', style: headerStyle),
          const SizedBox(height: 8),
          _buildDetailItem(context, 'Old Inputs Amount', 'ZMW ${(report.oldInputsAmount ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'Old Inputs Count', '${report.oldInputsCount ?? 0}'),
          _buildDetailItem(context, 'New Inputs Amount', 'ZMW ${(report.newInputsAmount ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'New Inputs Count', '${report.newInputsCount ?? 0}'),

          Divider(color: cs.onSurface.withOpacity(0.08), height: 30),

          Text('CASH FLOW', style: headerStyle),
          const SizedBox(height: 8),
          _buildDetailItem(context, 'Cash Advance', 'ZMW ${(report.cashAdvance ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'Overall Expected', 'ZMW ${(report.overallExpected ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'Actual Expected', 'ZMW ${(report.actualExpected ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'Collected (Principal)', 'ZMW ${(report.collected2 ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'Principal Reloaned', 'ZMW ${(report.principalReloaned ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'Default', 'ZMW ${(report.defaultAmount ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'Clearance', 'ZMW ${(report.clearance ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'Total Collections', 'ZMW ${(report.totalCollections ?? 0).toStringAsFixed(2)}'),
          _buildDetailItem(context, 'PERMIC Cash Advance', 'ZMW ${(report.permicCashAdvance ?? 0).toStringAsFixed(2)}'),

          Divider(color: cs.onSurface.withOpacity(0.08), height: 30),
          _buildDetailItem(context, 'Synced', report.synced ? 'Yes' : 'No', isTotal: true),
          _buildDetailItem(context, 'Last Updated', updatedAtText),
        ],
      ),
    );
  }
}
