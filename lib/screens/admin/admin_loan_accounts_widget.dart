// Supabase-backed loan account management for the overall admin.
// Admin can record repayments or mark a loan cleared.

// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:daml/widgets/app_skeleton.dart';
import 'package:daml/services/supabase_daml_service.dart';

class AdminLoanAccountsWidget extends StatefulWidget {
  const AdminLoanAccountsWidget({super.key});

  @override
  State<AdminLoanAccountsWidget> createState() => _AdminLoanAccountsWidgetState();
}

class _AdminLoanAccountsWidgetState extends State<AdminLoanAccountsWidget> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  double _amount(dynamic value) => SupabaseDamlService.parseAmount(value);

  String _money(dynamic value) => 'ZMW ${_amount(value).toStringAsFixed(2)}';

  String _text(dynamic value, {String fallback = '—'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
  }

  bool _isCleared(Map<String, dynamic> row) {
    final balance = _amount(row['current_balance']);
    final status = _text(row['loan_status'], fallback: '').toLowerCase();
    return balance <= 0.005 || status.contains('cleared') || status.contains('paid');
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    try {
      _items = await SupabaseDamlService.fetchLoanAccounts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load loan accounts: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recordPayment(Map<String, dynamic> row) async {
    final accountId = _text(row['id'], fallback: '');
    if (accountId.isEmpty) return;

    final amountController = TextEditingController();
    final referenceController = TextEditingController();
    final notesController = TextEditingController();
    final balance = _amount(row['current_balance']);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Record Payment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current balance: ${_money(balance)}'),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Payment amount',
                  prefixText: 'ZMW ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: referenceController,
                decoration: const InputDecoration(
                  labelText: 'Reference / receipt number (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, {
              'amount': amountController.text,
              'reference': referenceController.text,
              'notes': notesController.text,
            }),
            child: const Text('Save Payment'),
          ),
        ],
      ),
    );

    amountController.dispose();
    referenceController.dispose();
    notesController.dispose();

    if (result == null) return;
    final amount = double.tryParse((result['amount'] ?? '').replaceAll(',', '').trim());
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid payment amount.')),
        );
      }
      return;
    }

    try {
      final response = await SupabaseDamlService.recordLoanPayment(
        loanAccountId: accountId,
        amount: amount,
        reference: result['reference'],
        notes: result['notes'],
      );
      await _refresh();
      if (mounted) {
        final newBalance = _money(response['current_balance'] ?? 0);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment recorded. New balance: $newBalance')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment failed: $e')),
        );
      }
    }
  }

  Future<void> _markCleared(Map<String, dynamic> row) async {
    final accountId = _text(row['id'], fallback: '');
    if (accountId.isEmpty) return;

    final reasonController = TextEditingController(text: 'Loan fully cleared');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark Loan Cleared?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will set the client current balance to ZMW 0.00.\n\n'
              'Current balance: ${_money(row['current_balance'])}',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason / note',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Mark Cleared'),
          ),
        ],
      ),
    );

    final reason = reasonController.text;
    reasonController.dispose();
    if (confirmed != true) return;

    try {
      await SupabaseDamlService.clearLoanAccount(
        loanAccountId: accountId,
        reason: reason,
      );
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loan marked cleared. Client balance is now ZMW 0.00.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Clearance failed: $e')),
        );
      }
    }
  }

  Widget _statusChip(Map<String, dynamic> row) {
    final cleared = _isCleared(row);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cleared ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cleared ? const Color(0xFF81C784) : const Color(0xFFFFCA28)),
      ),
      child: Text(
        cleared ? 'CLEARED' : 'ACTIVE',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: cleared ? const Color(0xFF2E7D32) : const Color(0xFF8D6E00),
        ),
      ),
    );
  }

  Widget _accountCard(Map<String, dynamic> row) {
    final cleared = _isCleared(row);
    final name = _text(row['client_name'], fallback: 'Client');
    final email = _text(row['client_email']);
    final phone = _text(row['client_phone']);

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Icon(cleared ? Icons.check : Icons.account_balance_wallet_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(email, overflow: TextOverflow.ellipsis),
                      if (phone != '—') Text(phone),
                    ],
                  ),
                ),
                _statusChip(row),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _metric('Borrowed', _money(row['principal_amount'])),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metric('Current Balance', _money(row['current_balance'])),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: cleared ? null : () => _recordPayment(row),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Record Payment'),
                ),
                OutlinedButton.icon(
                  onPressed: cleared ? null : () => _markCleared(row),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Mark Cleared'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AppPageSkeleton();

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 140),
            Icon(Icons.account_balance_wallet_outlined, size: 48),
            SizedBox(height: 12),
            Center(child: Text('No live loan accounts yet')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, index) => _accountCard(_items[index]),
      ),
    );
  }
}
