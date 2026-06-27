// lib/screens/branch/overview_screen.dart
// ignore_for_file: unused_import, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:daml/models/report_model.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

class OverviewScreen extends StatelessWidget {
  final String username;
  final int pendingCount;
  final VoidCallback showPendingActions;
  final List<DailyReport> reports;
  final bool loading;
  final String? error;
  final Future<void> Function() refreshReports;

  const OverviewScreen({
    super.key,
    required this.username,
    required this.pendingCount,
    required this.showPendingActions,
    required this.reports,
    required this.loading,
    required this.error,
    required this.refreshReports,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

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

    final list = List<DailyReport>.from(reports)..sort((a, b) => b.date.compareTo(a.date));
    if (list.isEmpty) {
      return RefreshIndicator(
        onRefresh: refreshReports,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Center(child: Icon(Icons.assessment, size: 64, color: Colors.grey[500])),
            const SizedBox(height: 16),
            Center(child: Text('No reports available', style: TextStyle(color: Colors.grey[400], fontSize: 18))),
            const SizedBox(height: 8),
            Center(child: Text('Pull down to refresh', style: TextStyle(color: Colors.grey[600]))),
          ],
        ),
      );
    }

    final summary = _calcOverall(list);
    final last3Months = _lastNMonthStarts(3);
    final collectedSpark = _metricSeriesForMonths(list, last3Months, (r) => r.totalCollected ?? 0.0);
    final disbursedSpark = _metricSeriesForMonths(list, last3Months, (r) => r.totalDisbursed ?? 0.0);
    final loansSpark = _metricSeriesForMonthsInt(list, last3Months, (r) => r.totalLoans).map((e) => e.toDouble()).toList();
    final expensesSpark = _metricSeriesForMonths(list, last3Months, (r) => r.expenses ?? 0.0);
    final pettySpark = _metricSeriesForMonths(list, last3Months, (r) => r.pettyCash ?? 0.0);

    return RefreshIndicator(
      onRefresh: refreshReports,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(context),
          const SizedBox(height: 20),
          _buildKpiCards(context, summary, collectedSpark, disbursedSpark, loansSpark, expensesSpark, pettySpark),
          const SizedBox(height: 24),
          _buildTrendChart(context, list),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Welcome, $username 👋", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text("Here's your dashboard overview", style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          ],
        ),
        const Spacer(),
        _buildPendingIndicator(),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: "Refresh data",
          onPressed: refreshReports,
        ),
      ],
    );
  }

  Widget _buildPendingIndicator() {
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Pending deletions',
          onPressed: showPendingActions,
        ),
        if (pendingCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Center(
                child: Text('$pendingCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildKpiCards(BuildContext context, OverallSummary summary, List<double> collectedSpark, List<double> disbursedSpark,
      List<double> loansSpark, List<double> expensesSpark, List<double> pettySpark) {
    final currency = NumberFormat.currency(symbol: 'K ', decimalDigits: 2);

    return SizedBox(
      height: 140, // Slightly taller to give sparklines room
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _kpiCard(context, "Collected", currency.format(summary.totalCollected), Colors.greenAccent, collectedSpark),
          _kpiCard(context, "Disbursed", currency.format(summary.totalDisbursed), Colors.orangeAccent, disbursedSpark),
          _kpiCard(context, "Loans", summary.totalLoans.toString(), Colors.blueAccent, loansSpark),
          _kpiCard(context, "Expenses", currency.format(summary.totalExpenses), Colors.redAccent, expensesSpark),
          _kpiCard(context, "Petty Cash", currency.format(summary.totalPettyCash), Colors.purpleAccent, pettySpark),
        ],
      ),
    );
  }

  Widget _kpiCard(BuildContext context, String title, String value, Color color, List<double> sparkData) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[400], fontWeight: FontWeight.w500)),
          const Spacer(),
          SizedBox(height: 35, child: _buildSparkline(sparkData, color)), // Taller sparkline
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildSparkline(List<double> points, Color color) {
    if (points.isEmpty || points.every((d) => d == 0)) {
      return Center(child: Text('-', style: TextStyle(color: Colors.grey[600])));
    }

    final spots = points.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();
    final maxY = points.reduce((a, b) => a > b ? a : b);

    return LineChart(LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          barWidth: 1.8, // Thinner line for elegance
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: color.withOpacity(0.05)),
          color: color,
        ),
      ],
      titlesData: const FlTitlesData(show: false),
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      minY: 0,
      maxY: maxY == 0 ? 1 : maxY * 1.1,
    ));
  }

  Widget _buildTrendChart(BuildContext context, List<DailyReport> reports) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics_outlined, size: 20, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text("30-Day Collections Trend", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(height: 220, child: _lineChartExample(context, reports)),
          ],
        ),
      ),
    );
  }

  Widget _lineChartExample(BuildContext context, List<DailyReport> reports) {
    final last = reports.take(30).toList().reversed.toList();
    final spots = last.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), (e.value.totalCollected ?? 0).toDouble());
    }).toList();

    if (spots.isEmpty) return const Center(child: Text('No trend data'));

    return LineChart(LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: Colors.blueAccent,
          barWidth: 2.5,
          belowBarData: BarAreaData(show: true, color: Colors.blueAccent.withOpacity(0.1)),
          dotData: const FlDotData(show: false),
        ),
      ],
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      gridData: const FlGridData(show: false),
    ));
  }

  OverallSummary _calcOverall(List<DailyReport> r) {
    final o = OverallSummary();
    for (var rep in r) {
      o.totalCollected += rep.totalCollected ?? 0.0;
      o.totalDisbursed += rep.totalDisbursed ?? 0.0;
      o.totalExpenses += rep.expenses ?? 0.0;
      o.totalPettyCash += rep.pettyCash ?? 0.0;
      o.totalLoans += rep.totalLoans;
      o.reportCount++;
    }
    return o;
  }

  List<DateTime> _lastNMonthStarts(int n) {
    final now = DateTime.now();
    return List.generate(n, (i) {
      final dt = DateTime(now.year, now.month - (n - 1) + i);
      return DateTime(dt.year, dt.month, 1);
    });
  }

  List<double> _metricSeriesForMonths(List<DailyReport> reports, List<DateTime> months, double Function(DailyReport) extractor) {
    final Map<DateTime, double> map = {for (var m in months) m: 0.0};
    for (var r in reports) {
      final ms = DateTime(r.date.year, r.date.month, 1);
      if (!map.containsKey(ms)) continue;
      map[ms] = (map[ms] ?? 0) + extractor(r);
    }
    return months.map((m) => map[m] ?? 0.0).toList();
  }

  List<int> _metricSeriesForMonthsInt(List<DailyReport> reports, List<DateTime> months, int Function(DailyReport) extractor) {
    final Map<DateTime, int> map = {for (var m in months) m: 0};
    for (var r in reports) {
      final ms = DateTime(r.date.year, r.date.month, 1);
      if (!map.containsKey(ms)) continue;
      map[ms] = (map[ms] ?? 0) + extractor(r);
    }
    return months.map((m) => map[m] ?? 0).toList();
  }
}

class OverallSummary {
  double totalCollected = 0;
  double totalDisbursed = 0;
  double totalExpenses = 0;
  double totalPettyCash = 0;
  int totalLoans = 0;
  int reportCount = 0;
}