import 'package:hive/hive.dart';

part 'expense_item.g.dart';

@HiveType(typeId: 10) // pick a unique id for your app
class ExpenseItem extends HiveObject {
  @HiveField(0)
  String description;

  @HiveField(1)
  double amount;

  @HiveField(2)
  DateTime date;

  @HiveField(3)
  String branch;

  @HiveField(4)
  String? account; // optional account/category

  ExpenseItem({
    required this.description,
    required this.amount,
    required this.date,
    required this.branch,
    this.account,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'amount': amount,
        'date': date.toIso8601String(),
        'branch': branch,
        'account': account,
      };

  @override
  String toString() => 'ExpenseItem($description, $amount, $branch, $date)';
}