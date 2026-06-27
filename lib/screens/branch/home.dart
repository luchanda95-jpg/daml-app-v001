// lib/screens/branch/home.dart
// Branch Admin Home screen — fetches daily & monthly reports + Zanaco received totals.

/// ignore_for_file: unnecessary_cast, unused_element, curly_braces_in_flow_control_structures,
/// deprecated_member_use, unrelated_type_equality_checks, unused_field

// ignore_for_file: unused_field, dangling_library_doc_comments, deprecated_member_use

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';

import 'package:daml/models/report_model.dart';
import 'package:daml/models/monthly_report_model.dart';

import 'package:daml/screens/branch/widgets/branch_summery.dart';
import 'package:daml/theme/app_colors.dart';

import 'package:daml/screens/client/widgets/home_widget.dart';
import 'package:daml/screens/client/widgets/settings_screen.dart';

import 'package:daml/screens/branch/report_detail_screen.dart';
import 'package:daml/screens/branch/monthly_report_detail_screen.dart';
import 'package:daml/screens/branch/daily_form.dart';
import 'package:daml/screens/branch/monthly_form.dart';
import 'package:daml/screens/branch/zanaco_distribution_screen.dart';

import 'package:daml/services/api_service.dart';
import 'package:daml/services/auth_service.dart';

enum ReportsViewMode { both, daily, monthly }

class BranchAdminHomeScreen extends StatefulWidget {
  final String branchName;

  // UI-only inputs (still supported as fallback)
  final List<DailyReport> dailyReports;
  final List<MonthlyReport> monthlyReports;
  final String? initialName;
  final String? initialEmail;
  final double? initialAmountBorrowed;
  final double? initialAmountPaid;
  final double? initialActualBalance;
  final double? zanacoTodayTotal;

  const BranchAdminHomeScreen({
    super.key,
    required this.branchName,
    this.dailyReports = const [],
    this.monthlyReports = const [],
    this.initialName,
    this.initialEmail,
    this.initialAmountBorrowed,
    this.initialAmountPaid,
    this.initialActualBalance,
    this.zanacoTodayTotal,
  });

  @override
  State<BranchAdminHomeScreen> createState() => _BranchAdminHomeScreenState();
}

class _BranchAdminHomeScreenState extends State<BranchAdminHomeScreen> {
  bool _loading = false;

  late String _name;
  late String _email;

  late double _amountBorrowed;
  late double _amountPaid;
  late double _actualBalance;

  bool _isBalanceHidden = true;

  bool _isSyncing = false;
  bool _dailyExpanded = true;
  bool _monthlyExpanded = true;
  ReportsViewMode _viewMode = ReportsViewMode.both;

  // ✅ Zanaco received totals (by channel)
  double _zanacoTodayTotal = 0.0;
  double _zanacoAirtelToday = 0.0;
  double _zanacoMtnToday = 0.0;

  late final ValueNotifier<List<DailyReport>> _dailyNotifier;
  late final ValueNotifier<List<MonthlyReport>> _monthlyNotifier;

  bool _loadedFromApi = false;

  // ✅ This is the canonical branch key we use for matching (monze, lusaka, etc.)
  String _branchKey = '';

  @override
  void initState() {
    super.initState();

    _name = widget.initialName ?? 'Guest User';
    _email = widget.initialEmail ?? 'you@example.com';

    _amountBorrowed = widget.initialAmountBorrowed ?? 0.0;
    _amountPaid = widget.initialAmountPaid ?? 0.0;
    _actualBalance = widget.initialActualBalance ?? 0.0;

    _zanacoTodayTotal = widget.zanacoTodayTotal ?? 0.0;

    _dailyNotifier = ValueNotifier<List<DailyReport>>(List<DailyReport>.from(widget.dailyReports));
    _monthlyNotifier = ValueNotifier<List<MonthlyReport>>(List<MonthlyReport>.from(widget.monthlyReports));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _resolveSignedInUser();
      await _fetchReportsFromApi();
    });
  }

  @override
  void dispose() {
    _dailyNotifier.dispose();
    _monthlyNotifier.dispose();
    super.dispose();
  }

  // -------------------- branch normalization --------------------
  // Converts "Monze Branch" -> "monze", "Lusaka" -> "lusaka"
  String _normBranch(String input) {
    final v = input.toLowerCase().trim();
    if (v.isEmpty) return '';
    final cleaned = v.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    if (cleaned.isEmpty) return '';
    return cleaned.split(' ').first.trim(); // take first token as branch key
  }

  // -------------------- safe list extractor --------------------
  List _extractList(dynamic raw, List<String> keys) {
    if (raw == null) return const [];
    if (raw is List) return raw;
    if (raw is Map) {
      for (final k in keys) {
        final v = raw[k];
        if (v is List) return v;
      }
    }
    return const [];
  }

  Future<void> _resolveSignedInUser() async {
    try {
      final profile = await AuthService.getLocalProfile();
      final token = await AuthService.getToken();

      final name = (profile['name'] ?? '').toString().trim();
      final email = (profile['email'] ?? '').toString().trim();

      // If you stored branch in profile, prefer it.
      final profBranch = (profile['branch'] ?? '').toString().trim();

      if (mounted) {
        setState(() {
          if (name.isNotEmpty) _name = name;
          if (email.isNotEmpty) _email = email;
        });
      }

      // ✅ Resolve branch key
      final fromProfile = _normBranch(profBranch);
      final fromWidget = _normBranch(widget.branchName);
      _branchKey = fromProfile.isNotEmpty ? fromProfile : fromWidget;

      if (token != null && token.isNotEmpty) {
        ApiService.setAuthToken(token);
      } else {
        ApiService.clearAuthToken();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to resolve signed-in user: $e');
      ApiService.clearAuthToken();
      _branchKey = _normBranch(widget.branchName);
    }
  }

  Future<void> _onRefresh() async {
    setState(() => _loading = true);
    try {
      await _fetchReportsFromApi();

      _name = widget.initialName ?? _name;
      _email = widget.initialEmail ?? _email;
      _amountBorrowed = widget.initialAmountBorrowed ?? _amountBorrowed;
      _amountPaid = widget.initialAmountPaid ?? _amountPaid;
      _actualBalance = widget.initialActualBalance ?? _actualBalance;
      _zanacoTodayTotal = widget.zanacoTodayTotal ?? _zanacoTodayTotal;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openSettings() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  void _toggleBalanceVisibility() => setState(() => _isBalanceHidden = !_isBalanceHidden);

  // -------------------- ZANACO (received) --------------------
  // Requires ApiService.fetchZanacoAggregate(...) shown below.
  Future<void> _fetchZanacoTodayReceived() async {
    try {
      if (_branchKey.isEmpty) return;

      final agg = await ApiService.fetchZanacoAggregate(
        branch: _branchKey,
        date: DateTime.now(),
      );

      final airtel = (agg['airtel'] ?? 0.0);
      final mtn = (agg['mtn'] ?? 0.0);

      // ✅ This includes "self allocations" too because branch == recipient branch.
      final total = agg.values.fold<double>(0.0, (s, v) => s + v);

      if (!mounted) return;
      setState(() {
        _zanacoAirtelToday = airtel;
        _zanacoMtnToday = mtn;
        _zanacoTodayTotal = total;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Zanaco aggregate fetch failed: $e');
      // keep old values
    }
  }

  // -------------------- API FETCH --------------------
  Future<void> _fetchReportsFromApi() async {
    if (_isSyncing) return;

    setState(() {
      _isSyncing = true;
      _loading = true;
    });

    try {
      // Ensure token
      try {
        final token = await AuthService.getToken();
        if (token != null && token.isNotEmpty) {
          ApiService.setAuthToken(token);
        } else {
          ApiService.clearAuthToken();
        }
      } catch (_) {
        ApiService.clearAuthToken();
      }

      final rawDailyRes = await ApiService.fetchAllReports();
      final rawMonthlyRes = await ApiService.fetchAllMonthlyReports();

      // ✅ accept list OR {reports:[...]} OR {data:[...]} etc.
      final rawDaily = _extractList(rawDailyRes, ['reports', 'data', 'items']);
      final rawMonthly = _extractList(rawMonthlyRes, ['reports', 'monthlyReports', 'data', 'items']);

      final allDaily = <DailyReport>[];
      final allMonthly = <MonthlyReport>[];

      for (final item in rawDaily) {
        try {
          if (item is Map) {
            allDaily.add(DailyReport.fromMap(Map<dynamic, dynamic>.from(item)));
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Daily parse error: $e');
        }
      }

      for (final item in rawMonthly) {
        try {
          if (item is Map) {
            allMonthly.add(MonthlyReport.fromJson(Map<dynamic, dynamic>.from(item)));
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Monthly parse error: $e');
        }
      }

      // ✅ Use canonical branch key for matching
      final branchNorm = _branchKey.isNotEmpty ? _branchKey : _normBranch(widget.branchName);

      final filteredDaily = allDaily.where((r) => _normBranch(r.branch) == branchNorm).toList();
      final filteredMonthly = allMonthly.where((r) => _normBranch(r.branch) == branchNorm).toList();

      filteredDaily.sort((a, b) => b.date.compareTo(a.date));
      filteredMonthly.sort((a, b) => b.date.compareTo(a.date));

      _dailyNotifier.value = List<DailyReport>.from(filteredDaily);
      _monthlyNotifier.value = List<MonthlyReport>.from(filteredMonthly);

      _loadedFromApi = true;

      // ✅ Fetch Zanaco received totals for today (includes self allocations)
      await _fetchZanacoTodayReceived();
    } catch (e) {
      if (kDebugMode) debugPrint('Failed fetching reports: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed loading reports: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _loading = false;
        });
      }
    }
  }

  Widget _sectionEmptyState(String message, {required VoidCallback onSyncTap}) {
    return Card(
      elevation: 0,
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Theme.of(context).disabledColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(0.85)),
              ),
            ),
            ElevatedButton.icon(
              onPressed: onSyncTap,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(90, 36),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyCard(DailyReport report) {
    final dateLabel = DateFormat('yyyy-MM-dd').format(report.date);
    final double totalOpening = (report.openingBalances?.values.fold(0.0, (sum, a) => sum! + a) ?? 0.0);
    final collected = report.totalCollected ?? 0.0;
    final statusColor = report.synced ? AppColors.SUCCESS : AppColors.WARNING;

    return _buildReportCard(
      accentColor: Theme.of(context).colorScheme.primary,
      title: dateLabel,
      subtitleLines: [
        'Opening: ${totalOpening.toStringAsFixed(2)}',
        'Loans: ${report.totalDisbursed?.toStringAsFixed(2) ?? '0.00'}',
        'Collected: ${collected.toStringAsFixed(2)}',
      ],
      tag: report.synced ? 'Synced' : 'Pending',
      tagColor: statusColor,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportDetailScreen(report: report))),
      onShare: () {},
    );
  }

  Widget _buildMonthlyCard(MonthlyReport report) {
    final monthLabel = DateFormat.yMMMM().format(report.date);
    final expected = report.expected ?? 0.0;
    final collected = report.collected ?? 0.0;
    final statusColor = report.synced ? AppColors.SUCCESS : AppColors.WARNING;

    return _buildReportCard(
      accentColor: AppColors.SECONDARY,
      title: monthLabel,
      subtitleLines: [
        'Expected: ZMW ${expected.toStringAsFixed(2)}',
        'Collected: ZMW ${collected.toStringAsFixed(2)}',
        'Uncollected: ZMW ${(report.uncollected ?? 0).toStringAsFixed(2)}',
      ],
      tag: report.synced ? 'Synced' : 'Pending',
      tagColor: statusColor,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MonthlyReportDetailScreen(
            report: report,
            onDelete: () {},
          ),
        ),
      ),
      onShare: () {},
    );
  }

  Widget _buildReportCard({
    required Color accentColor,
    required String title,
    required List<String> subtitleLines,
    required String tag,
    required Color tagColor,
    required VoidCallback onTap,
    required VoidCallback onShare,
  }) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 100,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), bottomLeft: Radius.circular(10)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: tagColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(color: tagColor, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...subtitleLines.map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          s,
                          style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.85)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.note_add, color: Theme.of(context).colorScheme.primary),
              title: const Text('New Daily Report'),
              subtitle: const Text('Create or update today\'s report'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openDailyForm();
              },
            ),
            ListTile(
              leading: Icon(Icons.calendar_view_month, color: Theme.of(context).colorScheme.primary),
              title: const Text('New Monthly Report'),
              subtitle: const Text('Create or update monthly summary'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openMonthlyForm();
              },
            ),
            ListTile(
              leading: Icon(Icons.account_balance, color: Theme.of(context).colorScheme.primary),
              title: const Text('New Zanaco Distribution'),
              subtitle: const Text('Record inter-branch Zanaco allocations'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openZanacoDistribution();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openMonthlyForm() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => MonthlyFormScreen(branchName: widget.branchName)),
    );
    await _onRefresh();
  }

  Future<void> _openDailyForm() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DailyFormScreen(branchName: widget.branchName)),
    );
    await _onRefresh();
  }

  Future<void> _openZanacoDistribution() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ZanacoDistributionScreen(fromBranch: widget.branchName)),
    );
    await _onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    final primary = cs.primary;

    return Scaffold(
      body: Column(
        children: [
          HomeWidget(
            title: 'Welcome, ${_name.split(' ').first}',
            onSettingsPressed: _openSettings, onProfilePressed: () {  },
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              color: primary,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  BranchSummaryWidget(
                    name: _name,
                    email: _email,
                    // ✅ Show received totals (includes “self send to self” because branch is recipient)
                    zanacoAllocation: _zanacoTodayTotal,
                    mtnAllocation: _zanacoMtnToday,
                    airtelAllocation: _zanacoAirtelToday,
                    maskAmount: _isBalanceHidden,
                    onToggleVisibility: _toggleBalanceVisibility,
                    dateForZanacoLookup: DateTime.now(),
                    includeTodayAllocations: true,
                    initialResolvedBranch: _branchKey.isNotEmpty ? _branchKey : widget.branchName.toLowerCase().trim(),
                  ),

                  const SizedBox(height: 16),

                  // Reports controls
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 520;

                        Widget radiosRow() {
                          Widget radioTile(ReportsViewMode value, String label) => Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Radio<ReportsViewMode>(
                                    value: value,
                                    groupValue: _viewMode,
                                    onChanged: (v) => setState(() => _viewMode = v ?? ReportsViewMode.both),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    activeColor: primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(label, style: TextStyle(color: onSurface)),
                                ],
                              );

                          return Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text('View:', style: TextStyle(fontWeight: FontWeight.w600, color: onSurface)),
                              radioTile(ReportsViewMode.both, 'Both'),
                              radioTile(ReportsViewMode.daily, 'Daily'),
                              radioTile(ReportsViewMode.monthly, 'Monthly'),
                            ],
                          );
                        }

                        final toggleButtons = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Collapse all',
                              onPressed: () => setState(() {
                                _dailyExpanded = false;
                                _monthlyExpanded = false;
                              }),
                              icon: Icon(Icons.unfold_less, color: onSurface),
                            ),
                            IconButton(
                              tooltip: 'Expand all',
                              onPressed: () => setState(() {
                                _dailyExpanded = true;
                                _monthlyExpanded = true;
                              }),
                              icon: Icon(Icons.unfold_more, color: onSurface),
                            ),
                          ],
                        );

                        if (isNarrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              radiosRow(),
                              const SizedBox(height: 8),
                              Align(alignment: Alignment.centerRight, child: toggleButtons),
                            ],
                          );
                        }
                        return Row(children: [Expanded(child: radiosRow()), toggleButtons]);
                      },
                    ),
                  ),

                  // DAILY REPORTS
                  if (_viewMode != ReportsViewMode.monthly) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Daily Reports', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: onSurface)),
                          IconButton(
                            tooltip: 'Collapse/Expand',
                            onPressed: () => setState(() => _dailyExpanded = !_dailyExpanded),
                            icon: Icon(_dailyExpanded ? Icons.expand_less : Icons.expand_more, color: onSurface),
                          ),
                        ],
                      ),
                    ),
                    ValueListenableBuilder<List<DailyReport>>(
                      valueListenable: _dailyNotifier,
                      builder: (context, reports, _) {
                        if (!_dailyExpanded) return const SizedBox.shrink();
                        if (reports.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
                            child: _sectionEmptyState('No daily reports yet', onSyncTap: _onRefresh),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Column(children: reports.map(_buildDailyCard).toList()),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // MONTHLY REPORTS
                  if (_viewMode != ReportsViewMode.daily) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Monthly Reports', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: onSurface)),
                          IconButton(
                            tooltip: 'Collapse/Expand',
                            onPressed: () => setState(() => _monthlyExpanded = !_monthlyExpanded),
                            icon: Icon(_monthlyExpanded ? Icons.expand_less : Icons.expand_more, color: onSurface),
                          ),
                        ],
                      ),
                    ),
                    ValueListenableBuilder<List<MonthlyReport>>(
                      valueListenable: _monthlyNotifier,
                      builder: (context, monthlyReports, _) {
                        if (!_monthlyExpanded) return const SizedBox.shrink();
                        if (monthlyReports.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
                            child: _sectionEmptyState('No monthly reports yet', onSyncTap: _onRefresh),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Column(children: monthlyReports.map(_buildMonthlyCard).toList()),
                        );
                      },
                    ),
                    const SizedBox(height: 40),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),

      floatingActionButton: SpeedDial(
        icon: Icons.menu,
        activeIcon: Icons.close,
        backgroundColor: primary,
        foregroundColor: cs.onPrimary,
        children: [
          SpeedDialChild(
            child: Icon(Icons.add, color: cs.onPrimary),
            backgroundColor: cs.secondaryContainer,
            label: 'Add Report',
            onTap: _showAddOptions,
          ),
        ],
      ),
    );
  }
}
