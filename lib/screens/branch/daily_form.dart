// lib/screens/branch/daily_form.dart
// ignore_for_file: use_build_context_synchronously, avoid_print, curly_braces_in_flow_control, unused_field, unused_local_variable, unnecessary_type_check, deprecated_member_use

import 'package:daml/screens/branch/widgets/branch_summery.dart';
import 'package:daml/screens/branch/widgets/channel_card.dart';
import 'package:daml/screens/branch/widgets/collected_allocation_card.dart';
import 'package:daml/screens/branch/widgets/collected_allocation_mode.dart';
import 'package:daml/screens/branch/widgets/action_buttons.dart';
import 'package:daml/screens/branch/widgets/form_fields.dart';

import 'package:flutter/foundation.dart'; // ✅ for kDebugMode
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:daml/models/report_model.dart';
import 'package:daml/services/local_storage.dart';
import 'package:daml/services/api_service.dart';

class DailyFormScreen extends StatefulWidget {
  final String branchName;
  const DailyFormScreen({super.key, required this.branchName});

  @override
  State<DailyFormScreen> createState() => _DailyFormScreenState();
}

class _DailyFormScreenState extends State<DailyFormScreen> {
  final _formKey = GlobalKey<FormState>();

  static const List<String> channels = ['Airtel', 'MTN'];

  final Map<String, TextEditingController> _opening = {
    for (var c in channels) c: TextEditingController(text: '0.00')
  };
  final Map<String, TextEditingController> _closing = {
    for (var c in channels) c: TextEditingController(text: '0.00')
  };

  final Map<String, TextEditingController> _disbursedAlloc = {
    for (var c in channels) c: TextEditingController(text: '0.00')
  };

  final TextEditingController _disbursedCountCtrl = TextEditingController(text: '0');
  final TextEditingController _totalCollectedCtrl = TextEditingController(text: '0.00');
  final TextEditingController _collectedForOtherAmountCtrl = TextEditingController(text: '0.00');
  final TextEditingController _pettyCashCtrl = TextEditingController(text: '0.00');
  final TextEditingController _expensesCtrl = TextEditingController(text: '0.00');
  final TextEditingController _commentCtrl = TextEditingController();

  DateTime _today = DateTime.now();
  String? _collectedForBranchTarget;

  // ✅ add Kitwe + Mbala here so they show in dropdown
  static const List<String> _knownBranches = [
    'All',
    'Lumezi',
    'Nakonde',
    'Solwezi',
    'Monze',
    'Lusaka',
    'Mazabuka',
    'Mbala',   // ✅ added
    'Kitwe',   // ✅ added
    'DirectAccess'
  ];

  CollectedAllocationMode _collectedMode = CollectedAllocationMode.proportional;

  double _totalOpening = 0.0;
  double _totalClosing = 0.0;
  double _totalDisbursedAmount = 0.0;
  double _netMovement = 0.0;
  double _computedTotalClosing = 0.0;

  bool _isUpdatingControllers = false;

  // UI-only mask toggle for amounts (passed to BranchSummaryWidget)
  bool _maskAmounts = false;

  // Resolved email used for BranchSummaryWidget lookups
  String? _resolvedEmail;

  // Small deterministic mapping branchName -> canonical email used by server
  static const Map<String, String> _branchEmailMap = {
    'monze': 'monze@directaccess.com',
    'mazabuka': 'mazabuka@directaccess.com',
    'lusaka': 'lusaka@directaccess.com',
    'solwezi': 'solwezi@directaccess.com',
    'lumezi': 'lumezi@directaccess.com',
    'nakonde': 'nakonde@directaccess.com',
    'mbala': 'mbala@directaccess.com', // ✅ added
    'kitwe': 'kitwe@directaccess.com', // ✅ added
    'directaccess': 'admin@directaccess.com',
  };

  @override
  void initState() {
    super.initState();
    for (final c in _opening.values) {
      c.addListener(_recalculate);
    }
    for (final c in _closing.values) {
      c.addListener(_recalculate);
    }
    for (final c in _disbursedAlloc.values) {
      c.addListener(_recalculate);
    }

    _disbursedCountCtrl.addListener(_recalculate);
    _totalCollectedCtrl.addListener(_recalculate);
    _collectedForOtherAmountCtrl.addListener(_recalculate);
    _pettyCashCtrl.addListener(_recalculate);
    _expensesCtrl.addListener(_recalculate);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _resolveEmailFromBranch();

      for (final k in channels) {
        // default closing = opening initially
        _closing[k]!.text = _opening[k]!.text;
      }
      _recalculate();
      await _loadExistingForDate();
    });
  }

  @override
  void dispose() {
    for (final c in _opening.values) {
      c.dispose();
    }
    for (final c in _closing.values) {
      c.dispose();
    }
    for (final c in _disbursedAlloc.values) {
      c.dispose();
    }
    _disbursedCountCtrl.dispose();
    _totalCollectedCtrl.dispose();
    _collectedForOtherAmountCtrl.dispose();
    _pettyCashCtrl.dispose();
    _expensesCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  /// Resolve the email to use when asking BranchSummaryWidget / server for Zanaco allocations.
  Future<void> _resolveEmailFromBranch() async {
    try {
      final branchNorm = widget.branchName.toLowerCase().trim();
      if (_branchEmailMap.containsKey(branchNorm)) {
        setState(() => _resolvedEmail = _branchEmailMap[branchNorm]);
        return;
      }

      // Fallback: try session username (may be an email)
      try {
        final uname = await LocalStorage.getUsername();
        if (uname != null && uname.trim().isNotEmpty) {
          setState(() => _resolvedEmail = uname.trim());
          return;
        }
      } catch (_) {}

      setState(() => _resolvedEmail = '');
    } catch (e) {
      debugPrint('Failed to resolve email for branch ${widget.branchName}: $e');
      setState(() => _resolvedEmail = '');
    }
  }

  double _parse(String? s) {
    if (s == null) return 0.0;
    final cleaned = s.replaceAll(',', '').trim();
    return double.tryParse(cleaned) ?? 0.0;
  }

  int _parseInt(String? s) {
    if (s == null) return 0;
    return int.tryParse(s.trim()) ?? 0;
  }

  DateTime _normalizeToUtcMidnight(DateTime d) {
    final u = d.toUtc();
    return DateTime.utc(u.year, u.month, u.day);
  }

  dynamic _mapGetCaseInsensitive(Map? maybe, String key) {
    if (maybe == null) return null;
    if (maybe.containsKey(key)) return maybe[key];
    final keyNorm = key.toString().toLowerCase().trim();
    for (final e in maybe.entries) {
      try {
        if (e.key.toString().toLowerCase().trim() == keyNorm) return e.value;
      } catch (_) {}
    }
    return null;
  }

  void _recalculate() {
    if (_isUpdatingControllers) return;

    final totalOpen = channels.map((c) => _parse(_opening[c]!.text)).fold(0.0, (a, b) => a + b);
    final totalCloseReported = channels.map((c) => _parse(_closing[c]!.text)).fold(0.0, (a, b) => a + b);
    final totalDisbAlloc = channels.map((c) => _parse(_disbursedAlloc[c]!.text)).fold(0.0, (a, b) => a + b);
    final collected = _parse(_totalCollectedCtrl.text);
    final collectedForOther = _parse(_collectedForOtherAmountCtrl.text);
    final petty = _parse(_pettyCashCtrl.text);
    final expenses = _parse(_expensesCtrl.text);

    final netMovementGross = collected - collectedForOther;

    final closings = _computeClosingsAndTotal(
      writeToControllers: false,
      netMovement: netMovementGross,
      pettyCash: petty,
      expenses: expenses,
    );

    final computedTotalClosing = closings.values.fold(0.0, (a, b) => a + b);

    setState(() {
      _totalOpening = totalOpen;
      _totalClosing = totalCloseReported;
      _totalDisbursedAmount = totalDisbAlloc;
      _netMovement = netMovementGross;
      _computedTotalClosing = computedTotalClosing;
    });
  }

  Map<String, double> _computeClosingsAndTotal({
    bool writeToControllers = false,
    double? netMovement,
    double? pettyCash,
    double? expenses,
  }) {
    final openings = {for (var k in channels) k: _parse(_opening[k]!.text)};
    final disbursed = {for (var k in channels) k: _parse(_disbursedAlloc[k]!.text)};
    final totalOpen = openings.values.fold(0.0, (a, b) => a + b);

    final nm = netMovement ?? _netMovement;
    final exp = expenses ?? _parse(_expensesCtrl.text);
    final petty = pettyCash ?? _parse(_pettyCashCtrl.text);

    final totalMobileExpense = (petty + exp);
    final double airtelOpen = openings['Airtel'] ?? 0.0;
    final double mtnOpen = openings['MTN'] ?? 0.0;
    final double mobileOpenTotal = airtelOpen + mtnOpen;

    final Map<String, double> expenseShare = {for (var k in channels) k: 0.0};

    if (mobileOpenTotal > 0.0) {
      final airtelShare = (airtelOpen / mobileOpenTotal);
      final mtnShare = (mtnOpen / mobileOpenTotal);
      expenseShare['Airtel'] = double.parse((totalMobileExpense * airtelShare).toStringAsFixed(2));
      expenseShare['MTN'] = double.parse((totalMobileExpense * mtnShare).toStringAsFixed(2));
    } else {
      expenseShare['Airtel'] = 0.0;
      expenseShare['MTN'] = 0.0;
    }

    final closings = <String, double>{};

    if (totalOpen <= 0 || _collectedMode == CollectedAllocationMode.cashOnly) {
      for (final k in channels) {
        final open = openings[k] ?? 0.0;
        final alloc = disbursed[k] ?? 0.0;
        double close = open - alloc;
        if (k == 'Airtel') close += nm;
        close -= (expenseShare[k] ?? 0.0);
        close = close.clamp(0.0, double.infinity);
        closings[k] = double.parse(close.toStringAsFixed(2));
      }
    } else {
      for (final k in channels) {
        final open = openings[k] ?? 0.0;
        final alloc = disbursed[k] ?? 0.0;
        final ratio = totalOpen == 0 ? 0.0 : (open / totalOpen);
        double close = open - alloc + (nm * ratio);
        close -= (expenseShare[k] ?? 0.0);
        close = close.clamp(0.0, double.infinity);
        closings[k] = double.parse(close.toStringAsFixed(2));
      }
    }

    final total = closings.values.fold(0.0, (a, b) => a + b);

    if (writeToControllers) {
      _isUpdatingControllers = true;
      try {
        closings.forEach((k, v) {
          if (_closing.containsKey(k)) _closing[k]!.text = v.toStringAsFixed(2);
        });
      } finally {
        _isUpdatingControllers = false;
        _recalculate();
      }
      setState(() => _computedTotalClosing = total);
    }

    return closings;
  }

  void _applyAllocationsToClosings() {
    _isUpdatingControllers = true;
    try {
      for (final k in channels) {
        final open = _parse(_opening[k]!.text);
        final alloc = _parse(_disbursedAlloc[k]!.text);
        final newClose = (open - alloc).clamp(0.0, double.infinity);
        _closing[k]!.text = newClose.toStringAsFixed(2);
      }
      _computeClosingsAndTotal(writeToControllers: true);
    } finally {
      _isUpdatingControllers = false;
      _recalculate();
    }
  }

  /// Helper that uses ApiService.fetchReportForBranchDate and converts to model
  Future<DailyReport?> _fetchReportFromServer(DateTime date) async {
    try {
      final Map<String, dynamic>? json = await ApiService.fetchReportForBranchDate(widget.branchName, date);
      if (json == null) return null;
      return DailyReport.fromMap(json);
    } catch (e) {
      debugPrint('Failed to fetch/parse report from server: $e');
      return null;
    }
  }

  Future<void> _prefillFromPreviousDay() async {
    try {
      final normalizedToday = _normalizeToUtcMidnight(_today);
      final prevDay = normalizedToday.subtract(const Duration(days: 1));

      final DailyReport? found = await _fetchReportFromServer(prevDay);

      if (found != null) {
        _isUpdatingControllers = true;
        try {
          final clos = found.closingBalances ?? <String, double>{};
          for (final k in channels) {
            final raw = _mapGetCaseInsensitive(clos, k) ?? 0.0;
            double v;
            if (raw is num) {
              v = raw.toDouble();
            } else {
              v = double.tryParse(raw.toString()) ?? 0.0;
            }
            _opening[k]!.text = v.toStringAsFixed(2);
            _closing[k]!.text = v.toStringAsFixed(2);
          }
        } finally {
          _isUpdatingControllers = false;
          _recalculate();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No previous day report found on server'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
        );
      }
    } catch (e) {
      debugPrint('Prefill error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Prefill failed: $e')));
    }
  }

  Future<void> _loadExistingForDate() async {
    try {
      final normalizedDate = _normalizeToUtcMidnight(_today);

      final DailyReport? existing = await _fetchReportFromServer(normalizedDate);

      if (existing != null) {
        _isUpdatingControllers = true;
        try {
          final openings = existing.openingBalances ?? <String, double>{};
          final closings = existing.closingBalances ?? <String, double>{};

          for (final k in channels) {
            final oRaw = _mapGetCaseInsensitive(openings, k) ?? 0.0;
            final cRaw = _mapGetCaseInsensitive(closings, k) ?? 0.0;
            final o = (oRaw is num) ? oRaw.toDouble() : double.tryParse(oRaw.toString()) ?? 0.0;
            final c = (cRaw is num) ? cRaw.toDouble() : double.tryParse(cRaw.toString()) ?? 0.0;
            _opening[k]!.text = o.toStringAsFixed(2);
            _closing[k]!.text = c.toStringAsFixed(2);
          }

          _totalCollectedCtrl.text = (existing.totalCollected ?? 0.0).toStringAsFixed(2);
          _pettyCashCtrl.text = (existing.pettyCash ?? 0.0).toStringAsFixed(2);
          _expensesCtrl.text = (existing.expenses ?? 0.0).toStringAsFixed(2);
          _disbursedCountCtrl.text = (existing.totalLoans).toString();
          final totalDisb = existing.totalDisbursed ?? 0.0;
          if (totalDisb > 0) {
            _disbursedAlloc['Airtel']!.text = totalDisb.toStringAsFixed(2);
            for (final k in channels) {
              if (k != 'Airtel') _disbursedAlloc[k]!.text = '0.00';
            }
          }
          _collectedForOtherAmountCtrl.text = (existing.collectedForOtherBranches ?? 0.0).toStringAsFixed(2);
        } finally {
          _isUpdatingControllers = false;
          _recalculate();
        }
      } else {
        // No existing: try previous day prefill, then set closings=opening
        await _prefillFromPreviousDay();
        _isUpdatingControllers = true;
        try {
          for (final k in channels) {
            _closing[k]!.text = _opening[k]!.text;
          }
        } finally {
          _isUpdatingControllers = false;
          _recalculate();
        }
      }
    } catch (e) {
      debugPrint('Load existing error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Load report failed: $e')));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _today,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _today = picked);
    await _loadExistingForDate();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final collectedForOther = _parse(_collectedForOtherAmountCtrl.text);
    if (collectedForOther > 0 &&
        (_collectedForBranchTarget == null || _collectedForBranchTarget!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select target branch for collected-for-other'),
          backgroundColor: Theme.of(context).colorScheme.secondary,
        ),
      );
      return;
    }

    final expenses = _parse(_expensesCtrl.text);
    if (expenses > 0 && _commentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please add a comment explaining expenses'),
          backgroundColor: Theme.of(context).colorScheme.secondary,
        ),
      );
      return;
    }

    for (final k in channels) {
      final open = _parse(_opening[k]!.text);
      final alloc = _parse(_disbursedAlloc[k]!.text);
      if (alloc > open + 0.0001) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Disbursed allocation for $k exceeds its opening balance')),
        );
        return;
      }
    }

    final normalized = _normalizeToUtcMidnight(_today);

    final Map<String, double> openingBalancesOut = <String, double>{};
    for (final k in channels) {
      openingBalancesOut[k] = _parse(_opening[k]!.text);
    }

    final Map<String, double> closings = _computeClosingsAndTotal(writeToControllers: false);
    final Map<String, double> closingBalancesOut = <String, double>{};
    closings.forEach((k, v) => closingBalancesOut[k] = v);

    final loanCount = _parseInt(_disbursedCountCtrl.text);
    final Map<String, int> loanCountsMap = {'unknown': loanCount};

    final double totalDisbursedAmount =
        _disbursedAlloc.values.map((c) => _parse(c.text)).fold(0.0, (a, b) => a + b);
    final double totalCollected = _parse(_totalCollectedCtrl.text);
    final double petty = _parse(_pettyCashCtrl.text);
    final commentText = _commentCtrl.text.trim();

    final report = DailyReport(
      branch: widget.branchName,
      date: normalized,
      openingBalances: openingBalancesOut,
      closingBalances: closingBalancesOut,
      loanCounts: loanCountsMap,
      totalDisbursed: totalDisbursedAmount,
      totalCollected: totalCollected,
      collectedForOtherBranches: _parse(_collectedForOtherAmountCtrl.text),
      pettyCash: petty,
      expenses: _parse(_expensesCtrl.text),
      zanacoApplied: null,
      totalLoans: loanCount,
    );

    try {
      final payload = <String, dynamic>{
        'branch': report.branch,
        'date': DateTime.utc(normalized.year, normalized.month, normalized.day).toIso8601String(),
        'openingBalances': report.openingBalances ?? <String, double>{},
        'closingBalances': report.closingBalances ?? <String, double>{},
        'loanCounts': report.loanCounts ?? <String, int>{},
        'totalDisbursed': report.totalDisbursed ?? 0.0,
        'totalCollected': report.totalCollected ?? 0.0,
        'collectedForOtherBranches': report.collectedForOtherBranches ?? 0.0,
        'pettyCash': report.pettyCash ?? 0.0,
        'expenses': report.expenses ?? 0.0,
        'zanacoApplied': report.zanacoApplied ?? <String, bool>{},
        'totalLoans': report.totalLoans,
      };

      await ApiService.saveReportSingle(payload);

      if (commentText.isNotEmpty) {
        try {
          final author = await LocalStorage.getUsername() ?? 'user';
          await ApiService.saveBranchComment(widget.branchName, commentText, author);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Saved report but failed to save comment: $e'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }

      if (_parse(_collectedForOtherAmountCtrl.text) > 0 &&
          _collectedForBranchTarget != null &&
          _collectedForBranchTarget!.isNotEmpty) {
        try {
          final user = await LocalStorage.getUsername() ?? 'user';
          await ApiService.saveBranchComment(
            widget.branchName,
            '__collected_for__:${_collectedForBranchTarget!}',
            user,
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Saved report but failed to save collected-for comment: $e'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Report saved to server'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (serverErr) {
      debugPrint('Server save failed: $serverErr');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save report to server: $serverErr'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEE, MMM d, yyyy').format(_today);

    return Scaffold(
      appBar: AppBar(
        title: Text('Daily Report', style: Theme.of(context).textTheme.titleLarge),
        actions: [
          IconButton(icon: const Icon(Icons.calendar_today), onPressed: _pickDate),

          // ✅ Debug-only testing shortcut (hidden in production)
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Prefill openings from previous day (debug only)',
              onPressed: _prefillFromPreviousDay,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              Center(
                child: Text(
                  'DATE: $dateLabel',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16),
                ),
              ),
              const SizedBox(height: 8),

              BranchSummaryWidget(
                name: widget.branchName,
                email: _resolvedEmail ?? '',
                zanacoAllocation: 0.0,
                mtnAllocation: 0.0,
                airtelAllocation: 0.0,
                maskAmount: _maskAmounts,
                onToggleVisibility: () => setState(() => _maskAmounts = !_maskAmounts),
                dateForZanacoLookup: _today,
                includeTodayAllocations: true,
              ),

              const SizedBox(height: 12),

              Text(
                'OPENING / CLOSING (per channel)',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              for (final ch in channels)
                ChannelCard(
                  channel: ch,
                  openingController: _opening[ch]!,
                  closingController: _closing[ch]!,
                  disbursedController: _disbursedAlloc[ch]!,
                  onApplyAlloc: _applyAllocationsToClosings,
                ),

              const SizedBox(height: 6),

              Row(children: [
                Expanded(child: CountField(controller: _disbursedCountCtrl, label: 'Number of Loans Disbursed (count)')),
                const SizedBox(width: 12),
                Expanded(child: AmountField(controller: _totalCollectedCtrl, label: 'Total Amount Collected')),
              ]),

              const SizedBox(height: 12),

              LayoutBuilder(builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 520;
                if (isWide) {
                  return Row(children: [
                    Expanded(
                      child: AmountField(
                        controller: _collectedForOtherAmountCtrl,
                        label: 'Collected for Other Branches (amount)',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _collectedForBranchTarget,
                        items: _knownBranches
                            .where((b) => b != widget.branchName)
                            .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                            .toList(),
                        onChanged: (v) => setState(() => _collectedForBranchTarget = v),
                        decoration: const InputDecoration(labelText: 'Which branch?'),
                        validator: (v) {
                          final amt = _parse(_collectedForOtherAmountCtrl.text);
                          if (amt > 0 && (v == null || v.isEmpty)) return 'Select branch';
                          return null;
                        },
                      ),
                    ),
                  ]);
                } else {
                  return Column(children: [
                    AmountField(controller: _collectedForOtherAmountCtrl, label: 'Collected for Other Branches (amount)'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _collectedForBranchTarget,
                      items: _knownBranches
                          .where((b) => b != widget.branchName)
                          .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                          .toList(),
                      onChanged: (v) => setState(() => _collectedForBranchTarget = v),
                      decoration: const InputDecoration(labelText: 'Which branch?'),
                      validator: (v) {
                        final amt = _parse(_collectedForOtherAmountCtrl.text);
                        if (amt > 0 && (v == null || v.isEmpty)) return 'Select branch';
                        return null;
                      },
                    ),
                  ]);
                }
              }),

              const SizedBox(height: 12),

              Row(children: [
                Expanded(child: AmountField(controller: _pettyCashCtrl, label: 'Petty Cash @ Hand')),
                const SizedBox(width: 12),
                Expanded(child: AmountField(controller: _expensesCtrl, label: 'Expenses')),
              ]),

              const SizedBox(height: 12),

              CollectedAllocationCard(
                mode: _collectedMode,
                onModeChanged: (m) => setState(() => _collectedMode = m),
                computedTotalClosing: _computedTotalClosing,
                netMovement: _netMovement,
              ),

              const SizedBox(height: 12),

              ActionButtonsRow(
                onApplyComputedClosings: () {
                  _computeClosingsAndTotal(writeToControllers: true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Closings updated from computed totals'),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  );
                },
                onApplyAllocToClosings: _applyAllocationsToClosings,
                onRecompute: _recalculate,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _commentCtrl,
                decoration: const InputDecoration(labelText: 'Comment (required if expenses > 0)'),
                maxLines: 2,
                validator: (v) {
                  final exp = _parse(_expensesCtrl.text);
                  if (exp > 0 && (v == null || v.trim().isEmpty)) return 'Please explain expenses';
                  return null;
                },
              ),

              const SizedBox(height: 14),

              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('SAVE REPORT', style: TextStyle(fontSize: 16)),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
