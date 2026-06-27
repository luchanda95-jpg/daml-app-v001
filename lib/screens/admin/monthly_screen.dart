// lib/screens/branch/monthly_screen.dart
// ignore_for_file: deprecated_member_use

import 'dart:math' as math;
import 'package:daml/models/monthly_report_model.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:daml/screens/branch/monthly_report_detail_screen.dart';
import 'package:daml/services/api_service.dart';

class MonthlyScreen extends StatefulWidget {
  final int pendingCount;
  final VoidCallback showPendingActions;
  final List<MonthlyReport>? reports;

  const MonthlyScreen({
    super.key,
    required this.pendingCount,
    required this.showPendingActions,
    this.reports,
  });

  @override
  State<MonthlyScreen> createState() => _MonthlyScreenState();
}

class _MonthlyScreenState extends State<MonthlyScreen> {
  String _monthlyChartMode = 'bar';
  int _monthlyTopN = 5;
  final String _selectedMonthlyBranch = 'All';

  final NumberFormat _currency = NumberFormat.currency(symbol: 'ZMW ', decimalDigits: 2);
  bool _loading = false;
  String? _error;
  List<MonthlyReport> _fetchedReports = [];

  @override
  void initState() {
    super.initState();
    final provided = widget.reports;
    if (provided == null || provided.isEmpty) {
      _fetchMonthlyReports();
    } else {
      _fetchedReports = List<MonthlyReport>.from(provided);
    }
  }

  Future<void> _fetchMonthlyReports() async {
    setState(() { _loading = true; _error = null; });
    try {
      final raw = await ApiService.fetchAllMonthlyReports();
      final parsed = <MonthlyReport>[];
      for (final item in raw) {
        if (item is Map) {
          final branch = (item['branch'] ?? item['branchName'] ?? '').toString();
          DateTime date = DateTime.tryParse(item['date']?.toString() ?? '') ?? DateTime.now();
          final collected = _toDouble(item['collected'] ?? item['totalCollected'] ?? 0);
          parsed.add(MonthlyReport(
            branch: branch, date: date, collected: collected,
            year: null, month: null, totalCollected: null, totalDisbursed: null, totalExpenses: null,
          ));
        }
      }
      setState(() { _fetchedReports = parsed; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '')) ?? 0.0;
    return 0.0;
  }

  Color _accentFor(BuildContext c) => Theme.of(c).colorScheme.primary;

  @override
  Widget build(BuildContext context) {
    final reports = (widget.reports != null && widget.reports!.isNotEmpty) ? widget.reports! : _fetchedReports;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _errorState();
    if (reports.isEmpty) return _emptyState();

    final branchSummaries = _calcMonthlyBranches(reports);
    final sorted = branchSummaries.entries.toList()
      ..sort((a, b) => b.value.totalCollected.compareTo(a.value.totalCollected));

    final topEntries = sorted.take(_monthlyTopN).where((e) => e.key.isNotEmpty).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeader(),
        const SizedBox(height: 12),
        _buildControls(branchSummaries),
        const SizedBox(height: 20),
        _buildMainChart(topEntries),
        const SizedBox(height: 24),
        if (_selectedMonthlyBranch == 'All') _buildTopBranchesList(topEntries),
        const SizedBox(height: 16),
        _buildReportsList(reports),
      ],
    );
  }

  Widget _buildHeader() {
    return Text('Monthly Performance', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold));
  }

  Widget _buildControls(Map<String, MonthlyBranchSummary> branchSummaries) {
    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(label: const Text('Bar'), selected: _monthlyChartMode == 'bar', onSelected: (_) => setState(() => _monthlyChartMode = 'bar')),
        ChoiceChip(label: const Text('Pie'), selected: _monthlyChartMode == 'pie', onSelected: (_) => setState(() => _monthlyChartMode = 'pie')),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: _monthlyTopN,
          underline: const SizedBox(),
          items: [3, 5, 10].map((i) => DropdownMenuItem(value: i, child: Text('Top $i'))).toList(),
          onChanged: (v) => setState(() => _monthlyTopN = v ?? 5),
        ),
      ],
    );
  }

  Widget _buildMainChart(List<MapEntry<String, MonthlyBranchSummary>> entries) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: SizedBox(
          height: 300,
          child: _monthlyChartMode == 'bar' ? _buildBarChart(entries) : _buildPieChart(entries),
        ),
      ),
    );
  }

  Widget _buildBarChart(List<MapEntry<String, MonthlyBranchSummary>> entries) {
    final accent = _accentFor(context);
    final labels = entries.map((e) => e.key).toList();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: entries.isEmpty ? 10 : entries.map((e) => e.value.totalCollected).reduce(math.max) * 1.2,
        barGroups: List.generate(entries.length, (i) => BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: entries[i].value.totalCollected,
              color: accent,
              width: 14, // Slimmer bars
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              backDrawRodData: BackgroundBarChartRodData(show: true, toY: 0, color: accent.withOpacity(0.05)),
            )
          ],
        )),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, m) {
              int i = v.toInt();
              if (i < 0 || i >= labels.length) return const SizedBox();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(labels[i].length > 6 ? '${labels[i].substring(0, 5)}..' : labels[i], style: const TextStyle(fontSize: 10)),
              );
            },
          )),
          leftTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (v, m) => Text(v >= 1000 ? '${(v/1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0), style: const TextStyle(fontSize: 10)),
          )),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 1000, getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _buildPieChart(List<MapEntry<String, MonthlyBranchSummary>> entries) {
    final total = entries.fold<double>(0, (sum, e) => sum + e.value.totalCollected);
    return PieChart(PieChartData(
      sections: entries.map((e) => PieChartSectionData(
        value: e.value.totalCollected,
        title: '${((e.value.totalCollected/total)*100).toStringAsFixed(0)}%',
        color: _colorForLabel(e.key),
        radius: 50,
        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
      )).toList(),
      centerSpaceRadius: 40,
    ));
  }

  Widget _buildTopBranchesList(List<MapEntry<String, MonthlyBranchSummary>> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Breakdown", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        ...entries.map((e) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(backgroundColor: _colorForLabel(e.key), radius: 6),
          title: Text(e.key),
          trailing: Text(_currency.format(e.value.totalCollected), style: const TextStyle(fontWeight: FontWeight.w600)),
        )),
      ],
    );
  }

  Widget _buildReportsList(List<MonthlyReport> reports) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('All Reports', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: reports.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final rep = reports[index];
            return Card(
              child: ListTile(
                title: Text(rep.branch),
                subtitle: Text(DateFormat.yMMMM().format(rep.date)),
                trailing: Text(_currency.format(rep.collected ?? 0), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => MonthlyReportDetailScreen(report: rep, onDelete: (){}))),
              ),
            );
          },
        ),
      ],
    );
  }

  Map<String, MonthlyBranchSummary> _calcMonthlyBranches(List<MonthlyReport> reports) {
    final map = <String, MonthlyBranchSummary>{};
    for (var r in reports) {
      final s = map.putIfAbsent(r.branch, () => MonthlyBranchSummary());
      s.totalCollected += (r.collected ?? 0).toDouble();
      s.reports.add(r);
    }
    return map;
  }

  Widget _errorState() => Center(child: Text(_error ?? "Unknown Error"));
  Widget _emptyState() => const Center(child: Text("No data found"));

  Color _colorForLabel(String label) {
    final hash = label.codeUnits.fold(0, (a, b) => a + b);
    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.6, 0.6).toColor();
  }
}

class MonthlyBranchSummary {
  double totalCollected = 0;
  List<MonthlyReport> reports = [];
}