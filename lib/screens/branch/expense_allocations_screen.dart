// lib/screens/branch/expense_allocations_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daml/models/expense_item.dart';
import 'package:daml/services/expense_repository.dart';

class ExpenseAllocationsScreen extends StatefulWidget {
  final String branchName;
  const ExpenseAllocationsScreen({super.key, required this.branchName});

  @override
  State<ExpenseAllocationsScreen> createState() => _ExpenseAllocationsScreenState();
}

class _ExpenseAllocationsScreenState extends State<ExpenseAllocationsScreen> {
  final ExpenseRepository _repo = ExpenseRepository();
  late Future<List<ExpenseItem>> _futureItems;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _futureItems = _repo.getExpensesForBranch(widget.branchName);
  }

  Future<void> _showAddDialog() async {
    final descCtl = TextEditingController();
    final amtCtl = TextEditingController();
    final acctCtl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Expense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: descCtl, decoration: const InputDecoration(labelText: 'Description')),
            TextField(controller: amtCtl, decoration: const InputDecoration(labelText: 'Amount'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            TextField(controller: acctCtl, decoration: const InputDecoration(labelText: 'Account (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final desc = descCtl.text.trim();
              final amt = double.tryParse(amtCtl.text.replaceAll(',', '')) ?? 0.0;
              if (desc.isEmpty || amt <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Provide description and amount > 0')));
                return;
              }
              final item = ExpenseItem(description: desc, amount: amt, date: DateTime.now(), branch: widget.branchName, account: acctCtl.text.trim().isEmpty ? null : acctCtl.text.trim());
              _repo.addExpense(item);
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (saved == true) {
      setState(() => _reload());
    }
  }

  Future<void> _deleteItem(int key) async {
    await _repo.deleteExpense(key);
    setState(() => _reload());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Expense Allocations • ${widget.branchName}'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _showAddDialog),
        ],
      ),
      body: FutureBuilder<List<ExpenseItem>>(
        future: _futureItems,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return Center(child: Text('No expenses recorded for ${widget.branchName}'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, i) {
              final it = items[i];
              // HiveObject keys are accessible when object stored in box; use .key if available, else show index
              final key = it.key;
              return ListTile(
                title: Text(it.description),
                subtitle: Text('${it.account ?? 'General'} • ${DateFormat.yMd().format(it.date)}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(it.amount.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: key != null ? () => _deleteItem(key as int) : null),
                ]),
              );
            },
            separatorBuilder: (_, __) => const Divider(),
            itemCount: items.length,
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
