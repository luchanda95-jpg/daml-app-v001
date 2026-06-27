// lib/screens/client/widgets/loan_calculator.dart
// ignore_for_file: deprecated_member_use

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class LoanCalculatorScreen extends StatelessWidget {
  const LoanCalculatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Loan Calculator'),
        centerTitle: true,
        backgroundColor: cs.surface,
        scrolledUnderElevation: 0,
      ),
      body: const SafeArea(
        child: LoanCalculator(),
      ),
    );
  }
}

class LoanCalculator extends StatefulWidget {
  const LoanCalculator({super.key});

  @override
  State<LoanCalculator> createState() => _LoanCalculatorState();
}

class _LoanCalculatorState extends State<LoanCalculator> {
  final _formKey = GlobalKey<FormState>();
  
  // Principal and Term are empty to show the "faded hint"
  final _principalCtrl = TextEditingController(); 
  final _termCtrl = TextEditingController();
  
  // Rate is fixed to '21'
  final _rateCtrl = TextEditingController(text: '21'); 

  double? _periodicPayment;
  double? _totalInterest;
  double? _totalPaid;
  List<_AmortRow> _schedule = [];

  final _fmt = NumberFormat.currency(symbol: '', decimalDigits: 2);

  @override
  void dispose() {
    _principalCtrl.dispose();
    _rateCtrl.dispose();
    _termCtrl.dispose();
    super.dispose();
  }

  // Helper to safely parse numbers
  double _parse(String s) {
    if (s.isEmpty) return 0.0;
    try {
      final cleaned = s.replaceAll(RegExp(r'[^\d.]'), '');
      return double.parse(cleaned);
    } catch (_) {
      return 0.0;
    }
  }

  void _calc() {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus(); 

    final principal = _parse(_principalCtrl.text);
    // Fixed rate logic: Always uses the text from the read-only controller (21)
    final monthlyRate = _parse(_rateCtrl.text) / 100.0; 
    final termMonths = int.tryParse(_termCtrl.text) ?? 0;

    if (principal <= 0 || termMonths <= 0) return;

    final r = monthlyRate;
    final n = termMonths;

    double payment;
    if (r == 0) {
      payment = principal / n;
    } else {
      final denom = 1 - pow(1 + r, -n);
      payment = principal * r / denom;
    }

    final schedule = <_AmortRow>[];
    double remaining = principal;
    double totalInterestAcc = 0.0;
    double totalPaidAcc = 0.0;

    for (int i = 1; i <= n; i++) {
      final interestPaid = remaining * r;
      double principalPaid = payment - interestPaid;
      double thisPayment = payment;

      if (i == n) {
        principalPaid = remaining;
        thisPayment = principalPaid + interestPaid;
        remaining = 0.0;
      } else {
        remaining = (remaining - principalPaid).clamp(0.0, double.infinity);
      }

      totalInterestAcc += interestPaid;
      totalPaidAcc += thisPayment;

      schedule.add(_AmortRow(
        period: i,
        payment: thisPayment,
        principalPaid: principalPaid,
        interestPaid: interestPaid,
        balance: remaining,
      ));
    }

    setState(() {
      _periodicPayment = payment;
      _totalInterest = totalInterestAcc;
      _totalPaid = totalPaidAcc;
      _schedule = schedule;
    });
  }

  void _reset() {
    setState(() {
      _principalCtrl.clear();
      _termCtrl.clear();
      // We do NOT clear rate, it stays at 21
      _rateCtrl.text = '21'; 
      
      _periodicPayment = null;
      _totalInterest = null;
      _totalPaid = null;
      _schedule = [];
      _formKey.currentState?.reset();
    });
  }

  Widget _buildInputs(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    InputDecoration inputDec(String label, String hint, {String? prefix, String? suffix, bool isReadOnly = false}) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: cs.onSurfaceVariant.withOpacity(0.4)),
        prefixText: prefix,
        suffixText: suffix,
        prefixIcon: isReadOnly ? Icon(Icons.lock_outline, size: 16, color: cs.onSurfaceVariant) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outlineVariant)),
        filled: true,
        // Make the fixed field slightly darker/different to indicate it's fixed
        fillColor: isReadOnly ? cs.surfaceContainerHighest.withOpacity(0.3) : cs.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      );
    }

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Principal Input
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _principalCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: inputDec('Principal', '4500', prefix: 'ZMW '),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Fixed Rate Input
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _rateCtrl,
                      readOnly: true, // User cannot edit this
                      decoration: inputDec('Rate', '', suffix: '%', isReadOnly: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Term Input
              TextFormField(
                controller: _termCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: inputDec('Duration', '12', suffix: ' Months'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 24),
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _calc,
                      icon: const Icon(Icons.calculate),
                      label: const Text('Calculate Loan'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filledTonal(
                    onPressed: _reset,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Reset',
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(BuildContext context) {
    if (_periodicPayment == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final txt = theme.textTheme;

    return Card(
      elevation: 2,
      color: cs.primaryContainer, // Adapts to your theme
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              'ESTIMATED MONTHLY PAYMENT',
              style: txt.labelMedium?.copyWith(
                color: cs.onPrimaryContainer.withOpacity(0.8),
                letterSpacing: 1.2,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            // Hero Number
            RichText(
              text: TextSpan(
                style: txt.displaySmall?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w900,
                ),
                children: [
                  TextSpan(
                    text: 'ZMW ',
                    style: txt.titleLarge?.copyWith(
                      color: cs.onPrimaryContainer.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextSpan(text: _fmt.format(_periodicPayment)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Stats Row
            Row(
              children: [
                Expanded(
                  child: _themeStatTile(
                    context, 
                    'Total Interest', 
                    _totalInterest!, 
                    cs.tertiaryContainer, // Uses accent color
                    cs.onTertiaryContainer
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _themeStatTile(
                    context, 
                    'Total Payable', 
                    _totalPaid!, 
                    cs.secondaryContainer, 
                    cs.onSecondaryContainer
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _themeStatTile(BuildContext context, String label, double value, Color bgColor, Color fgColor) {
    final txt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label, 
            style: txt.bodySmall?.copyWith(color: fgColor.withOpacity(0.8)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'ZMW ${_fmt.format(value)}',
              style: txt.titleMedium?.copyWith(
                fontWeight: FontWeight.bold, 
                color: fgColor
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleList(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_schedule.isEmpty) return const SizedBox.shrink();

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              'Amortization Schedule',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                SizedBox(width: 30, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurfaceVariant))),
                Expanded(child: Text('Payment', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurfaceVariant))),
                Expanded(child: Text('Interest', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurfaceVariant))),
                Expanded(child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurfaceVariant))),
              ],
            ),
          ),
          // Scrollable List
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: _schedule.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: cs.outlineVariant.withOpacity(0.2)),
                itemBuilder: (ctx, idx) {
                  final row = _schedule[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 30, 
                          child: Text(
                            '${row.period}', 
                            style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold)
                          )
                        ),
                        Expanded(child: Text(_fmt.format(row.payment), textAlign: TextAlign.right)),
                        Expanded(child: Text(_fmt.format(row.interestPaid), textAlign: TextAlign.right, style: TextStyle(color: cs.error.withOpacity(0.8)))),
                        Expanded(child: Text(_fmt.format(row.balance), textAlign: TextAlign.right, style: TextStyle(color: cs.onSurfaceVariant))),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildInputs(context),
          const SizedBox(height: 16),
          _buildResultCard(context),
          const SizedBox(height: 16),
          _buildScheduleList(context),
        ],
      ),
    );
  }
}

class _AmortRow {
  final int period;
  final double payment;
  final double principalPaid;
  final double interestPaid;
  final double balance;

  _AmortRow({
    required this.period,
    required this.payment,
    required this.principalPaid,
    required this.interestPaid,
    required this.balance,
  });
}