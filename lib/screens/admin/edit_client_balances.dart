// lib/screens/admin/edit_client_balances.dart
// Admin screen for viewing/editing a client's balances, interest rate, and next payment.
// This UI-only version removes all local storage / direct network calls and instead
// exposes callbacks for the parent to implement persistence or fetching logic.

// ignore_for_file: use_build_context_synchronously, unnecessary_type_check, curly_braces_in_flow_structures

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class EditClientBalancesScreen extends StatefulWidget {
  final String? initialEmail;
  final Future<Map<String, dynamic>?> Function(String email)? onFetchBalances;
  final Future<void> Function(Map<String, dynamic> payload)? onSaveBalances;
  final Future<void> Function(String email)? onDeleteClient;
  final String? Function()? getCurrentUserEmail;
  final List<Map<String, String>>? clients;

  const EditClientBalancesScreen({
    super.key,
    this.initialEmail,
    this.onFetchBalances,
    this.onSaveBalances,
    this.onDeleteClient,
    this.getCurrentUserEmail,
    this.clients,
  });

  @override
  State<EditClientBalancesScreen> createState() => _EditClientBalancesScreenState();
}

class _EditClientBalancesScreenState extends State<EditClientBalancesScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers for each editable field
  final TextEditingController _emailCtl = TextEditingController();
  final TextEditingController _borrowedCtl = TextEditingController();
  final TextEditingController _paidCtl = TextEditingController();
  final TextEditingController _balanceCtl = TextEditingController();
  final TextEditingController _interestCtl = TextEditingController(); // NEW

  // NEW: next payment controllers
  final TextEditingController _nextPaymentAmountCtl = TextEditingController();
  final TextEditingController _nextPaymentDateCtl = TextEditingController();

  // Raw picked date (preferred to rely on this instead of reparsing the formatted string)
  DateTime? _pickedNextPaymentDate;

  bool _loading = false;
  bool _saving = false;

  // UI client list (optional)
  List<Map<String, String>> _clients = [];
  String? _selectedClientEmail;

  @override
  void initState() {
    super.initState();

    // initialize clients from constructor (if provided)
    if (widget.clients != null) {
      _clients = List<Map<String, String>>.from(widget.clients!);
    }

    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _emailCtl.text = widget.initialEmail!;
      _selectedClientEmail = widget.initialEmail!.toLowerCase().trim();
      // attempt to load balances if callback provided
      _loadBalancesFor(widget.initialEmail!);
    }
  }

  @override
  void dispose() {
    _emailCtl.dispose();
    _borrowedCtl.dispose();
    _paidCtl.dispose();
    _balanceCtl.dispose();
    _interestCtl.dispose();
    _nextPaymentAmountCtl.dispose();
    _nextPaymentDateCtl.dispose();
    super.dispose();
  }

  /// Load balances via the provided callback (if any).
  Future<void> _loadBalancesFor(String email) async {
    setState(() => _loading = true);
    try {
      if (widget.onFetchBalances == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No fetch handler provided. Implement onFetchBalances.')),
          );
        }
        return;
      }

      final balances = await widget.onFetchBalances!(email);

      if (balances == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No balances returned')));
        return;
      }

      final borrowed = (balances['amountBorrowed'] ?? balances['amount_borrowed'] ?? balances['borrowed'] ?? 0.0);
      final paid = (balances['amountPaid'] ?? balances['amount_paid'] ?? balances['paid'] ?? 0.0);
      final actual = (balances['actualBalance'] ?? balances['actual_balance'] ?? balances['balance'] ?? 0.0);
      final interest = (balances['interestRate'] ?? balances['interest_rate'] ?? 0.0);

      _borrowedCtl.text = _formatNumber(borrowed);
      _paidCtl.text = _formatNumber(paid);
      _balanceCtl.text = _formatNumber(actual);
      _interestCtl.text = (interest is num) ? interest.toString() : (interest?.toString() ?? '0');

      _emailCtl.text = email;
      _selectedClientEmail = email.toLowerCase().trim();

      // next payment handling
      String nextAmountText = '';
      String nextDateText = '';
      DateTime? parsedDate;

      final nextPayment = (balances['nextPayment'] ?? balances['next_payment']) as Map<String, dynamic>?;
      if (nextPayment != null) {
        final rawAmt = nextPayment['amount'];
        if (rawAmt != null) nextAmountText = (rawAmt is num) ? rawAmt.toString() : rawAmt.toString();
        final rawDate = nextPayment['date'];
        if (rawDate != null) {
          if (rawDate is String) {
            parsedDate = DateTime.tryParse(rawDate);
          // ignore: curly_braces_in_flow_control_structures
          } else if (rawDate is DateTime) parsedDate = rawDate;
          if (parsedDate != null) nextDateText = DateFormat.yMMMd().format(parsedDate);
        }
      }

      _nextPaymentAmountCtl.text = nextAmountText;
      _pickedNextPaymentDate = parsedDate;
      _nextPaymentDateCtl.text = nextDateText;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load balances: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatNumber(dynamic v) {
    if (v == null) return '0';
    if (v is num) return v.toString();
    return v.toString();
  }

  double _parseDouble(String s) {
    return double.tryParse(s.replaceAll(',', '').trim()) ?? 0.0;
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailCtl.text.trim().toLowerCase();
    final borrowed = _parseDouble(_borrowedCtl.text);
    final paid = _parseDouble(_paidCtl.text);
    final actual = _parseDouble(_balanceCtl.text);
    final interest = _parseDouble(_interestCtl.text);

    final nextPaymentAmount = _nextPaymentAmountCtl.text.trim().isEmpty
        ? null
        : double.tryParse(_nextPaymentAmountCtl.text.replaceAll(',', '').trim());

    DateTime? nextPaymentDate = _pickedNextPaymentDate;
    if (nextPaymentDate == null && _nextPaymentDateCtl.text.trim().isNotEmpty) {
      try {
        nextPaymentDate = DateFormat.yMMMd().parse(_nextPaymentDateCtl.text.trim());
      } catch (_) {
        nextPaymentDate = null;
      }
    }

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'email': email,
        'amountBorrowed': borrowed,
        'amountPaid': paid,
        'actualBalance': actual,
        'interestRate': interest,
        'nextPaymentAmount': nextPaymentAmount,
        'nextPaymentDate': nextPaymentDate?.toIso8601String(),
      };

      if (widget.onSaveBalances == null) {
        // No handler — show informative snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No save handler provided. Implement onSaveBalances to persist data.')),
          );
        }
      } else {
        await widget.onSaveBalances!(payload);

        // Optionally post a notification or allow parent to do so
        final current = widget.getCurrentUserEmail?.call() ?? '';
        if (current.toLowerCase().trim() == email.toLowerCase().trim()) {
          // Parent can choose to show notification when wiring the callback
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Balances updated successfully')));
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update balances: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickNextPaymentDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickedNextPaymentDate ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        _pickedNextPaymentDate = picked;
        _nextPaymentDateCtl.text = DateFormat.yMMMd().format(picked);
      });
    }
  }

  Future<void> _confirmDelete() async {
    final email = _emailCtl.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid client email to delete')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete client?'),
        content: Text(
            'Are you sure you want to delete client "$email"?\nThis action typically requires a server-side API call.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteClient(email);
    }
  }

  Future<void> _deleteClient(String email) async {
    setState(() => _loading = true);
    try {
      if (widget.onDeleteClient == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No delete handler provided.')));
      } else {
        await widget.onDeleteClient!(email);

        // Clear form on success (optimistic)
        _emailCtl.clear();
        _borrowedCtl.clear();
        _paidCtl.clear();
        _balanceCtl.clear();
        _interestCtl.clear();
        _nextPaymentAmountCtl.clear();
        _nextPaymentDateCtl.clear();
        _pickedNextPaymentDate = null;
        _selectedClientEmail = null;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Client deletion completed')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete client: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Client Balances'),
        actions: [
          IconButton(
            tooltip: 'Refresh clients (parent must supply clients or onFetchBalances)',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () {
              // re-read clients from widget prop if provided
              if (widget.clients != null) {
                setState(() => _clients = List<Map<String, String>>.from(widget.clients!));
              }
              if (_emailCtl.text.trim().isNotEmpty) {
                _loadBalancesFor(_emailCtl.text.trim());
              } else {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No email to refresh')));
              }
            },
          ),
          IconButton(
            tooltip: 'Delete client (parent must implement onDeleteClient)',
            icon: const Icon(Icons.delete_forever),
            onPressed: _loading || _saving ? null : _confirmDelete,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    // Dropdown of registered clients
                    DropdownButtonFormField<String>(
                      initialValue: _selectedClientEmail,
                      decoration: const InputDecoration(labelText: 'Select client (or type email below)'),
                      items: _clients.isEmpty
                          ? []
                          : _clients
                              .map(
                                (c) => DropdownMenuItem<String>(
                                  value: c['email']!.toLowerCase().trim(),
                                  child: Text('${(c['name']?.isNotEmpty == true ? c['name'] : c['email'])} (${c['email']})'),
                                ),
                              )
                              .toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        _selectedClientEmail = val;
                        _emailCtl.text = val;
                        _loadBalancesFor(val);
                      },
                    ),

                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _emailCtl,
                      decoration: const InputDecoration(labelText: 'Client email', hintText: 'client@example.com'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Email is required';
                        if (!v.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                      onFieldSubmitted: (v) {
                        if (v.trim().isNotEmpty) _loadBalancesFor(v.trim());
                      },
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _borrowedCtl,
                      decoration: const InputDecoration(labelText: 'Amount Borrowed', prefixText: 'ZMW '),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Enter amount borrowed (0 if none)';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _paidCtl,
                      decoration: const InputDecoration(labelText: 'Amount Paid', prefixText: 'ZMW '),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Enter amount paid (0 if none)';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _balanceCtl,
                      decoration: const InputDecoration(labelText: 'Actual Balance', prefixText: 'ZMW '),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Enter actual balance (0 if none)';
                        return null;
                      },
                    ),

                    // Interest rate input
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _interestCtl,
                      decoration: const InputDecoration(
                        labelText: 'Interest rate (percent)',
                        suffixText: '%',
                        hintText: 'e.g., 15',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Enter interest rate (0 if none)';
                        final parsed = double.tryParse(v.trim());
                        if (parsed == null) return 'Enter a valid number';
                        if (parsed < 0) return 'Interest rate cannot be negative';
                        return null;
                      },
                    ),

                    const SizedBox(height: 12),

                    // Next payment amount (optional)
                    TextFormField(
                      controller: _nextPaymentAmountCtl,
                      decoration: const InputDecoration(
                        labelText: 'Next payment amount',
                        prefixText: 'ZMW ',
                        hintText: 'e.g., 250.00 (leave empty if none)',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null; // optional
                        final parsed = double.tryParse(v.replaceAll(',', '').trim());
                        if (parsed == null) return 'Enter a valid amount';
                        if (parsed < 0) return 'Amount cannot be negative';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Next payment date picker (optional)
                    TextFormField(
                      controller: _nextPaymentDateCtl,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Next payment date',
                        hintText: 'Tap to pick a date (optional)',
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      onTap: _pickNextPaymentDate,
                    ),

                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              icon: _saving
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.save),
                              label: Text(_saving ? 'Saving...' : 'Save balances'),
                              onPressed: _saving ? null : _onSave,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.delete),
                            label: const Text('Delete client'),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            onPressed: _loading || _saving ? null : _confirmDelete,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Debug footer: helpful text to integrator
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        widget.onSaveBalances == null
                            ? 'No save handler attached — implement onSaveBalances to persist changes.'
                            : 'Save handler attached.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
