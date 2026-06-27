// lib/screens/branch/zanaco_distribution_screen.dart
// Zanaco Distribution — saves to remote DB via ApiService
// Updated:
// - Allows allocating to the sender's own account (self row shows as "My account")
// - This is what makes the sender also "receive" when it allocates to itself.

// ignore_for_file: unnecessary_type_check, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:daml/services/api_service.dart';

const String _overallAdminEmail = 'directaccessmoney@gmail.com';

class ZanacoDistributionScreen extends StatefulWidget {
  final String fromBranch; // e.g. "Monze"
  final Map<String, Map<String, double>>? initialAllocations;

  const ZanacoDistributionScreen({
    super.key,
    required this.fromBranch,
    this.initialAllocations,
  });

  @override
  State<ZanacoDistributionScreen> createState() => _ZanacoDistributionScreenState();
}

class _ZanacoDistributionScreenState extends State<ZanacoDistributionScreen> {
  DateTime _date = DateTime.now();

  static const List<String> _targets = [
    'Lumezi',
    'Nakonde',
    'Solwezi',
    'Monze',
    'Lusaka',
    'Mazabuka',
    'DirectAccess',
  ];

  static const List<String> _channels = ['Airtel', 'MTN'];

  final Map<String, Map<String, TextEditingController>> _ctrls = {};
  final Map<String, double> _branchTotals = {};
  double _overallTotal = 0.0;

  final _currencyFmt = NumberFormat.currency(symbol: 'ZMW ', decimalDigits: 2);

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    final fromNorm = widget.fromBranch.trim().toLowerCase();

    // Ensure fromBranch exists in list
    final targets = List<String>.from(_targets);
    final exists = targets.any((t) => t.trim().toLowerCase() == fromNorm);
    if (!exists) targets.insert(0, widget.fromBranch);

    for (final t in targets) {
      final map = <String, TextEditingController>{
        for (var ch in _channels) ch: TextEditingController(text: '0.00')
      };
      for (final ctrl in map.values) {
        ctrl.addListener(_recalculateTotals);
      }
      _ctrls[t] = map;
      _branchTotals[t] = 0.0;
    }

    // Load initial allocations if provided
    if (widget.initialAllocations != null) {
      widget.initialAllocations!.forEach((branchKey, chMap) {
        try {
          final localKey = _ctrls.keys.firstWhere(
            (k) => k.toLowerCase().trim() == branchKey.toLowerCase().trim(),
            orElse: () => '',
          );
          if (localKey.isEmpty) return;

          for (final ch in _channels) {
            final val = chMap[ch] ?? chMap[ch.toLowerCase()];
            if (val != null) _ctrls[localKey]?[ch]?.text = val.toStringAsFixed(2);
          }
        } catch (_) {}
      });
    }

    _recalculateTotals();
  }

  @override
  void dispose() {
    for (final m in _ctrls.values) {
      for (final c in m.values) {
        c.removeListener(_recalculateTotals);
        c.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _date = picked);
  }

  double _parse(String? s) {
    if (s == null) return 0.0;
    final cleaned = s.replaceAll(',', '').trim();
    return double.tryParse(cleaned) ?? 0.0;
  }

  void _recalculateTotals() {
    double overall = 0.0;
    final updated = <String, double>{};

    _ctrls.forEach((branch, chMap) {
      double sum = 0.0;
      for (final ch in _channels) {
        sum += _parse(chMap[ch]!.text);
      }
      updated[branch] = sum;
      overall += sum;
    });

    setState(() {
      _branchTotals
        ..clear()
        ..addAll(updated);
      _overallTotal = overall;
    });
  }

  Future<void> _resetAll() async {
    for (final m in _ctrls.values) {
      for (final c in m.values) {
        c.text = '0.00';
      }
    }
    _recalculateTotals();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final allocations = <String, Map<String, double>>{};

      _ctrls.forEach((branch, chMap) {
        final inner = <String, double>{};

        chMap.forEach((ch, ctrl) {
          final v = _parse(ctrl.text);
          if (v > 0) inner[ch.toLowerCase().trim()] = double.parse(v.toStringAsFixed(2));
        });

        if (inner.isNotEmpty) {
          allocations[branch.toLowerCase().trim()] = inner;
        }
      });

      if (allocations.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No allocations to save')));
        }
        setState(() => _isSaving = false);
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm save'),
          content: Text(
            'Save distribution for ${widget.fromBranch} on ${DateFormat.yMMMd().format(_date)}?\n'
            'Total: ${_currencyFmt.format(_overallTotal)}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
          ],
        ),
      );

      if (confirmed != true) {
        setState(() => _isSaving = false);
        return;
      }

      final result = await ApiService.saveZanacoBulk(
        date: _date,
        fromBranch: widget.fromBranch,
        allocations: allocations,
      );

      String message = 'Zanaco distribution saved';
      if (result is Map<String, dynamic>) {
        if (result.containsKey('message')) {
          message = result['message'].toString();
        } else if (result.containsKey('success') && result['success'] == false) {
          throw Exception('Server rejected request: ${result.toString()}');
        }
      }

      // notify overall admin (optional)
      try {
        await ApiService.createNotification(
          toEmail: _overallAdminEmail,
          title: 'Zanaco distribution saved',
          message: '${widget.fromBranch} saved Zanaco distribution for ${DateFormat.yMMMd().format(_date)}',
          type: 'success',
          data: {
            'kind': 'zanaco',
            'fromBranch': widget.fromBranch,
            'date': DateTime.utc(_date.year, _date.month, _date.day).toIso8601String(),
            'total': _overallTotal,
          },
        );
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        if (Navigator.of(context).canPop()) Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('Zanaco save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save Zanaco distribution: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildBranchRow(String branch) {
    final chMap = _ctrls[branch]!;
    final branchTotal = _branchTotals[branch] ?? 0.0;

    final isSelf = branch.trim().toLowerCase() == widget.fromBranch.trim().toLowerCase();
    final title = isSelf ? '$branch (My account)' : branch;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _currencyFmt.format(branchTotal),
                    style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
                  ),
                )
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _amountField(chMap['Airtel']!, 'Airtel')),
                const SizedBox(width: 12),
                Expanded(child: _amountField(chMap['MTN']!, 'MTN')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountField(TextEditingController ctrl, String label) {
    return TextFormField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]'))],
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'ZMW',
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      onFieldSubmitted: (_) => _recalculateTotals(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEE, MMM d, yyyy').format(_date);
    final hasAllocations = _overallTotal > 0.0001;

    return Scaffold(
      appBar: AppBar(
        title: Text('Zanaco — ${widget.fromBranch}'),
        actions: [
          IconButton(
            tooltip: 'Reset all',
            icon: const Icon(Icons.refresh_outlined),
            onPressed: _resetAll,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.04),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Date: $dateLabel', style: const TextStyle(fontSize: 14))),
                          TextButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.edit_calendar, size: 16),
                            label: const Text('Change'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Total allocated', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(
                          _currencyFmt.format(_overallTotal),
                          style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Enter amounts to distribute from ${widget.fromBranch} to branches (including your own account).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.9),
                    ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _ctrls.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (ctx, i) {
                  final branch = _ctrls.keys.elementAt(i);
                  return _buildBranchRow(branch);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: hasAllocations && !_isSaving ? _save : null,
                      icon: _isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save),
                      label: Text(hasAllocations ? (_isSaving ? 'Saving...' : 'Save distribution') : 'No allocations to save'),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
