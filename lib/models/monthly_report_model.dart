// lib/models/monthly_report_model.dart
// Robust MonthlyReport model with Hive annotations and flexible parsing
// for Mongo-export shapes.

import 'package:hive/hive.dart';

part 'monthly_report_model.g.dart';

@HiveType(typeId: 1)
class MonthlyReport {
  @HiveField(0)
  final String branch;

  @HiveField(1)
  final DateTime date;

  @HiveField(2)
  final double? expected;

  @HiveField(3)
  final int? inputs;

  @HiveField(4)
  final double? collected;

  @HiveField(5)
  final int? collectedInput;

  @HiveField(6)
  final double? totalUncollected;

  @HiveField(7)
  final int? uncollectedInput;

  @HiveField(8)
  final double? insufficient;

  @HiveField(9)
  final int? insufficientInput;

  @HiveField(10)
  final double? unreported;

  @HiveField(11)
  final int? unreportedInput;

  @HiveField(12)
  final double? lateCollection;

  @HiveField(13)
  final double? uncollected;

  @HiveField(14)
  final double? permicExpectedNextMonth;

  @HiveField(15)
  final int? totalInputs;

  @HiveField(16)
  final double? oldInputsAmount;

  @HiveField(17)
  final int? oldInputsCount;

  @HiveField(18)
  final double? newInputsAmount;

  @HiveField(19)
  final int? newInputsCount;

  @HiveField(20)
  final double? cashAdvance;

  @HiveField(21)
  final double? overallExpected;

  @HiveField(22)
  final double? actualExpected;

  @HiveField(23)
  final double? collected2;

  @HiveField(24)
  final double? principalReloaned;

  @HiveField(25)
  final double? defaultAmount;

  @HiveField(26)
  final double? clearance;

  @HiveField(27)
  final double? totalCollections;

  @HiveField(28)
  final double? permicCashAdvance;

  @HiveField(29, defaultValue: false)
  bool synced;

  @HiveField(30)
  final DateTime updatedAt;

  @HiveField(31)
  final DateTime createdAt;

  // ✅ Optional compatibility fields (previously "required" in your constructor)
  @HiveField(32)
  final int? year;

  @HiveField(33)
  final int? month;

  @HiveField(34)
  final double? totalCollected;

  @HiveField(35)
  final double? totalDisbursed;

  @HiveField(36)
  final double? totalExpenses;

  MonthlyReport({
    required this.branch,
    required this.date,
    this.expected,
    this.inputs,
    this.collected,
    this.collectedInput,
    this.totalUncollected,
    this.uncollectedInput,
    this.insufficient,
    this.insufficientInput,
    this.unreported,
    this.unreportedInput,
    this.lateCollection,
    this.uncollected,
    this.permicExpectedNextMonth,
    this.totalInputs,
    this.oldInputsAmount,
    this.oldInputsCount,
    this.newInputsAmount,
    this.newInputsCount,
    this.cashAdvance,
    this.overallExpected,
    this.actualExpected,
    this.collected2,
    this.principalReloaned,
    this.defaultAmount,
    this.clearance,
    this.totalCollections,
    this.permicCashAdvance,
    this.synced = false,
    DateTime? updatedAt,
    DateTime? createdAt,

    // optional compat params
    this.year,
    this.month,
    this.totalCollected,
    this.totalDisbursed,
    this.totalExpenses,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  MonthlyReport copyWith({
    String? branch,
    DateTime? date,
    double? expected,
    int? inputs,
    double? collected,
    int? collectedInput,
    double? totalUncollected,
    int? uncollectedInput,
    double? insufficient,
    int? insufficientInput,
    double? unreported,
    int? unreportedInput,
    double? lateCollection,
    double? uncollected,
    double? permicExpectedNextMonth,
    int? totalInputs,
    double? oldInputsAmount,
    int? oldInputsCount,
    double? newInputsAmount,
    int? newInputsCount,
    double? cashAdvance,
    double? overallExpected,
    double? actualExpected,
    double? collected2,
    double? principalReloaned,
    double? defaultAmount,
    double? clearance,
    double? totalCollections,
    double? permicCashAdvance,
    bool? synced,
    DateTime? updatedAt,
    DateTime? createdAt,

    int? year,
    int? month,
    double? totalCollected,
    double? totalDisbursed,
    double? totalExpenses,
  }) {
    return MonthlyReport(
      branch: branch ?? this.branch,
      date: date ?? this.date,
      expected: expected ?? this.expected,
      inputs: inputs ?? this.inputs,
      collected: collected ?? this.collected,
      collectedInput: collectedInput ?? this.collectedInput,
      totalUncollected: totalUncollected ?? this.totalUncollected,
      uncollectedInput: uncollectedInput ?? this.uncollectedInput,
      insufficient: insufficient ?? this.insufficient,
      insufficientInput: insufficientInput ?? this.insufficientInput,
      unreported: unreported ?? this.unreported,
      unreportedInput: unreportedInput ?? this.unreportedInput,
      lateCollection: lateCollection ?? this.lateCollection,
      uncollected: uncollected ?? this.uncollected,
      permicExpectedNextMonth: permicExpectedNextMonth ?? this.permicExpectedNextMonth,
      totalInputs: totalInputs ?? this.totalInputs,
      oldInputsAmount: oldInputsAmount ?? this.oldInputsAmount,
      oldInputsCount: oldInputsCount ?? this.oldInputsCount,
      newInputsAmount: newInputsAmount ?? this.newInputsAmount,
      newInputsCount: newInputsCount ?? this.newInputsCount,
      cashAdvance: cashAdvance ?? this.cashAdvance,
      overallExpected: overallExpected ?? this.overallExpected,
      actualExpected: actualExpected ?? this.actualExpected,
      collected2: collected2 ?? this.collected2,
      principalReloaned: principalReloaned ?? this.principalReloaned,
      defaultAmount: defaultAmount ?? this.defaultAmount,
      clearance: clearance ?? this.clearance,
      totalCollections: totalCollections ?? this.totalCollections,
      permicCashAdvance: permicCashAdvance ?? this.permicCashAdvance,
      synced: synced ?? this.synced,
      updatedAt: updatedAt ?? DateTime.now(),
      createdAt: createdAt ?? this.createdAt,
      year: year ?? this.year,
      month: month ?? this.month,
      totalCollected: totalCollected ?? this.totalCollected,
      totalDisbursed: totalDisbursed ?? this.totalDisbursed,
      totalExpenses: totalExpenses ?? this.totalExpenses,
    );
  }

  // normalize to month start (UTC)
  static DateTime _normalizeToMonthStartUtc(DateTime d) {
    final u = d.toUtc();
    return DateTime.utc(u.year, u.month, 1);
  }

  static double _flexDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '').trim()) ?? 0.0;
    if (v is Map) {
      if (v.containsKey(r'$numberInt')) return double.tryParse(v[r'$numberInt'].toString()) ?? 0.0;
      if (v.containsKey(r'$numberLong')) return double.tryParse(v[r'$numberLong'].toString()) ?? 0.0;
      if (v.containsKey(r'$numberDecimal')) return double.tryParse(v[r'$numberDecimal'].toString()) ?? 0.0;
      if (v.values.isNotEmpty) return _flexDouble(v.values.first);
    }
    return 0.0;
  }

  static int? _flexIntNullable(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final cleaned = v.trim().replaceAll(',', '');
      if (cleaned.isEmpty) return null;
      return int.tryParse(cleaned) ?? double.tryParse(cleaned)?.toInt();
    }
    if (v is Map) {
      if (v.containsKey(r'$numberInt')) return int.tryParse(v[r'$numberInt'].toString()) ?? 0;
      if (v.containsKey(r'$numberLong')) return int.tryParse(v[r'$numberLong'].toString()) ?? 0;
      if (v.values.isNotEmpty) return _flexIntNullable(v.values.first);
    }
    return null;
  }

  static DateTime _flexParseDate(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is DateTime) return v;
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    if (v is String) {
      final asInt = int.tryParse(v);
      if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
      return DateTime.tryParse(v) ?? DateTime.now();
    }
    if (v is Map) {
      if (v.containsKey(r'$date')) return _flexParseDate(v[r'$date']);
      if (v.containsKey(r'$numberLong')) {
        final iv = int.tryParse(v[r'$numberLong'].toString());
        if (iv != null) return DateTime.fromMillisecondsSinceEpoch(iv);
      }
      if (v.values.isNotEmpty) return _flexParseDate(v.values.first);
    }
    return DateTime.now();
  }

  factory MonthlyReport.fromJson(Map<dynamic, dynamic> item) {
    final branch = (item['branch'] ?? '').toString();
    final parsedDate = _flexParseDate(item['date']);
    final normalized = _normalizeToMonthStartUtc(parsedDate);

    final parsedUpdated = _flexParseDate(item['updatedAt'] ?? item['updated_at'] ?? DateTime.now());
    final parsedCreated = _flexParseDate(item['createdAt'] ?? item['created_at'] ?? DateTime.now());

    return MonthlyReport(
      branch: branch,
      date: normalized,
      expected: _flexDouble(item['expected']),
      inputs: _flexIntNullable(item['inputs']),
      collected: _flexDouble(item['collected']),
      collectedInput: _flexIntNullable(item['collectedInput']),
      totalUncollected: _flexDouble(item['totalUncollected'] ?? item['total_uncollected']),
      uncollectedInput: _flexIntNullable(item['uncollectedInput']),
      insufficient: _flexDouble(item['insufficient']),
      insufficientInput: _flexIntNullable(item['insufficientInput']),
      unreported: _flexDouble(item['unreported']),
      unreportedInput: _flexIntNullable(item['unreportedInput']),
      lateCollection: _flexDouble(item['lateCollection']),
      uncollected: _flexDouble(item['uncollected']),
      permicExpectedNextMonth: _flexDouble(item['permicExpectedNextMonth']),
      totalInputs: _flexIntNullable(item['totalInputs']),
      oldInputsAmount: _flexDouble(item['oldInputsAmount']),
      oldInputsCount: _flexIntNullable(item['oldInputsCount']),
      newInputsAmount: _flexDouble(item['newInputsAmount']),
      newInputsCount: _flexIntNullable(item['newInputsCount']),
      cashAdvance: _flexDouble(item['cashAdvance']),
      overallExpected: _flexDouble(item['overallExpected']),
      actualExpected: _flexDouble(item['actualExpected']),
      collected2: _flexDouble(item['collected2']),
      principalReloaned: _flexDouble(item['principalReloaned']),
      defaultAmount: _flexDouble(item['defaultAmount']),
      clearance: _flexDouble(item['clearance']),
      totalCollections: _flexDouble(item['totalCollections']),
      permicCashAdvance: _flexDouble(item['permicCashAdvance']),
      synced: (item['synced'] == true),
      updatedAt: parsedUpdated,
      createdAt: parsedCreated,

      // compat fields if present
      year: _flexIntNullable(item['year']) ?? normalized.year,
      month: _flexIntNullable(item['month']) ?? normalized.month,
      totalCollected: _flexDouble(item['totalCollected']),
      totalDisbursed: _flexDouble(item['totalDisbursed']),
      totalExpenses: _flexDouble(item['totalExpenses']),
    );
  }

  Map<String, dynamic> toJson() => {
        'branch': branch,
        'date': date.toUtc().toIso8601String(),
        'expected': expected,
        'inputs': inputs,
        'collected': collected,
        'collectedInput': collectedInput,
        'totalUncollected': totalUncollected,
        'uncollectedInput': uncollectedInput,
        'insufficient': insufficient,
        'insufficientInput': insufficientInput,
        'unreported': unreported,
        'unreportedInput': unreportedInput,
        'lateCollection': lateCollection,
        'uncollected': uncollected,
        'permicExpectedNextMonth': permicExpectedNextMonth,
        'totalInputs': totalInputs,
        'oldInputsAmount': oldInputsAmount,
        'oldInputsCount': oldInputsCount,
        'newInputsAmount': newInputsAmount,
        'newInputsCount': newInputsCount,
        'cashAdvance': cashAdvance,
        'overallExpected': overallExpected,
        'actualExpected': actualExpected,
        'collected2': collected2,
        'principalReloaned': principalReloaned,
        'defaultAmount': defaultAmount,
        'clearance': clearance,
        'totalCollections': totalCollections,
        'permicCashAdvance': permicCashAdvance,
        'synced': synced,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'createdAt': createdAt.toUtc().toIso8601String(),

        // compat fields
        'year': year,
        'month': month,
        'totalCollected': totalCollected,
        'totalDisbursed': totalDisbursed,
        'totalExpenses': totalExpenses,
      };
}
