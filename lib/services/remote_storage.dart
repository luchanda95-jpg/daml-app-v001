// lib/services/remote_storage.dart
// ignore_for_file: unrelated_type_equality_checks, prefer_typing_uninitialized_variables, curly_braces_in_flow_control_structures, unintended_html_in_doc_comment

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:daml/models/report_model.dart'; // DailyReport
import 'package:daml/models/monthly_report_model.dart'; // MonthlyReport
import 'package:daml/services/api_service.dart';

/// RemoteStorage: tries server first, falls back to local Hive cache.
/// Keeps a small API compatible with your existing LocalStorage usage.
class RemoteStorage {
  static const _reportsBox = 'reports';
  static const _monthlyBox = 'monthly_reports';

  static var instance;

  /// Call at app startup (main)
  static Future<void> ensureInitialized() async {
    // Ensure Hive is initialized by caller (LocalStorage.init does this).
    // Open / create boxes we use.
    if (!Hive.isBoxOpen(_reportsBox)) {
      try {
        await Hive.openBox<DailyReport>(_reportsBox);
      } catch (e) {
        debugPrint('RemoteStorage.ensureInitialized: failed to open reports box: $e');
      }
    }
    if (!Hive.isBoxOpen(_monthlyBox)) {
      try {
        await Hive.openBox<MonthlyReport>(_monthlyBox);
      } catch (e) {
        debugPrint('RemoteStorage.ensureInitialized: failed to open monthly_reports box: $e');
      }
    }
  }

  static String _keyFor(String branch, DateTime date) {
    final norm = DateTime.utc(date.year, date.month, date.day);
    // For monthly reports we will use YYYY-MM keys; for daily we keep iso day
    return '${branch.trim().toLowerCase()}::${norm.toIso8601String()}';
  }

  // ---------------- DAILY REPORTS ----------------

  /// Save report: try server upsert; if succeeds mark local copy as synced; else save locally as unsynced
  static Future<void> saveReport(DailyReport report) async {
    await ensureInitialized();
    try {
      final conn = await Connectivity().checkConnectivity();
      if (conn != ConnectivityResult.none) {
        // Convert to plain map expected by server
        final rmap = report.toMap();
        try {
          await ApiService.saveReportSingle(rmap);
          // persist local copy marked synced = true
          final synced = report.copyWith(synced: true);
          final box = Hive.box<DailyReport>(_reportsBox);
          await box.put(_keyFor(report.branch, report.date), synced);
          return;
        } catch (e) {
          debugPrint('RemoteStorage.saveReport: server upsert failed, falling back to local: $e');
        }
      } else {
        debugPrint('RemoteStorage.saveReport: no connectivity - saving locally');
      }
    } catch (e) {
      debugPrint('RemoteStorage.saveReport: connectivity check failed: $e');
    }

    // fallback: save locally with synced=false
    try {
      final box = Hive.box<DailyReport>(_reportsBox);
      final unsynced = report.copyWith(synced: false);
      await box.put(_keyFor(report.branch, report.date), unsynced);
    } catch (e) {
      debugPrint('RemoteStorage.saveReport: local save failed: $e');
      rethrow;
    }
  }

  static ValueListenable<Box<DailyReport>> getReportsListenable() {
    if (!Hive.isBoxOpen(_reportsBox)) throw Exception('Reports box is not open');
    return Hive.box<DailyReport>(_reportsBox).listenable();
  }

  /// Push pending unsynced reports to server (retry loop). Marks them synced locally on success.
  static Future<Map<String, dynamic>> pushPendingReports({int limit = 200}) async {
    await ensureInitialized();
    final box = Hive.box<DailyReport>(_reportsBox);
    final pending = <DailyReport>[];
    for (final v in box.values) {
      if (v.synced != true) pending.add(v);
      if (pending.length >= limit) break;
    }
    if (pending.isEmpty) return {'ok': true, 'pushed': 0};

    final payload = pending.map((r) => r.toMap()).toList();
    try {
      final resp = await ApiService.syncReports(payload);
      // Mark them synced locally
      for (final r in pending) {
        final key = _keyFor(r.branch, r.date);
        final updated = r.copyWith(synced: true);
        await box.put(key, updated);
      }
      return {'ok': true, 'pushed': pending.length, 'server': resp};
    } catch (e) {
      debugPrint('RemoteStorage.pushPendingReports: syncReports failed: $e');
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Debug helper: print local reports
  static void debugPrintLocalReports() {
    if (!Hive.isBoxOpen(_reportsBox)) return;
    final box = Hive.box<DailyReport>(_reportsBox);
    for (final k in box.keys) {
      debugPrint('report key: $k');
      debugPrint(' -> ${box.get(k)}');
    }
  }

  // ---------------- ZANACO ----------------

  /// Get zanaco allocation for branch & date & channel. Tries server first; returns 0.0 on errors.
  static Future<double> getZanacoAllocForBranchOnDate(DateTime date, String channel, String branch) async {
    try {
      final json = await ApiService.getZanaco(date: date, branch: branch, channel: channel);
      // server returns { success: true, amount: N } or { distributions: [...] }
      if (json is Map && json.containsKey('amount')) {
        final amt = json['amount'];
        if (amt is num) return amt.toDouble();
        if (amt is String) return double.tryParse(amt) ?? 0.0;
      }
      // if distributions array given, find matching
      if (json is Map && json['distributions'] is List) {
        final list = (json['distributions'] as List);
        // find matching branch+channel if present, else take first
        for (final item in list) {
          if (item is Map) {
            final b = (item['branch'] ?? '').toString();
            final ch = (item['channel'] ?? '').toString().toLowerCase();
            if (b.toLowerCase().trim() == branch.toLowerCase().trim() && ch == channel.toLowerCase().trim()) {
              final v = item['amount'];
              if (v is num) return v.toDouble();
              if (v is String) return double.tryParse(v) ?? 0.0;
            }
          }
        }
        if (list.isNotEmpty) {
          final first = list.first;
          if (first is Map && first['amount'] != null) {
            final v = first['amount'];
            if (v is num) return v.toDouble();
            if (v is String) return double.tryParse(v) ?? 0.0;
          }
        }
      }
    } catch (e) {
      debugPrint('RemoteStorage.getZanacoAllocForBranchOnDate failed: $e');
    }
    return 0.0;
  }

  /// Save zanaco allocations in bulk using API's bulk endpoint. Returns server response map or throws.
  static Future<Map<String, dynamic>> saveZanacoBulk(DateTime date, String fromBranch, Map<String, Map<String, double>> allocations) async {
    return ApiService.saveZanacoBulk(date: date, fromBranch: fromBranch, allocations: allocations, distributions: []);
  }

  // ---------------- Branch comments ----------------
  static Future<bool> saveBranchComment(String branch, String text, String author) async {
    try {
      final resp = await ApiService.saveBranchComment(branch, text, author);
      return resp['success'] == true || resp['ok'] == true;
    } catch (e) {
      debugPrint('RemoteStorage.saveBranchComment failed: $e');
      return false;
    }
  }

  // ---------------- MONTHLY REPORTS ----------------

  /// Convert server JSON list and save into Hive box 'monthly_reports' (overwrite).
  /// Accepts List<dynamic> with either Map<String, dynamic> shapes or already parsed MonthlyReport objects.
  static Future<void> saveMonthlyReportsFromServer(List<dynamic> docs) async {
    await ensureInitialized();
    try {
      if (!Hive.isBoxOpen(_monthlyBox)) await Hive.openBox<MonthlyReport>(_monthlyBox);
    } catch (e) {
      debugPrint('saveMonthlyReportsFromServer: failed to open monthly box: $e');
    }

    final box = Hive.box<MonthlyReport>(_monthlyBox);

    // Option: clear and repopulate so UI exactly reflects server snapshot.
    // If you prefer merging/upserting only, change this behavior.
    try {
      await box.clear();
    } catch (e) {
      debugPrint('saveMonthlyReportsFromServer: box.clear failed: $e');
    }

    for (final item in docs) {
      try {
        MonthlyReport? rep;
        if (item is MonthlyReport) {
          rep = item;
        } else if (item is Map<String, dynamic>) {
          // Prefer model-level fromJson if available
          try {
            rep = MonthlyReport.fromJson(item);
          } catch (_) {
            // Fallback mapping
            final branch = (item['branch'] ?? item['Branch'] ?? '').toString();
            DateTime date = DateTime.now();
            if (item['date'] != null) {
              try {
                date = DateTime.parse(item['date'].toString());
              } catch (_) {}
            }
            double collected = 0.0;
            try {
              final c = item['collected'] ?? item['collectedAmount'] ?? item['totalCollected'] ?? item['collectedForOther'] ?? 0;
              if (c is num) {
                collected = c.toDouble();
              } else if (c is String) collected = double.tryParse(c.replaceAll(',', '')) ?? 0.0;
            } catch (_) {}
            DateTime createdAt = DateTime.now();
            DateTime updatedAt = DateTime.now();
            try {
              if (item['createdAt'] != null) createdAt = DateTime.parse(item['createdAt'].toString());
            } catch (_) {}
            try {
              if (item['updatedAt'] != null) updatedAt = DateTime.parse(item['updatedAt'].toString());
            } catch (_) {}

            // Build minimal MonthlyReport — adapt fields if your model is different
            rep = MonthlyReport(
              branch: branch,
              date: DateTime(date.year, date.month, 1),
              expected: (item['expected'] is num) ? (item['expected'] as num).toDouble() : (double.tryParse((item['expected'] ?? '').toString()) ?? 0.0),
              collected: collected,
              inputs: (item['inputs'] is num) ? (item['inputs'] as num).toInt() : (int.tryParse((item['inputs'] ?? '').toString()) ?? 0),
              synced: item['synced'] == true,
              // Use parsed timestamps correctly (no duplicate named args)
              updatedAt: updatedAt,
              createdAt: createdAt, year: null, month: null, totalCollected: null, totalDisbursed: null, totalExpenses: null,
            );
          }
        } else {
          // unsupported shape, skip
          continue;
        }

        // Use key branch::yyyy-MM to keep unique monthly entries per branch and month
        final key = '${rep.branch.trim().toLowerCase()}::${rep.date.year.toString().padLeft(4, '0')}-${rep.date.month.toString().padLeft(2, '0')}';
        await box.put(key, rep);
      } catch (e) {
        debugPrint('saveMonthlyReportsFromServer: failed to save item: $e');
        continue;
      }
    }

    try {
      await box.flush();
    } catch (e) {
      debugPrint('saveMonthlyReportsFromServer: box.flush failed: $e');
    }
  }

  static ValueListenable<Box<MonthlyReport>> getMonthlyReportsListenable() {
    if (!Hive.isBoxOpen(_monthlyBox)) throw Exception('monthly_reports box not open. Call RemoteStorage.ensureInitialized() earlier.');
    return Hive.box<MonthlyReport>(_monthlyBox).listenable();
  }

  static List<MonthlyReport> getMonthlyReportsSnapshot() {
    if (!Hive.isBoxOpen(_monthlyBox)) return <MonthlyReport>[];
    final box = Hive.box<MonthlyReport>(_monthlyBox);
    return box.values.toList().cast<MonthlyReport>();
  }

  /// Fetch monthly reports from server and persist into local Hive (monthly_reports).
  /// Returns parsed list of MonthlyReport objects saved locally.
  static Future<List<MonthlyReport>> fetchAndCacheMonthlyReports() async {
    await ensureInitialized();
    try {
      final conn = await Connectivity().checkConnectivity();
      if (conn == ConnectivityResult.none) {
        debugPrint('fetchAndCacheMonthlyReports: no network connectivity');
        return getMonthlyReportsSnapshot();
      }
    } catch (e) {
      debugPrint('fetchAndCacheMonthlyReports: connectivity check failed: $e');
    }

    try {
      final resp = await ApiService.fetchAllMonthlyReports();
      // ignore: unnecessary_type_check
      if (resp is List) {
        await saveMonthlyReportsFromServer(resp);
        return getMonthlyReportsSnapshot();
      } else {
        debugPrint('fetchAndCacheMonthlyReports: unexpected server response type: ${resp.runtimeType}');
        return getMonthlyReportsSnapshot();
      }
    } catch (e) {
      debugPrint('fetchAndCacheMonthlyReports failed: $e');
      return getMonthlyReportsSnapshot();
    }
  }

  // ---------------- Utility ----------------
  static Future<String?> getUsername() async {
    // Implement reading saved username/email from Hive or secure storage if you use it.
    return null;
  }
}
