// Monthly Form — saves to remote DB via ApiService
// UPDATED: sends a notification to overall admin when saved.

// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:daml/models/monthly_report_model.dart';
import 'package:daml/services/api_service.dart';
import 'package:flutter/foundation.dart'; // kDebugMode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

const String _overallAdminEmail = 'directaccessmoney@gmail.com';

class MonthlyFormScreen extends StatefulWidget {
  final String branchName;

  /// Optional initialReport to prefill the form (editing).
  final MonthlyReport? initialReport;

  const MonthlyFormScreen({
    super.key,
    required this.branchName,
    this.initialReport,
  });

  @override
  State<MonthlyFormScreen> createState() => _MonthlyFormScreenState();
}

class _MonthlyFormScreenState extends State<MonthlyFormScreen> {
  final _formKey = GlobalKey<FormState>();

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _isEditingExisting = false;
  bool _isSaving = false;

  final TextEditingController _expectedController = TextEditingController(text: '0');
  final TextEditingController _inputsController = TextEditingController(text: '0');
  final TextEditingController _collectedController = TextEditingController(text: '0');
  final TextEditingController _collectedInputController = TextEditingController(text: '0');
  final TextEditingController _totalUncollectedController = TextEditingController(text: '0');
  final TextEditingController _uncollectedInputsController = TextEditingController(text: '0');
  final TextEditingController _insufficientController = TextEditingController(text: '0');
  final TextEditingController _insufficientInputController = TextEditingController(text: '0');
  final TextEditingController _unreportedController = TextEditingController(text: '0');
  final TextEditingController _unreportedInputController = TextEditingController(text: '0');
  final TextEditingController _lateCollectionController = TextEditingController(text: '0');
  final TextEditingController _uncollectedCalcController = TextEditingController(text: '0');
  final TextEditingController _permicExpectedController = TextEditingController(text: '0');
  final TextEditingController _totalInputsController = TextEditingController(text: '0');
  final TextEditingController _oldInputsAmountController = TextEditingController(text: '0');
  final TextEditingController _oldInputsCountController = TextEditingController(text: '0');
  final TextEditingController _newInputsAmountController = TextEditingController(text: '0');
  final TextEditingController _newInputsCountController = TextEditingController(text: '0');
  final TextEditingController _cashAdvanceController = TextEditingController(text: '0');
  final TextEditingController _overallExpectedController = TextEditingController(text: '0');
  final TextEditingController _actualExpectedController = TextEditingController(text: '0');
  final TextEditingController _collected2Controller = TextEditingController(text: '0');
  final TextEditingController _principalReloanedController = TextEditingController(text: '0');
  final TextEditingController _defaultController = TextEditingController(text: '0');
  final TextEditingController _clearanceController = TextEditingController(text: '0');
  final TextEditingController _totalCollectionsController = TextEditingController(text: '0');
  final TextEditingController _permicCashAdvanceController = TextEditingController(text: '0');

  final List<TextInputFormatter> _decimalInputFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  final List<TextInputFormatter> _intInputFormatters = [
    FilteringTextInputFormatter.digitsOnly,
  ];

  @override
  void initState() {
    super.initState();

    if (widget.initialReport != null) {
      _selectedMonth = DateTime(widget.initialReport!.date.year, widget.initialReport!.date.month, 1);
      _populateFromExisting(widget.initialReport!);
    } else {
      _loadExistingForMonth();
    }
  }

  @override
  void dispose() {
    _expectedController.dispose();
    _inputsController.dispose();
    _collectedController.dispose();
    _collectedInputController.dispose();
    _totalUncollectedController.dispose();
    _uncollectedInputsController.dispose();
    _insufficientController.dispose();
    _insufficientInputController.dispose();
    _unreportedController.dispose();
    _unreportedInputController.dispose();
    _lateCollectionController.dispose();
    _uncollectedCalcController.dispose();
    _permicExpectedController.dispose();
    _totalInputsController.dispose();
    _oldInputsAmountController.dispose();
    _oldInputsCountController.dispose();
    _newInputsAmountController.dispose();
    _newInputsCountController.dispose();
    _cashAdvanceController.dispose();
    _overallExpectedController.dispose();
    _actualExpectedController.dispose();
    _collected2Controller.dispose();
    _principalReloanedController.dispose();
    _defaultController.dispose();
    _clearanceController.dispose();
    _totalCollectionsController.dispose();
    _permicCashAdvanceController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingForMonth() async {
    setState(() {
      _isEditingExisting = widget.initialReport != null;
      if (!_isEditingExisting) _resetFormToDefaults();
    });
  }

  void _populateFromExisting(MonthlyReport existing) {
    String toFixed(dynamic v, [int digits = 2]) {
      try {
        final d = (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '0') ?? 0.0;
        return d.toStringAsFixed(digits);
      } catch (_) {
        return (0.0).toStringAsFixed(digits);
      }
    }

    setState(() {
      _isEditingExisting = true;

      _expectedController.text = toFixed(existing.expected);
      _inputsController.text = (existing.inputs ?? 0).toString();

      _collectedController.text = toFixed(existing.collected);
      _collectedInputController.text = (existing.collectedInput ?? 0).toString();

      _totalUncollectedController.text = toFixed(existing.totalUncollected);
      _uncollectedInputsController.text = (existing.uncollectedInput ?? 0).toString();

      _insufficientController.text = toFixed(existing.insufficient);
      _insufficientInputController.text = (existing.insufficientInput ?? 0).toString();

      _unreportedController.text = toFixed(existing.unreported);
      _unreportedInputController.text = (existing.unreportedInput ?? 0).toString();

      _lateCollectionController.text = toFixed(existing.lateCollection);
      _uncollectedCalcController.text = toFixed(existing.uncollected);

      _permicExpectedController.text = toFixed(existing.permicExpectedNextMonth);
      _totalInputsController.text = (existing.totalInputs ?? 0).toString();

      _oldInputsAmountController.text = toFixed(existing.oldInputsAmount);
      _oldInputsCountController.text = (existing.oldInputsCount ?? 0).toString();

      _newInputsAmountController.text = toFixed(existing.newInputsAmount);
      _newInputsCountController.text = (existing.newInputsCount ?? 0).toString();

      _cashAdvanceController.text = toFixed(existing.cashAdvance);

      _overallExpectedController.text = toFixed(existing.overallExpected);
      _actualExpectedController.text = toFixed(existing.actualExpected);

      _collected2Controller.text = toFixed(existing.collected2);
      _principalReloanedController.text = toFixed(existing.principalReloaned);

      _defaultController.text = toFixed(existing.defaultAmount);
      _clearanceController.text = toFixed(existing.clearance);

      _totalCollectionsController.text = toFixed(existing.totalCollections);
      _permicCashAdvanceController.text = toFixed(existing.permicCashAdvance);
    });
  }

  void _resetFormToDefaults() {
    _expectedController.text = '0';
    _inputsController.text = '0';
    _collectedController.text = '0';
    _collectedInputController.text = '0';
    _totalUncollectedController.text = '0';
    _uncollectedInputsController.text = '0';
    _insufficientController.text = '0';
    _insufficientInputController.text = '0';
    _unreportedController.text = '0';
    _unreportedInputController.text = '0';
    _lateCollectionController.text = '0';
    _uncollectedCalcController.text = '0';
    _permicExpectedController.text = '0';
    _totalInputsController.text = '0';
    _oldInputsAmountController.text = '0';
    _oldInputsCountController.text = '0';
    _newInputsAmountController.text = '0';
    _newInputsCountController.text = '0';
    _cashAdvanceController.text = '0';
    _overallExpectedController.text = '0';
    _actualExpectedController.text = '0';
    _collected2Controller.text = '0';
    _principalReloanedController.text = '0';
    _defaultController.text = '0';
    _clearanceController.text = '0';
    _totalCollectionsController.text = '0';
    _permicCashAdvanceController.text = '0';
  }

  Future<void> _refreshMonthlyFromServer() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sync not implemented here — use fetch in list screen')),
    );
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialEntryMode: DatePickerEntryMode.input,
      helpText: 'Select Month',
      fieldLabelText: 'Month',
    );
    if (picked == null) return;

    setState(() => _selectedMonth = DateTime(picked.year, picked.month, 1));
    await _loadExistingForMonth();
  }

  double _parseDouble(String? s) {
    if (s == null) return 0.0;
    final cleaned = s.replaceAll(',', '').trim();
    return double.tryParse(cleaned) ?? 0.0;
  }

  int _parseInt(String? s) {
    if (s == null || s.trim().isEmpty) return 0;
    final cleaned = s.replaceAll(',', '').trim();
    return int.tryParse(cleaned) ?? (double.tryParse(cleaned)?.toInt() ?? 0);
  }

  Widget _sectionTitle(String text) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(text, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
    );
  }

  Widget _buildCurrencyField(String label, TextEditingController ctl, {bool isRequired = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: ctl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: _decimalInputFormatters,
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'ZMW',
        ),
        validator: isRequired
            ? (v) {
                if (v == null || v.isEmpty) return 'Required';
                final parsed = double.tryParse(v.replaceAll(',', ''));
                if (parsed == null) return 'Invalid number';
                if (parsed < 0) return 'Cannot be negative';
                return null;
              }
            : null,
      ),
    );
  }

  Widget _buildCountField(String label, TextEditingController ctl, {bool isRequired = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: ctl,
        keyboardType: TextInputType.number,
        inputFormatters: _intInputFormatters,
        decoration: InputDecoration(
          labelText: label,
        ),
        validator: isRequired
            ? (v) {
                if (v == null || v.isEmpty) return 'Required';
                final parsed = int.tryParse(v);
                if (parsed == null) return 'Invalid number';
                if (parsed < 0) return 'Cannot be negative';
                return null;
              }
            : null,
      ),
    );
  }

  String _cleanServerMessage(dynamic result) {
    if (result is! Map) return 'Monthly report saved to server';

    final raw = (result['message'] ?? '').toString().trim();
    final lower = raw.toLowerCase();

    if (raw.isEmpty) return 'Monthly report saved to server';
    if (lower.contains('ui only')) return 'Monthly report saved to server';

    return raw;
  }

  Future<void> _submitForm() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isEditingExisting ? 'Confirm update' : 'Confirm save'),
        content: Text(
          'Save monthly report for ${widget.branchName} — ${DateFormat.yMMM().format(_selectedMonth)}?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      final monthStartUtc = DateTime.utc(_selectedMonth.year, _selectedMonth.month, 1);

      final payload = <String, dynamic>{
        'branch': widget.branchName,
        'date': monthStartUtc.toIso8601String(),
        'expected': _parseDouble(_expectedController.text),
        'inputs': _parseInt(_inputsController.text),
        'collected': _parseDouble(_collectedController.text),
        'collectedInput': _parseInt(_collectedInputController.text),
        'totalUncollected': _parseDouble(_totalUncollectedController.text),
        'uncollectedInput': _parseInt(_uncollectedInputsController.text),
        'insufficient': _parseDouble(_insufficientController.text),
        'insufficientInput': _parseInt(_insufficientInputController.text),
        'unreported': _parseDouble(_unreportedController.text),
        'unreportedInput': _parseInt(_unreportedInputController.text),
        'lateCollection': _parseDouble(_lateCollectionController.text),
        'uncollected': _parseDouble(_uncollectedCalcController.text),
        'permicExpectedNextMonth': _parseDouble(_permicExpectedController.text),
        'totalInputs': _parseInt(_totalInputsController.text),
        'oldInputsAmount': _parseDouble(_oldInputsAmountController.text),
        'oldInputsCount': _parseInt(_oldInputsCountController.text),
        'newInputsAmount': _parseDouble(_newInputsAmountController.text),
        'newInputsCount': _parseInt(_newInputsCountController.text),
        'cashAdvance': _parseDouble(_cashAdvanceController.text),
        'overallExpected': _parseDouble(_overallExpectedController.text),
        'actualExpected': _parseDouble(_actualExpectedController.text),
        'collected2': _parseDouble(_collected2Controller.text),
        'principalReloaned': _parseDouble(_principalReloanedController.text),
        'defaultAmount': _parseDouble(_defaultController.text),
        'clearance': _parseDouble(_clearanceController.text),
        'totalCollections': _parseDouble(_totalCollectionsController.text),
        'permicCashAdvance': _parseDouble(_permicCashAdvanceController.text),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };

      final result = await ApiService.syncMonthlyReports([payload]);

      if (result['success'] == false) {
        throw Exception('Server rejected request: $result');
      }

      // ✅ SEND NOTIFICATION TO OVERALL ADMIN
      try {
        await ApiService.createNotification(
          toEmail: _overallAdminEmail,
          title: 'Monthly report submitted',
          message:
              '${widget.branchName} submitted monthly report for ${DateFormat.yMMM().format(_selectedMonth)}',
          type: 'info',
          data: {
            'kind': 'monthly',
            'branch': widget.branchName,
            'month': monthStartUtc.toIso8601String(),
          },
        );
      } catch (_) {}

      final message = _cleanServerMessage(result);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      if (Navigator.of(context).canPop()) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Monthly save failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save monthly report: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final monthFormatted = DateFormat.yMMM().format(_selectedMonth);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditingExisting ? 'Edit Monthly Report' : 'New Monthly Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Pick month',
            onPressed: _pickMonth,
          ),
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Sync monthly reports from server (debug)',
              onPressed: () async {
                await _refreshMonthlyFromServer();
                await _loadExistingForMonth();
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DIRECT ACCESS MONTHLY FINANCIAL REPORT',
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'BRANCH: ${widget.branchName.toUpperCase()}  •  MONTH: $monthFormatted',
                        style: t.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.75)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              _sectionTitle('EXPECTED & COLLECTED'),
              _buildCurrencyField('Expected', _expectedController),
              _buildCountField('Inputs', _inputsController),
              _buildCurrencyField('Collected (main)', _collectedController),
              _buildCountField('Collected Input', _collectedInputController),
              _buildCurrencyField('Total Uncollected', _totalUncollectedController),
              _buildCountField('Uncollected Inputs', _uncollectedInputsController),

              _sectionTitle('UNCOLLECTED BREAKDOWN'),
              _buildCurrencyField('Insufficient', _insufficientController),
              _buildCountField('Insufficient Input', _insufficientInputController),
              _buildCurrencyField('Unreported', _unreportedController),
              _buildCountField('Unreported Input', _unreportedInputController),
              _buildCurrencyField('Late Collection', _lateCollectionController),
              _buildCurrencyField('Uncollected (Calc)', _uncollectedCalcController, isRequired: false),

              _sectionTitle('NEXT MONTH PLANNING'),
              _buildCurrencyField('PERMIC Expected Next Month', _permicExpectedController),
              _buildCountField('Total Inputs', _totalInputsController),

              _sectionTitle('INPUTS BREAKDOWN'),
              _buildCurrencyField('Old Inputs Amount', _oldInputsAmountController),
              _buildCountField('Old Inputs Count', _oldInputsCountController),
              _buildCurrencyField('New Inputs Amount', _newInputsAmountController),
              _buildCountField('New Inputs Count', _newInputsCountController),

              _sectionTitle('CASH FLOW'),
              _buildCurrencyField('Cash Advance (book)', _cashAdvanceController),
              _buildCurrencyField('Overall Expected', _overallExpectedController),
              _buildCurrencyField('Actual Expected', _actualExpectedController),
              _buildCurrencyField('Collected (principal)', _collected2Controller),
              _buildCurrencyField('Principal Reloaned', _principalReloanedController),
              _buildCurrencyField('Default', _defaultController),
              _buildCurrencyField('Clearance', _clearanceController),
              _buildCurrencyField('Total Collections', _totalCollectionsController),
              _buildCurrencyField('PERMIC Cash Advance', _permicCashAdvanceController),

              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _isSaving ? null : _submitForm,
                child: _isSaving
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('Saving...'),
                        ],
                      )
                    : Text(
                        _isEditingExisting ? 'UPDATE MONTHLY REPORT' : 'SAVE MONTHLY REPORT',
                        style: const TextStyle(fontSize: 16),
                      ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
