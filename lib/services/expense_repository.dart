// lib/services/expense_repository.dart
import 'package:hive/hive.dart';
import 'package:daml/models/expense_item.dart';

class ExpenseRepository {
  static const String _boxName = 'expensesBox';

  Future<Box<ExpenseItem>> _openBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox<ExpenseItem>(_boxName);
    }
    return Hive.box<ExpenseItem>(_boxName);
  }

  Future<List<ExpenseItem>> getExpensesForBranch(String branch) async {
    final box = await _openBox();
    return box.values.where((e) => e.branch == branch).toList();
  }

  Future<int> addExpense(ExpenseItem item) async {
    final box = await _openBox();
    return await box.add(item);
  }

  Future<void> deleteExpense(int key) async {
    final box = await _openBox();
    await box.delete(key);
  }

  Future<double> totalForBranch(String branch) async {
    final box = await _openBox();
    final items = box.values.where((e) => e.branch == branch);
    return items.fold<double>(0.0, (s, i) => s + i.amount);
  }

  Future<void> clearForBranch(String branch) async {
    final box = await _openBox();
    final keysToDelete = box.keys.where((k) => box.get(k)?.branch == branch).toList();
    for (final k in keysToDelete) {
      await box.delete(k);
    }
  }
}
