// lib/screens/branch/reports_screen.dart
// ignore_for_file: use_build_context_synchronously, unnecessary_null_comparison

import 'package:daml/screens/branch/report_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:daml/models/report_model.dart';

class ReportsScreen extends StatelessWidget {
  final int pendingCount;
  final VoidCallback showPendingActions;
  final Future<void> Function(DailyReport) addPendingDeletion;
  final Future<void> Function(Map<String, String>) removePendingDeletion;
  final Future<void> Function() loadPendingCount;

  // Parent-provided handlers and data
  final Future<void> Function(DailyReport) onDelete;
  final List<DailyReport> reports;
  final bool loading;
  final String? error;
  final Future<void> Function() refreshReports;

  // ignore: use_super_parameters
  const ReportsScreen({
    Key? key,
    required this.pendingCount,
    required this.showPendingActions,
    required this.addPendingDeletion,
    required this.removePendingDeletion,
    required this.loadPendingCount,
    required this.onDelete,
    required this.reports,
    required this.loading,
    required this.error,
    required this.refreshReports,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && error!.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Failed to load reports', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: refreshReports,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ]),
        ),
      );
    }

    final displayReports = List<DailyReport>.from(reports)..sort((a, b) => b.date.compareTo(a.date));
    if (displayReports.isEmpty) return _emptyState(context);

    return RefreshIndicator(
      onRefresh: refreshReports,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: displayReports.length,
        itemBuilder: (context, i) {
          final rep = displayReports[i];
          return _buildReportCard(context, rep);
        },
      ),
    );
  }

  Widget _buildReportCard(BuildContext context, DailyReport rep) {
    final currency = NumberFormat.currency(symbol: 'K ', decimalDigits: 2);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.receipt_long, color: Colors.blueAccent),
        title: Text(rep.branch, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(DateFormat.yMMMd().format(rep.date)),
        trailing: Text(currency.format(rep.totalCollected ?? 0),
            style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReportDetailScreen(report: rep),
            ),
          );
        },
        onLongPress: () => _handleReportLongPress(context, rep),
      ),
    );
  }

  Future<void> _handleReportLongPress(BuildContext context, DailyReport rep) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete report?'),
        content: Text('Delete report for ${rep.branch} on ${DateFormat.yMMMd().format(rep.date)}? This will attempt to remove it from the server.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await onDelete(rep);
    } catch (e) {
      // fallback: queue locally and remove local copy (parent-provided)
      try {
        await addPendingDeletion(rep);
        if (mountedContext(context)) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offline: deletion queued'))); 
        }
      } catch (_) {
        if (mountedContext(context)) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
        }
      }
    } finally {
      await loadPendingCount();
    }
  }

  bool mountedContext(BuildContext context) {
    return context != null;
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.assessment, size: 64, color: Colors.grey[500]),
        const SizedBox(height: 16),
        Text('No reports available', style: TextStyle(color: Colors.grey[400], fontSize: 18)),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Reload'),
          onPressed: refreshReports,
        ),
      ]),
    );
  }
}
