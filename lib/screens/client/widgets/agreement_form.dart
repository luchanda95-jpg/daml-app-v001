// lib/screens/client/widgets/agreement_form.dart
// Updated: adds Save as PDF and Send PDF functionality
// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// PDF and file helpers
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

class ClientAgreementForm extends StatefulWidget {
  const ClientAgreementForm({super.key});

  @override
  State<ClientAgreementForm> createState() => _ClientAgreementFormState();
}

class _ClientAgreementFormState extends State<ClientAgreementForm> {
  final _formKey = GlobalKey<FormState>();

  // Consent & status
  bool? _crbConsent; // null = unanswered, true = yes, false = no
  String? _maritalStatus; // 'MARRIED' | 'SINGLE'
  String? _gender; // 'Male' | 'Female'

  // Client details
  final _nameCtrl = TextEditingController();
  final _nrcCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String? _residenceType; // 'OWNER' | 'TENANT'
  final _emailCtrl = TextEditingController();

  // Next of kin
  final _nok1NameCtrl = TextEditingController();
  final _nok1MobileCtrl = TextEditingController();
  final _nok1AddressCtrl = TextEditingController();

  final _nok2NameCtrl = TextEditingController();
  final _nok2MobileCtrl = TextEditingController();
  final _nok2AddressCtrl = TextEditingController();

  // Employment details
  final _employerNameCtrl = TextEditingController();
  final _employerAddressCtrl = TextEditingController();
  final _employeeNumberCtrl = TextEditingController();
  final _departmentCtrl = TextEditingController();
  final _supervisorNameCtrl = TextEditingController();
  final _supervisorMobileCtrl = TextEditingController();

  // Banking details
  final _bankNameCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _branchNameCtrl = TextEditingController();

  // NRC and Sort Code under Banking Details
  final _bankNrcCtrl = TextEditingController();
  final _sortCodeCtrl = TextEditingController();

  // Loan details
  final _loanAmountCtrl = TextEditingController();
  final _monthlyInstallmentCtrl = TextEditingController();
  DateTime? _loanStart;
  DateTime? _loanEnd;
  String _modeOfPayment = 'PERMIC DEDUCTION'; // or DDACC or CASH

  // Helpers
  final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');

  // UI state for PDF ops
  bool _generatingPdf = false;

  @override
  void dispose() {
    // dispose controllers
    _nameCtrl.dispose();
    _nrcCtrl.dispose();
    _mobileCtrl.dispose();
    _addressCtrl.dispose();
    _emailCtrl.dispose();

    _nok1NameCtrl.dispose();
    _nok1MobileCtrl.dispose();
    _nok1AddressCtrl.dispose();
    _nok2NameCtrl.dispose();
    _nok2MobileCtrl.dispose();
    _nok2AddressCtrl.dispose();

    _employerNameCtrl.dispose();
    _employerAddressCtrl.dispose();
    _employeeNumberCtrl.dispose();
    _departmentCtrl.dispose();
    _supervisorNameCtrl.dispose();
    _supervisorMobileCtrl.dispose();

    _bankNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _branchNameCtrl.dispose();

    // dispose NRC and sort code controllers
    _bankNrcCtrl.dispose();
    _sortCodeCtrl.dispose();

    _loanAmountCtrl.dispose();
    _monthlyInstallmentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(BuildContext ctx, bool isStart) async {
    final now = DateTime.now();
    final initial = isStart ? (_loanStart ?? now) : (_loanEnd ?? now.add(const Duration(days: 30)));
    final picked = await showDatePicker(
      context: ctx,
      initialDate: initial,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _loanStart = picked;
      } else {
        _loanEnd = picked;
      }
    });
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    setState(() {
      _crbConsent = null;
      _maritalStatus = null;
      _gender = null;
      _residenceType = null;
      _loanStart = null;
      _loanEnd = null;
      _modeOfPayment = 'PERMIC DEDUCTION';
    });

    // clear controllers
    for (final c in [
      _nameCtrl,
      _nrcCtrl,
      _mobileCtrl,
      _addressCtrl,
      _emailCtrl,
      _nok1NameCtrl,
      _nok1MobileCtrl,
      _nok1AddressCtrl,
      _nok2NameCtrl,
      _nok2MobileCtrl,
      _nok2AddressCtrl,
      _employerNameCtrl,
      _employerAddressCtrl,
      _employeeNumberCtrl,
      _departmentCtrl,
      _supervisorNameCtrl,
      _supervisorMobileCtrl,
      _bankNameCtrl,
      _accountNumberCtrl,
      _branchNameCtrl,
      // banking NRC and sort code
      _bankNrcCtrl,
      _sortCodeCtrl,
      _loanAmountCtrl,
      _monthlyInstallmentCtrl,
    ]) {
      c.clear();
    }
  }

  void _showPrettyConfirmation() {
    // Build the sections as widgets then show them in a scrollable dialog
    final clientLines = <String>[];
    if (_nameCtrl.text.trim().isNotEmpty) clientLines.add(_nameCtrl.text.trim());
    if (_gender != null) clientLines.add('Gender: $_gender');
    if (_nrcCtrl.text.trim().isNotEmpty) clientLines.add('NRC: ${_nrcCtrl.text.trim()}');
    if (_mobileCtrl.text.trim().isNotEmpty) clientLines.add('Mobile: ${_mobileCtrl.text.trim()}');
    if (_addressCtrl.text.trim().isNotEmpty) clientLines.add('Address: ${_addressCtrl.text.trim()}');
    if (_residenceType != null) clientLines.add('Residence: $_residenceType');
    if (_emailCtrl.text.trim().isNotEmpty) clientLines.add('Email: ${_emailCtrl.text.trim()}');

    final nok1Lines = <String>[];
    if (_nok1NameCtrl.text.trim().isNotEmpty) nok1Lines.add(_nok1NameCtrl.text.trim());
    if (_nok1MobileCtrl.text.trim().isNotEmpty) nok1Lines.add('Mobile: ${_nok1MobileCtrl.text.trim()}');
    if (_nok1AddressCtrl.text.trim().isNotEmpty) nok1Lines.add('Address: ${_nok1AddressCtrl.text.trim()}');

    final nok2Lines = <String>[];
    if (_nok2NameCtrl.text.trim().isNotEmpty) nok2Lines.add(_nok2NameCtrl.text.trim());
    if (_nok2MobileCtrl.text.trim().isNotEmpty) nok2Lines.add('Mobile: ${_nok2MobileCtrl.text.trim()}');
    if (_nok2AddressCtrl.text.trim().isNotEmpty) nok2Lines.add('Address: ${_nok2AddressCtrl.text.trim()}');

    final employmentLines = <String>[];
    if (_employerNameCtrl.text.trim().isNotEmpty) employmentLines.add(_employerNameCtrl.text.trim());
    if (_employerAddressCtrl.text.trim().isNotEmpty) employmentLines.add('Address: ${_employerAddressCtrl.text.trim()}');
    if (_employeeNumberCtrl.text.trim().isNotEmpty) employmentLines.add('Emp #: ${_employeeNumberCtrl.text.trim()}');
    if (_departmentCtrl.text.trim().isNotEmpty) employmentLines.add('Dept: ${_departmentCtrl.text.trim()}');
    if (_supervisorNameCtrl.text.trim().isNotEmpty) employmentLines.add('Supervisor: ${_supervisorNameCtrl.text.trim()}');
    if (_supervisorMobileCtrl.text.trim().isNotEmpty) employmentLines.add('Sup. Mobile: ${_supervisorMobileCtrl.text.trim()}');

    final bankingLines = <String>[];
    if (_bankNameCtrl.text.trim().isNotEmpty) bankingLines.add(_bankNameCtrl.text.trim());
    if (_accountNumberCtrl.text.trim().isNotEmpty) bankingLines.add('Account: ${_accountNumberCtrl.text.trim()}');
    if (_branchNameCtrl.text.trim().isNotEmpty) bankingLines.add('Branch: ${_branchNameCtrl.text.trim()}');
    // include NRC and Sort Code
    if (_bankNrcCtrl.text.trim().isNotEmpty) bankingLines.add('NRC: ${_bankNrcCtrl.text.trim()}');
    if (_sortCodeCtrl.text.trim().isNotEmpty) bankingLines.add('Sort Code: ${_sortCodeCtrl.text.trim()}');

    showDialog<void>(
      context: context,
      builder: (c) {
        return AlertDialog(
          title: const Text('Confirm submission'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Client', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (clientLines.isEmpty)
                    const Text('—')
                  else
                    ...clientLines.map((l) => Padding(padding: const EdgeInsets.only(bottom:4), child: Text(l))),

                  const Divider(),

                  const Text('Next of Kin', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (nok1Lines.isEmpty) const Text('—') else ...nok1Lines.map((l) => Padding(padding: const EdgeInsets.only(bottom:4), child: Text(l))),
                  if (nok2Lines.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...nok2Lines.map((l) => Padding(padding: const EdgeInsets.only(bottom:4), child: Text(l))),
                  ],

                  const Divider(),

                  const Text('Employment', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (employmentLines.isEmpty) const Text('—') else ...employmentLines.map((l) => Padding(padding: const EdgeInsets.only(bottom:4), child: Text(l))),

                  const Divider(),

                  const Text('Banking', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (bankingLines.isEmpty) const Text('—') else ...bankingLines.map((l) => Padding(padding: const EdgeInsets.only(bottom:4), child: Text(l))),

                  const Divider(),

                  const Text('Loan Details', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Amount: ${_loanAmountCtrl.text.trim().isEmpty ? '—' : _loanAmountCtrl.text.trim()}'),
                  const SizedBox(height: 4),
                  Text('Installment: ${_monthlyInstallmentCtrl.text.trim().isEmpty ? '—' : _monthlyInstallmentCtrl.text.trim()}'),
                  const SizedBox(height: 8),
                  Text('Period: ${_loanStart != null ? _dateFmt.format(_loanStart!) : '—'} — ${_loanEnd != null ? _dateFmt.format(_loanEnd!) : '—'}'),
                  const SizedBox(height: 4),
                  Text('Mode of payment: $_modeOfPayment'),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('CRB Consent: ${_crbConsent == null ? '—' : (_crbConsent! ? 'YES' : 'NO')}'),
                      const Spacer(),
                      Text('Marital Status: ${_maritalStatus ?? '—'}'),
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Text('Tap Edit to change any information or Confirm & Save to proceed.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Edit')),
            ElevatedButton(
              onPressed: () {
                Navigator.of(c).pop();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Form saved (demo, not persisted)')));
              },
              child: const Text('Confirm & Save'),
            ),
          ],
        );
      },
    );
  }

  void _onSave() {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fix errors in the form')));
      return;
    }

    if (_crbConsent == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please indicate CRB consent')));
      return;
    }
    if (_maritalStatus == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select marital status')));
      return;
    }
    if (_gender == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select gender')));
      return;
    }

    // If validation passes show the pretty dialog
    _showPrettyConfirmation();
  }

  // Collect current form values into a map for PDF generation
  Map<String, dynamic> _collectFormData() {
    return {
      'name': _nameCtrl.text.trim(),
      'gender': _gender,
      'nrc': _nrcCtrl.text.trim(),
      'mobile': _mobileCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'residenceType': _residenceType,
      'maritalStatus': _maritalStatus,
      'nok1Name': _nok1NameCtrl.text.trim(),
      'nok1Mobile': _nok1MobileCtrl.text.trim(),
      'nok1Address': _nok1AddressCtrl.text.trim(),
      'nok2Name': _nok2NameCtrl.text.trim(),
      'nok2Mobile': _nok2MobileCtrl.text.trim(),
      'nok2Address': _nok2AddressCtrl.text.trim(),
      'employerName': _employerNameCtrl.text.trim(),
      'employerAddress': _employerAddressCtrl.text.trim(),
      'employeeNumber': _employeeNumberCtrl.text.trim(),
      'department': _departmentCtrl.text.trim(),
      'supervisorName': _supervisorNameCtrl.text.trim(),
      'supervisorMobile': _supervisorMobileCtrl.text.trim(),
      'bankName': _bankNameCtrl.text.trim(),
      'branchName': _branchNameCtrl.text.trim(),
      'accountNumber': _accountNumberCtrl.text.trim(),
      'sortCode': _sortCodeCtrl.text.trim(),
      'bankNrc': _bankNrcCtrl.text.trim(),
      'loanAmount': _loanAmountCtrl.text.trim(),
      'monthlyInstallment': _monthlyInstallmentCtrl.text.trim(),
      'loanStart': _loanStart != null ? _dateFmt.format(_loanStart!) : null,
      'loanEnd': _loanEnd != null ? _dateFmt.format(_loanEnd!) : null,
      'modeOfPayment': _modeOfPayment,
      'crbConsent': _crbConsent == null ? null : (_crbConsent! ? 'YES' : 'NO'),
    };
  }

  // Generate and save PDF, show success snackbar with path
  Future<File?> _generateAndSavePdf() async {
    setState(() => _generatingPdf = true);
    try {
      final formData = _collectFormData();
      final file = await PDFGenerator.generateAgreementPDF(formData);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF saved: ${file.path}')));
      return file;
    } catch (e, st) {
      debugPrint('PDF error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to generate PDF')));
      return null;
    } finally {
      setState(() => _generatingPdf = false);
    }
  }

  // Generate and share the PDF using share_plus
  Future<void> _generateAndSharePdf() async {
    setState(() => _generatingPdf = true);
    try {
      final formData = _collectFormData();
      final file = await PDFGenerator.generateAgreementPDF(formData);
      if (mounted) {
        await Share.shareXFiles([XFile(file.path)], text: 'Client Agreement PDF');
      }
    } catch (e, st) {
      debugPrint('Share PDF error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to generate/share PDF')));
    } finally {
      setState(() => _generatingPdf = false);
    }
  }

  // New utility widget for section headings with improved styling
  Widget _formSection({required String title, required List<Widget> fields}) {
    // Build children with consistent spacing (no negative SizedBox)
    final children = <Widget>[
      const SizedBox(height: 16),
      Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary, // Use primary color for section titles
        ) ?? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      const Divider(),
      const SizedBox(height: 8),
    ];

    for (var i = 0; i < fields.length; i++) {
      children.add(fields[i]);
      if (i != fields.length - 1) {
        children.add(const SizedBox(height: 12));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  // Helper for consistent field styling (takes advantage of InputDecorationTheme via theme)
  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      // The rest is handled by theme: fillColor, border, etc.
    );
  }

  @override
  Widget build(BuildContext context) {
    // NOTE: Use InputDecoration(...) directly when creating InputDecorator or TextFormField.

    return Scaffold(
      appBar: AppBar(
        title: const Text('Client Agreement'),
        centerTitle: true,
        elevation: 1,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- CONSENT & STATUS SECTION (Top) ---

                // CRB Consent
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Flexible(
                      child: Text(
                        'CRB Consent:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('NO'),
                          selected: _crbConsent == false,
                          onSelected: (s) => setState(() => _crbConsent = false),
                        ),
                        ChoiceChip(
                          label: const Text('YES'),
                          selected: _crbConsent == true,
                          onSelected: (s) => setState(() => _crbConsent = true),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Marital status
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text('Marital Status: ', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('MARRIED'),
                          selected: _maritalStatus == 'MARRIED',
                          onSelected: (s) => setState(() => _maritalStatus = 'MARRIED'),
                        ),
                        ChoiceChip(
                          label: const Text('SINGLE'),
                          selected: _maritalStatus == 'SINGLE',
                          onSelected: (s) => setState(() => _maritalStatus = 'SINGLE'),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Text(
                    'Between Direct Access of Mazabuka and the borrower concluded at Direct Access offices on the following terms and conditions, including the schedules attached:',
                    style: TextStyle(fontStyle: FontStyle.italic)),
                const SizedBox(height: 16),

                // --- CLIENT'S DETAILS ---
                _formSection(
                  title: "CLIENT'S DETAILS",
                  fields: [
                    // Name and gender inline
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _nameCtrl,
                            decoration: _inputDecoration('Name'),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Enter name' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Use a column for better alignment of the 'Gender' label and radio buttons
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Gender', style: Theme.of(context).textTheme.bodySmall),
                              Row(
                                children: [
                                  Expanded(
                                    child: RadioListTile<String?>(
                                      title: const Text('Male'),
                                      value: 'Male',
                                      groupValue: _gender,
                                      onChanged: (v) => setState(() => _gender = v),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                  Expanded(
                                    child: RadioListTile<String?>(
                                      title: const Text('Female'),
                                      value: 'Female',
                                      groupValue: _gender,
                                      onChanged: (v) => setState(() => _gender = v),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // NRC & Mobile inline
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _nrcCtrl,
                            decoration: _inputDecoration('NRC No'),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Enter NRC No' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _mobileCtrl,
                            decoration: _inputDecoration('Mobile number +260'),
                            keyboardType: TextInputType.phone,
                            validator: (v) => v == null || v.trim().isEmpty ? 'Enter mobile number' : null,
                          ),
                        ),
                      ],
                    ),

                    // Address & Residence type inline
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _addressCtrl,
                            decoration: _inputDecoration('Physical address'),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Enter address' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _residenceType,
                            decoration: _inputDecoration('Residence type (OWNER/TENANT)'),
                            items: const [
                              DropdownMenuItem(value: 'OWNER', child: Text('OWNER')),
                              DropdownMenuItem(value: 'TENANT', child: Text('TENANT')),
                            ],
                            onChanged: (v) => setState(() => _residenceType = v),
                            validator: (v) => v == null || v.isEmpty ? 'Select residence type' : null,
                          ),
                        ),
                      ],
                    ),

                    // Email
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: _inputDecoration('Email Address'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ],
                ),

                // --- NEXT OF KIN ---
                _formSection(
                  title: 'NEXT OF KIN',
                  fields: [
                    // NOK 1
                    Text(
                      'Next of Kin 1 (Primary)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _nok1NameCtrl,
                            decoration: _inputDecoration('Name'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _nok1MobileCtrl,
                            decoration: _inputDecoration('Mobile number'),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ],
                    ),
                    TextFormField(
                      controller: _nok1AddressCtrl,
                      decoration: _inputDecoration('Home address'),
                    ),

                    // NOK 2
                    Text(
                      'Next of Kin 2 (Secondary)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _nok2NameCtrl,
                            decoration: _inputDecoration('Name'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _nok2MobileCtrl,
                            decoration: _inputDecoration('Mobile Number'),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ],
                    ),
                    TextFormField(
                      controller: _nok2AddressCtrl,
                      decoration: _inputDecoration('Home address'),
                    ),
                  ],
                ),

                // --- EMPLOYMENT DETAILS ---
                _formSection(
                  title: '1. EMPLOYMENT DETAILS',
                  fields: [
                    TextFormField(
                      controller: _employerNameCtrl,
                      decoration: _inputDecoration('Name of Employer'),
                    ),
                    TextFormField(
                      controller: _employerAddressCtrl,
                      decoration: _inputDecoration('Employer\'s address'),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _employeeNumberCtrl,
                            decoration: _inputDecoration('Employee number'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _departmentCtrl,
                            decoration: _inputDecoration('Department'),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _supervisorNameCtrl,
                            decoration: _inputDecoration('Supervisor\'s name'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _supervisorMobileCtrl,
                            decoration: _inputDecoration('Mobile number'),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // --- BANKING DETAILS ---
                _formSection(
                  title: '2. BANKING DETAILS',
                  fields: [
                    TextFormField(
                      controller: _bankNameCtrl,
                      decoration: _inputDecoration('The borrower\'s bank is'),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _accountNumberCtrl,
                            decoration: _inputDecoration('Account No'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _branchNameCtrl,
                            decoration: _inputDecoration('Branch name'),
                          ),
                        ),
                      ],
                    ),
                    // NRC and Sort Code fields under Banking Details
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _bankNrcCtrl,
                            decoration: _inputDecoration('NRC'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _sortCodeCtrl,
                            decoration: _inputDecoration('Sort Code'),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text('The borrower acknowledges that changing the banking details without notifying Direct Access in writing within 7 days will constitute fraud.',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                ),

                // --- LOAN DETAILS ---
                _formSection(
                  title: '3. DETAILS OF THE LOAN ADVANCED AND MODE OF PAYMENT',
                  fields: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _loanAmountCtrl,
                            decoration: _inputDecoration('Loan amount (ZMW)'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _monthlyInstallmentCtrl,
                            decoration: _inputDecoration('Monthly installment'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),

                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _pickDate(context, true),
                            child: InputDecorator(
                              decoration: const InputDecoration(labelText: 'Start (month)'),
                              child: Text(
                                _loanStart == null ? 'Select start date' : _dateFmt.format(_loanStart!),
                                style: Theme.of(context).textTheme.bodyMedium, // Match input text style
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () => _pickDate(context, false),
                            child: InputDecorator(
                              decoration: const InputDecoration(labelText: 'End (month)'),
                              child: Text(
                                _loanEnd == null ? 'Select end date' : _dateFmt.format(_loanEnd!),
                                style: Theme.of(context).textTheme.bodyMedium, // Match input text style
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    DropdownButtonFormField<String>(
                      value: _modeOfPayment,
                      decoration: _inputDecoration('Mode of payment'),
                      items: const [
                        DropdownMenuItem(value: 'PERMIC DEDUCTION', child: Text('PERMIC DEDUCTION')),
                        DropdownMenuItem(value: 'DDACC', child: Text('DDACC')),
                        DropdownMenuItem(value: 'CASH', child: Text('CASH')),
                      ],
                      onChanged: (v) => setState(() => _modeOfPayment = v ?? _modeOfPayment),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _onSave,
                        child: const Text('Save'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120, // fixed width to prevent overflow
                      child: OutlinedButton(
                        onPressed: _resetForm,
                        child: const Text('Reset'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // NEW: PDF actions
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _generatingPdf ? null : () async {
                          // Validate required fields before generating
                          if (!_formKey.currentState!.validate()) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fix errors in the form')));
                            return;
                          }
                          final file = await _generateAndSavePdf();
                          if (file != null) {
                            // Optionally open file or further action
                          }
                        },
                        icon: _generatingPdf ? const SizedBox(width:16, height:16, child: CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.picture_as_pdf),
                        label: Text(_generatingPdf ? 'Generating...' : 'Save as PDF'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _generatingPdf ? null : () async {
                          if (!_formKey.currentState!.validate()) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fix errors in the form')));
                            return;
                          }
                          await _generateAndSharePdf();
                        },
                        icon: const Icon(Icons.send),
                        label: const Text('Send PDF'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ------------------- PDF GENERATOR -------------------
/// Self-contained PDF generator based on your earlier example.
/// Uses path_provider to save file. Returns saved File.
class PDFGenerator {
  static Future<File> generateAgreementPDF(Map<String, dynamic> formData) async {
    final pdf = pw.Document();
    final dateFmt = DateFormat('yyyy-MM-dd');

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(
            base: pw.Font.helvetica(),
            bold: pw.Font.helveticaBold(),
          ),
        ),
        build: (context) => [
          // ---------- HEADER ----------
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('DIRECT ACCESS MONEY LENDING',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      )),
                  pw.Text('Client Loan Agreement',
                      style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
              // Optional logo placeholder
              pw.Container(
                width: 60,
                height: 60,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey),
                  shape: pw.BoxShape.circle,
                ),
                alignment: pw.Alignment.center,
                child: pw.Text('LOGO', style: const pw.TextStyle(fontSize: 10)),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),

          // ---------- AGREEMENT TITLE ----------
          pw.Center(
            child: pw.Text('LOAN AGREEMENT FORM',
                style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    decoration: pw.TextDecoration.underline)),
          ),
          pw.SizedBox(height: 10),
          pw.Text('Date: ${dateFmt.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 20),

          // ---------- CLIENT INFORMATION ----------
          _sectionTitle('CLIENT DETAILS'),
          _infoRow('Full Name', formData['name']),
          _infoRow('Gender', formData['gender']),
          _infoRow('NRC Number', formData['nrc']),
          _infoRow('Mobile Number', formData['mobile']),
          _infoRow('Email Address', formData['email']),
          _infoRow('Residential Address', formData['address']),
          _infoRow('Marital Status', formData['maritalStatus']),
          pw.SizedBox(height: 10),

          // ---------- NEXT OF KIN ----------
          _sectionTitle('NEXT OF KIN DETAILS'),
          _infoRow('Primary NOK', '${formData['nok1Name']} - ${formData['nok1Mobile']}'),
          _infoRow('Address', formData['nok1Address']),
          _infoRow('Secondary NOK', '${formData['nok2Name']} - ${formData['nok2Mobile']}'),
          _infoRow('Address', formData['nok2Address']),
          pw.SizedBox(height: 10),

          // ---------- EMPLOYMENT ----------
          _sectionTitle('EMPLOYMENT DETAILS'),
          _infoRow('Employer Name', formData['employerName']),
          _infoRow('Employer Address', formData['employerAddress']),
          _infoRow('Employee No.', formData['employeeNumber']),
          _infoRow('Department', formData['department']),
          _infoRow('Supervisor Name', formData['supervisorName']),
          _infoRow('Supervisor Contact', formData['supervisorMobile']),
          pw.SizedBox(height: 10),

          // ---------- BANKING ----------
          _sectionTitle('BANKING DETAILS'),
          _infoRow('Bank Name', formData['bankName']),
          _infoRow('Branch', formData['branchName']),
          _infoRow('Account Number', formData['accountNumber']),
          _infoRow('Sort Code', formData['sortCode']),
          pw.SizedBox(height: 10),

          // ---------- LOAN DETAILS ----------
          _sectionTitle('LOAN DETAILS'),
          _infoRow('Loan Amount', formData['loanAmount']),
          _infoRow('Monthly Installment', formData['monthlyInstallment']),
          _infoRow('Start Date', formData['loanStart']),
          _infoRow('End Date', formData['loanEnd']),
          _infoRow('Mode of Payment', formData['modeOfPayment']),
          _infoRow('CRB Consent', formData['crbConsent']),
          pw.SizedBox(height: 10),

          // ---------- AGREEMENT SUMMARY ----------
          _sectionTitle('AGREEMENT TERMS'),
          pw.Text(
              'By signing this agreement, the borrower acknowledges having read and understood the terms of the loan. '
              'The borrower agrees to repay the loan according to the agreed schedule and accepts that failure to do so '
              'may result in legal or financial action by Direct Access Money Lending.',
              style: const pw.TextStyle(fontSize: 10),
              textAlign: pw.TextAlign.justify),
          pw.SizedBox(height: 10),
          pw.Text(
              'This agreement shall be governed by and construed in accordance with the laws of the Republic of Zambia.',
              style: const pw.TextStyle(fontSize: 10),
              textAlign: pw.TextAlign.justify),
          pw.SizedBox(height: 25),

          // ---------- SIGNATURE AREA ----------
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signatureBlock('Borrower Signature'),
              _signatureBlock('Loan Officer Signature'),
            ],
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 20),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(color: PdfColors.grey, fontSize: 10),
          ),
        ),
      ),
    );

    // ---------- SAVE FILE ----------
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/DirectAccess_Agreement_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  // Helper widgets
  static pw.Widget _sectionTitle(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blue700,
        ),
      ),
    );
  }

  static pw.Widget _infoRow(String label, dynamic value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 150,
            child: pw.Text('$label:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          ),
          pw.Expanded(
            child: pw.Text(value?.toString() ?? '-', style: const pw.TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _signatureBlock(String title) {
    return pw.Column(
      children: [
        pw.Container(
          width: 200,
          height: 1,
          color: PdfColors.black,
        ),
        pw.SizedBox(height: 5),
        pw.Text(title, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 5),
        pw.Text('Date: ___________', style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }
}
