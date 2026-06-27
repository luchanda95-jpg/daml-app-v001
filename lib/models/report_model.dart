// lib/models/report_model.dart
// Robust DailyReport model with Hive annotations and flexible parsing for
// Mongo-export shapes ({"$date": {"$numberLong": "..." }}, {"$numberInt":"..."}, etc.)

// ignore_for_file: unnecessary_type_check, unused_element, curly_braces_in_flow_control_structures, duplicate_ignore

import 'package:hive/hive.dart';

part 'report_model.g.dart';

@HiveType(typeId: 0)
class DailyReport {
  @HiveField(0)
  final String branch;

  @HiveField(1)
  final DateTime date;

  @HiveField(2)
  final Map<String, double>? openingBalances;

  @HiveField(3)
  final Map<String, int>? loanCounts;

  @HiveField(4)
  final Map<String, double>? closingBalances;

  @HiveField(5)
  final double? totalDisbursed;

  @HiveField(6)
  final double? totalCollected;

  @HiveField(7)
  final double? collectedForOtherBranches;

  @HiveField(8)
  final double? pettyCash;

  @HiveField(9)
  final double? expenses;

  @HiveField(10, defaultValue: false)
  bool synced;

  @HiveField(11)
  final DateTime updatedAt;

  /// NEW: per-channel sentinel to mark that Zanaco distributions have been applied.
  /// Example: { 'Airtel': true, 'MTN': true }
  @HiveField(12)
  final Map<String, bool>? zanacoApplied;

  DailyReport({
    required this.branch,
    required this.date,
    this.openingBalances,
    this.loanCounts,
    this.closingBalances,
    this.totalDisbursed,
    this.totalCollected,
    this.collectedForOtherBranches,
    this.pettyCash,
    this.expenses,
    this.synced = false,
    DateTime? updatedAt,
    this.zanacoApplied, required totalLoans,
  }) : updatedAt = updatedAt ?? DateTime.now();

  // ---------- Convenience getters ----------
  double get totalOpening =>
      (openingBalances ?? {}).values.fold(0.0, (sum, amount) => sum + (amount));

  double get totalClosing =>
      (closingBalances ?? {}).values.fold(0.0, (sum, amount) => sum + (amount));

  int get totalLoans =>
      (loanCounts ?? {}).values.fold(0, (sum, count) {
        if (count is num) return sum + count.toInt();
        final parsed = int.tryParse(count.toString()) ?? 0;
        return sum + parsed;
      });

  /// return whether Zanaco allocation has been applied for the given channel
  bool isZanacoApplied(String channel) => (zanacoApplied ?? {})[channel] ?? false;

  // ---------- copyWith ----------
  DailyReport copyWith({
    String? branch,
    DateTime? date,
    Map<String, double>? openingBalances,
    Map<String, int>? loanCounts,
    Map<String, double>? closingBalances,
    double? totalDisbursed,
    double? totalCollected,
    double? collectedForOtherBranches,
    double? pettyCash,
    double? expenses,
    bool? synced,
    Map<String, bool>? zanacoApplied,
  }) {
    return DailyReport(
      branch: branch ?? this.branch,
      date: date ?? this.date,
      openingBalances: openingBalances ?? this.openingBalances,
      loanCounts: loanCounts ?? this.loanCounts,
      closingBalances: closingBalances ?? this.closingBalances,
      totalDisbursed: totalDisbursed ?? this.totalDisbursed,
      totalCollected: totalCollected ?? this.totalCollected,
      collectedForOtherBranches: collectedForOtherBranches ?? this.collectedForOtherBranches,
      pettyCash: pettyCash ?? this.pettyCash,
      expenses: expenses ?? this.expenses,
      synced: synced ?? this.synced,
      updatedAt: DateTime.now(),
      zanacoApplied: zanacoApplied ?? this.zanacoApplied, totalLoans: null,
    );
  }

  // ------------------------------
  // Flexible parsing for Mongo-export shapes
  // ------------------------------

  /// Parse flexible numeric shapes like:
  /// - 1000
  /// - "1000"
  /// - {"$numberInt":"1000"}
  /// - {"$numberLong":"1760572800000"}
  /// - {"$numberDecimal":"1000.00"}
  static double _extractDoubleFlexible(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) {
      final cleaned = v.replaceAll(',', '').trim();
      return double.tryParse(cleaned) ?? 0.0;
    }
    if (v is Map) {
      // Check typical mongo numeric wrappers
      if (v.containsKey(r'$numberInt')) return double.tryParse(v[r'$numberInt'].toString()) ?? 0.0;
      if (v.containsKey(r'$numberLong')) return double.tryParse(v[r'$numberLong'].toString()) ?? 0.0;
      if (v.containsKey(r'$numberDecimal')) return double.tryParse(v[r'$numberDecimal'].toString()) ?? 0.0;
      // If nested shape (e.g. { amount: { $numberInt: '100' } }), try first value
      if (v.values.isNotEmpty) return _extractDoubleFlexible(v.values.first);
    }
    return 0.0;
  }

  static int _extractIntFlexible(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final cleaned = v.replaceAll(',', '').trim();
      return int.tryParse(cleaned) ?? double.tryParse(cleaned)?.toInt() ?? 0;
    }
    if (v is Map) {
      if (v.containsKey(r'$numberInt')) return int.tryParse(v[r'$numberInt'].toString()) ?? 0;
      if (v.containsKey(r'$numberLong')) return int.tryParse(v[r'$numberLong'].toString()) ?? 0;
      if (v.values.isNotEmpty) return _extractIntFlexible(v.values.first);
    }
    return 0;
  }

  static DateTime _parseFlexibleDate(dynamic d) {
    if (d == null) return DateTime.now();
    if (d is DateTime) return d;
    if (d is num) return DateTime.fromMillisecondsSinceEpoch(d.toInt());
    if (d is String) {
      final asInt = int.tryParse(d);
      if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
      return DateTime.tryParse(d) ?? DateTime.now();
    }
    if (d is Map) {
      // Typical mongo date wrapper: {"$date": {"$numberLong":"1760572800000"}}
      if (d.containsKey(r'$date')) return _parseFlexibleDate(d[r'$date']);
      if (d.containsKey(r'$numberLong')) {
        final n = d[r'$numberLong'];
        final iv = int.tryParse(n.toString());
        if (iv != null) return DateTime.fromMillisecondsSinceEpoch(iv);
      }
      // fallback: try first value
      if (d.values.isNotEmpty) return _parseFlexibleDate(d.values.first);
    }
    return DateTime.now();
  }

  static Map<String, double>? _toDoubleMapFlexible(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) {
      final out = <String, double>{};
      raw.forEach((k, v) {
        final key = k.toString();
        out[key] = _extractDoubleFlexible(v);
      });
      return out.isEmpty ? null : out;
    }
    return null;
  }

  static Map<String, int>? _toIntMapFlexible(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) {
      final out = <String, int>{};
      raw.forEach((k, v) {
        final key = k.toString();
        out[key] = _extractIntFlexible(v);
      });
      return out.isEmpty ? null : out;
    }
    return null;
  }

  static Map<String, bool>? _toBoolMapFlexible(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) {
      final out = <String, bool>{};
      raw.forEach((k, v) {
        final key = k.toString();
        if (v is bool) out[key] = v;
        else if (v is num) out[key] = v != 0;
        else if (v is String) {
          final lw = v.toLowerCase();
          out[key] = (lw == 'true' || lw == '1' || lw == 'yes');
        } else out[key] = false;
      });
      return out.isEmpty ? null : out;
    }
    return null;
  }

  /// Robust factory that handles Mongo-export shapes and regular maps.
  factory DailyReport.fromJson(Map<dynamic, dynamic> map) {
    final branch = (map['branch'] ?? map['Branch'] ?? '').toString();
    final date = _parseFlexibleDate(map['date'] ?? map['Date'] ?? DateTime.now());
    final opening = _toDoubleMapFlexible(map['openingBalances'] ?? map['opening_balances'] ?? map['openings']);
    final closing = _toDoubleMapFlexible(map['closingBalances'] ?? map['closing_balances'] ?? map['closings']);
    final loanCounts = _toIntMapFlexible(map['loanCounts'] ?? map['loan_counts'] ?? map['loans']);
    final totalDisbursed = _extractDoubleFlexible(map['totalDisbursed'] ?? map['total_disbursed'] ?? map['disbursed']);
    final totalCollected = _extractDoubleFlexible(map['totalCollected'] ?? map['total_collected'] ?? map['collected']);
    final collectedForOtherBranches = _extractDoubleFlexible(map['collectedForOtherBranches'] ?? map['collected_for_other_branches']);
    final pettyCash = _extractDoubleFlexible(map['pettyCash'] ?? map['petty_cash']);
    final expenses = _extractDoubleFlexible(map['expenses']);
    final synced = (map['synced'] == true);
    final updatedAt = _parseFlexibleDate(map['updatedAt'] ?? map['updated_at'] ?? DateTime.now());
    final zanacoApplied = _toBoolMapFlexible(map['zanacoApplied'] ?? map['zanaco_applied']);

    // Keep compatibility with your constructor which expects totalLoans argument (you use null elsewhere)
    return DailyReport(
      branch: branch,
      date: date,
      openingBalances: opening,
      loanCounts: loanCounts,
      closingBalances: closing,
      totalDisbursed: totalDisbursed,
      totalCollected: totalCollected,
      collectedForOtherBranches: collectedForOtherBranches,
      pettyCash: pettyCash,
      expenses: expenses,
      synced: synced,
      updatedAt: updatedAt,
      zanacoApplied: zanacoApplied, totalLoans: null,
    );
  }

  /// Backwards-compatible alias if other code calls fromMap.
  factory DailyReport.fromMap(Map<dynamic, dynamic> map) => DailyReport.fromJson(map);

  // ---------- Convert to a plain Map<String, dynamic> ----------
  Map<String, dynamic> toMap() {
    return {
      'branch': branch,
      'date': date.toIso8601String(),
      'openingBalances': openingBalances,
      'loanCounts': loanCounts,
      'closingBalances': closingBalances,
      'totalDisbursed': totalDisbursed,
      'totalCollected': totalCollected,
      'collectedForOtherBranches': collectedForOtherBranches,
      'pettyCash': pettyCash,
      'expenses': expenses,
      'synced': synced,
      'updatedAt': updatedAt.toIso8601String(),
      'zanacoApplied': zanacoApplied,
    };
  }
}
