// Direct Supabase report sync with Hive offline queue.
// Daily/monthly report sync uses Supabase only.

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'package:daml/models/report_model.dart';
import 'package:daml/models/monthly_report_model.dart';
import 'package:daml/services/local_storage.dart';
import 'package:daml/services/supabase_daml_service.dart';

class SyncService {
  SyncService();

  void dispose() {}

  bool _offlineResult(dynamic result) {
    if (result is Iterable) {
      return result.isEmpty || result.every((e) => e == ConnectivityResult.none);
    }
    return result == ConnectivityResult.none;
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return !_offlineResult(result);
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> testConnections() async {
    final online = await _hasInternet();
    if (!online) {
      return {
        'internet': false,
        'server': false,
        'message': "You're currently offline. Changes will sync automatically when you're back online.",
      };
    }

    try {
      await SupabaseDamlService.ensureReady();
      return {
        'internet': true,
        'server': true,
        'message': 'Online and connected to Supabase',
      };
    } catch (_) {
      return {
        'internet': true,
        'server': false,
        'message': 'Internet is available, but cloud sync is temporarily unavailable.',
      };
    }
  }

  DateTime _day(DateTime d) => DateTime.utc(d.toUtc().year, d.toUtc().month, d.toUtc().day);
  DateTime _month(DateTime d) => DateTime.utc(d.toUtc().year, d.toUtc().month, 1);

  Future<void> syncReports({int retryCount = 0}) async {
    await LocalStorage.ensureInitialized();
    if (!await _hasInternet()) {
      throw Exception("You're offline. Reports remain safely saved on this device.");
    }

    final pending = LocalStorage.getAllReports().where((r) => !r.synced).toList();
    for (final report in pending) {
      await SupabaseDamlService.saveDailyReport(report.toMap());
      await LocalStorage.saveReport(report.copyWith(synced: true, date: _day(report.date)));
    }
    if (kDebugMode) debugPrint('✅ Supabase daily sync: ${pending.length} report(s)');
  }

  Future<List<DailyReport>> fetchReportsFromServer() async {
    await SupabaseDamlService.ensureReady();
    final rows = await SupabaseDamlService.fetchDailyReports();
    return rows.map((row) => DailyReport.fromMap(row)).toList();
  }

  Future<void> pullReports() async {
    await LocalStorage.ensureInitialized();
    if (!await _hasInternet()) {
      throw Exception("You're offline. Showing the latest reports stored on this device.");
    }

    final cloud = await fetchReportsFromServer();
    for (final report in cloud) {
      final normalized = report.copyWith(synced: true, date: _day(report.date));
      final local = LocalStorage.getReportByBranchAndDate(normalized.branch, normalized.date);
      if (local == null || normalized.updatedAt.isAfter(local.updatedAt)) {
        await LocalStorage.saveReport(normalized);
      }
    }
  }

  Future<void> fullSync() async {
    await LocalStorage.ensureInitialized();
    if (!await _hasInternet()) {
      throw Exception("You're offline. Changes will sync automatically when you're back online.");
    }
    await syncReports();
    await syncMonthlyReports();
    await pullReports();
    await pullMonthlyReports();
  }

  Future<void> deleteReport(DailyReport report, {int retryCount = 0}) async {
    await LocalStorage.ensureInitialized();
    if (!await _hasInternet()) {
      throw Exception("You're offline. Deletion can be retried when you're back online.");
    }
    await SupabaseDamlService.deleteDailyReport(branch: report.branch, date: report.date);
    await LocalStorage.deleteByBranchAndDate(report.branch, _day(report.date));
  }

  Future<void> syncMonthlyReports({int retryCount = 0}) async {
    await LocalStorage.ensureInitialized();
    if (!await _hasInternet()) {
      throw Exception("You're offline. Monthly reports remain safely saved on this device.");
    }

    final pending = LocalStorage.getAllMonthlyReports().where((m) => !m.synced).toList();
    for (final report in pending) {
      await SupabaseDamlService.saveMonthlyReport(report.toJson());
      await LocalStorage.saveMonthlyReport(
        report.copyWith(synced: true, date: _month(report.date), updatedAt: DateTime.now()),
      );
    }
    if (kDebugMode) debugPrint('✅ Supabase monthly sync: ${pending.length} report(s)');
  }

  Future<bool> pushMonthlyReport(MonthlyReport report, {int retryCount = 0}) async {
    await LocalStorage.ensureInitialized();
    if (!await _hasInternet()) {
      await LocalStorage.saveMonthlyReport(report.copyWith(synced: false));
      return false;
    }
    await SupabaseDamlService.saveMonthlyReport(report.toJson());
    await LocalStorage.saveMonthlyReport(
      report.copyWith(synced: true, date: _month(report.date), updatedAt: DateTime.now()),
    );
    return true;
  }

  Future<List<MonthlyReport>> fetchMonthlyReportsFromServer() async {
    await SupabaseDamlService.ensureReady();
    final rows = await SupabaseDamlService.fetchMonthlyReports();
    return rows.map((row) => MonthlyReport.fromJson(row)).toList();
  }

  Future<void> pullMonthlyReports() async {
    await LocalStorage.ensureInitialized();
    if (!await _hasInternet()) {
      throw Exception("You're offline. Showing the latest monthly reports stored on this device.");
    }

    final cloud = await fetchMonthlyReportsFromServer();
    for (final report in cloud) {
      final normalized = report.copyWith(
        synced: true,
        date: _month(report.date),
        updatedAt: report.updatedAt,
      );
      final local = LocalStorage.getMonthlyReportByBranchAndMonth(normalized.branch, normalized.date);
      if (local == null || normalized.updatedAt.isAfter(local.updatedAt)) {
        await LocalStorage.saveMonthlyReport(normalized);
      }
    }
  }

  Future<void> deleteMonthlyReport(MonthlyReport report, {int retryCount = 0}) async {
    await LocalStorage.ensureInitialized();
    if (!await _hasInternet()) {
      throw Exception("You're offline. Deletion can be retried when you're back online.");
    }
    await SupabaseDamlService.deleteMonthlyReport(branch: report.branch, date: report.date);
    await LocalStorage.deleteMonthlyByBranchAndMonth(report.branch, _month(report.date));
  }
}
