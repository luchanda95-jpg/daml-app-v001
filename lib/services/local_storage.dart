// ignore_for_file: unnecessary_type_check, curly_braces_in_flow_control_structures, prefer_void_to_null, no_leading_underscores_for_local_identifiers

import 'package:daml/models/monthly_report_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../models/report_model.dart';

class LocalStorage {
  static late Box<DailyReport> _reportsBox;
  // dynamic/untyped boxes to tolerate older on-disk shapes
  static late Box<dynamic> _branchCommentsBox;
  static late Box<dynamic> _zanacoDistributionsBox;

  // monthly reports
  static late Box<MonthlyReport> _monthlyReportsBox;

  // Simple session keys (kept minimal for compatibility)
  static const _keyUsername = 'username';
  static const _keyRole = 'role';
  static const _keyIsLoggedIn = 'is_logged_in';

  // Guards to prevent double-init and to allow callers to wait for init
  static bool _hiveInited = false;
  static bool _initialized = false;
  static bool get initialized => _initialized;

  /// Initialize Hive and open boxes. Safe to call multiple times.
  static Future<void> init() async {
    try {
      if (!_hiveInited) {
        final dir = await getApplicationDocumentsDirectory();
        await Hive.initFlutter(dir.path);
        _hiveInited = true;
      }

      // Register adapters if not already registered
      try {
        if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(DailyReportAdapter());
      } catch (_) {}
      try {
        if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(MapAdapter());
      } catch (_) {}
      try {
        if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(MonthlyReportAdapter());
      } catch (_) {}

      await _openBoxes();

      // Migrations + defaults for reports only
      await migrateReports();

      // mark initialized last
      _initialized = true;
    } catch (e) {
      debugPrint('LocalStorage initialization error: $e');
      rethrow;
    }
  }

  /// Ensure LocalStorage is initialized. Safe to call from any async context.
  static Future<void> ensureInitialized() async {
    if (!_initialized) await init();
  }

  static Future<void> _openBoxes() async {
    // Reports box
    try {
      _reportsBox = await Hive.openBox<DailyReport>('reports');
    } catch (e) {
      debugPrint('LocalStorage: reports box open failed, deleting and reopening. Error: $e');
      await Hive.deleteBoxFromDisk('reports');
      _reportsBox = await Hive.openBox<DailyReport>('reports');
    }

    // Branch comments (dynamic)
    try {
      _branchCommentsBox = await Hive.openBox('branch_comments');
    } catch (e) {
      debugPrint('LocalStorage: branch_comments box open failed, deleting and reopening. Error: $e');
      await Hive.deleteBoxFromDisk('branch_comments');
      _branchCommentsBox = await Hive.openBox('branch_comments');
    }

    // Monthly reports
    try {
      _monthlyReportsBox = await Hive.openBox<MonthlyReport>('monthly_reports');
    } catch (e) {
      debugPrint('LocalStorage: monthly_reports box open failed, deleting and reopening. Error: $e');
      await Hive.deleteBoxFromDisk('monthly_reports');
      _monthlyReportsBox = await Hive.openBox<MonthlyReport>('monthly_reports');
    }

    // Zanaco distributions (dynamic)
    try {
      _zanacoDistributionsBox = await Hive.openBox('zanaco_distributions');
    } catch (e) {
      debugPrint('LocalStorage: zanaco_distributions open failed, attempting delete+reopen. Error: $e');
      try {
        await Hive.deleteBoxFromDisk('zanaco_distributions');
      } catch (_) {}
      _zanacoDistributionsBox = await Hive.openBox('zanaco_distributions');
    }
  }

  /// Migrate + normalize existing reports: normalize dates to UTC-midnight and coerce maps
  static Future<void> migrateReports() async {
    try {
      final keys = _reportsBox.keys.cast<dynamic>().toList();
      for (var key in keys) {
        final old = _reportsBox.get(key);
        if (old == null) continue;

        // Normalize date to UTC midnight
        final normalizedDate = _normalizeToUtcMidnight(old.date);

        // Coerce loanCounts -> Map<String,int>
        final fixedLoanCounts = <String, int>{};
        if (old.loanCounts != null) {
          old.loanCounts!.forEach((k, v) {
            final keyStr = k.toString();
            final val = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
            fixedLoanCounts[keyStr] = val;
          });
        }

        // Coerce opening/closing balances -> Map<String,double>
        Map<String, double>? fixMap(Map? maybe) {
          if (maybe == null) return null;
          final out = <String, double>{};
          maybe.forEach((k, v) {
            final keyStr = k.toString();
            if (v is num) {
              out[keyStr] = v.toDouble();
            } else if (v is String) {
              out[keyStr] = double.tryParse(v) ?? 0.0;
            } else {
              out[keyStr] = 0.0;
            }
          });
          return out.isEmpty ? null : out;
        }

        // Coerce zanacoApplied -> Map<String,bool>
        Map<String, bool>? fixZanacoMap(Map? maybe) {
          if (maybe == null) return null;
          final out = <String, bool>{};
          maybe.forEach((k, v) {
            final keyStr = k.toString();
            if (v is bool) {
              out[keyStr] = v;
            } else if (v is num) out[keyStr] = (v != 0);
            else if (v is String) {
              final s = v.toLowerCase();
              out[keyStr] = (s == 'true' || s == '1' || s == 'yes');
            } else out[keyStr] = false;
          });
          return out.isEmpty ? null : out;
        }

        final migrated = DailyReport(
          branch: old.branch,
          date: normalizedDate,
          openingBalances: fixMap(old.openingBalances),
          loanCounts: fixedLoanCounts.isEmpty ? null : fixedLoanCounts,
          closingBalances: fixMap(old.closingBalances),
          totalDisbursed: old.totalDisbursed,
          totalCollected: old.totalCollected,
          collectedForOtherBranches: old.collectedForOtherBranches,
          pettyCash: old.pettyCash,
          expenses: old.expenses,
          synced: old.synced,
          updatedAt: old.updatedAt,
          zanacoApplied: fixZanacoMap(old.zanacoApplied ?? {}), totalLoans: null,
        );

        await _reportsBox.put(key, migrated);
      }
    } catch (e) {
      debugPrint('migrateReports error: $e');
    }
  }

  // === Helpers ===
  static DateTime _normalizeToUtcMidnight(DateTime d) {
    final utc = d.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  static DateTime _normalizeToMonthStartUtc(DateTime d) {
    final utc = d.toUtc();
    return DateTime.utc(utc.year, utc.month, 1);
  }

  static bool _sameDay(DateTime a, DateTime b) {
    final au = a.toUtc();
    final bu = b.toUtc();
    return au.year == bu.year && au.month == bu.month && au.day == bu.day;
  }

  /// Normalize branch key for matching (case-insensitive + trimmed).
  static String _normalizeBranch(String b) => b.toString().toLowerCase().trim();

  static dynamic _findKeyByBranchAndDate(String branch, DateTime date) {
    final normalizedDate = _normalizeToUtcMidnight(date);
    final branchNorm = _normalizeBranch(branch);
    return _reportsBox.keys.cast<dynamic>().firstWhere(
      (k) {
        final r = _reportsBox.get(k);
        if (r == null) return false;
        return _normalizeBranch(r.branch) == branchNorm && _sameDay(r.date, normalizedDate);
      },
      orElse: () => null,
    );
  }

  static dynamic _findMonthlyKeyByBranchAndMonth(String branch, DateTime monthDate) {
    final normalized = _normalizeToMonthStartUtc(monthDate);
    final branchNorm = _normalizeBranch(branch);
    return _monthlyReportsBox.keys.cast<dynamic>().firstWhere(
      (k) {
        final r = _monthly_reports_box_getter(k);
        if (r == null) return false;
        final rMonth = _normalizeToMonthStartUtc(r.date);
        return _normalizeBranch(r.branch) == branchNorm && rMonth.year == normalized.year && rMonth.month == normalized.month;
      },
      orElse: () => null,
    );
  }

  // Helper to safely get monthly report (avoids direct access issues)
  // ignore: non_constant_identifier_names
  static MonthlyReport? _monthly_reports_box_getter(dynamic key) {
    try {
      return _monthlyReportsBox.get(key);
    } catch (_) {
      return null;
    }
  }

  // === Report Methods ===
  static ValueListenable<Box<DailyReport>> getReportsListenable() {
    if (!Hive.isBoxOpen('reports')) {
      throw StateError('LocalStorage not initialized or "reports" box is not open. Call LocalStorage.init() before requesting listenables.' );
    }
    return _reportsBox.listenable();
  }

  static Future<void> saveReport(DailyReport report) async {
    final normalized = report.copyWith(date: _normalizeToUtcMidnight(report.date));

    Map<String, double>? safeMapD(Map<String, double>? m) {
      if (m == null) return null;
      final out = <String, double>{};
      m.forEach((k, v) {
        final keyStr = k.toString();
        out[keyStr] = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
      });
      return out.isEmpty ? null : out;
    }

    Map<String, int>? safeMapI(Map<String, int>? m) {
      if (m == null) return null;
      final out = <String, int>{};
      m.forEach((k, v) {
        final keyStr = k.toString();
        out[keyStr] = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
      });
      return out.isEmpty ? null : out;
    }

    final safeReport = normalized.copyWith(
      openingBalances: safeMapD(normalized.openingBalances),
      closingBalances: safeMapD(normalized.closingBalances),
      loanCounts: safeMapI(normalized.loanCounts),
    );

    final existingKey = _findKeyByBranchAndDate(safeReport.branch, safeReport.date);
    if (existingKey != null) {
      await _reportsBox.put(existingKey, safeReport);
    } else {
      await _reportsBox.add(safeReport);
    }
  }

  static Future<void> deleteReport(DailyReport report) async {
    final normalizedDate = _normalizeToUtcMidnight(report.date);
    final key = _findKeyByBranchAndDate(report.branch, normalizedDate);
    if (key != null) {
      await _reportsBox.delete(key);
      debugPrint('LocalStorage: deleted report for ${report.branch} @ $normalizedDate');
    } else {
      debugPrint('LocalStorage: report to delete not found for ${report.branch} @ $normalizedDate');
    }
  }

  static Future<void> deleteByBranchAndDate(String branch, DateTime date) async {
    final normalized = _normalizeToUtcMidnight(date);
    final key = _findKeyByBranchAndDate(branch, normalized);
    if (key != null) {
      await _reportsBox.delete(key);
      debugPrint('LocalStorage: deleted report for $branch @ $normalized');
    } else {
      debugPrint('LocalStorage: no report found to delete for $branch @ $normalized');
    }
  }

  static List<DailyReport> getAllReports() => _reportsBox.values.toList();

  static List<DailyReport> getBranchReports(String branch) =>
      getAllReports().where((r) => _normalizeBranch(r.branch) == _normalizeBranch(branch)).toList();

  static DailyReport? getReportByBranchAndDate(String branch, DateTime date) {
    final key = _findKeyByBranchAndDate(branch, date);
    if (key != null) return _reportsBox.get(key);
    return null;
  }

  static List<dynamic> findEmptyBranchKeys() {
    final bad = <dynamic>[];
    for (var key in _reportsBox.keys) {
      final r = _reportsBox.get(key);
      if (r == null) continue;
      if (r.branch.trim().isEmpty) bad.add(key);
    }
    return bad;
  }

  static Future<void> deleteEmptyBranchReports() async {
    final bad = findEmptyBranchKeys();
    for (var key in bad) {
      await _reportsBox.delete(key);
    }
  }

  // === Branch Comments ===
  static Future<void> saveBranchComment(String branchName, String comment, String author) async {
    try {
      final raw = _branchCommentsBox.get(branchName);

      Map<String, dynamic> data;
      if (raw == null) {
        data = {'comments': []};
      } else if (raw is Map) {
        data = Map<String, dynamic>.fromEntries(raw.entries.map((e) => MapEntry(e.key.toString(), e.value)));
        if (data['comments'] == null || data['comments'] is! List) data['comments'] = [];
      } else {
        data = {'comments': []};
      }

      final comments = List.from(data['comments'] as List);
      comments.add({
        'author': author,
        'comment': comment,
        'timestamp': DateTime.now().toIso8601String(),
      });

      final toStore = <String, dynamic>{'comments': comments};
      await _branchCommentsBox.put(branchName, toStore);
    } catch (e) {
      debugPrint('saveBranchComment error: $e');
      rethrow;
    }
  }

  static List<Map<String, dynamic>> getBranchComments(String branchName) {
    try {
      final raw = _branchCommentsBox.get(branchName);
      Map<String, dynamic> data;
      if (raw == null) {
        data = {'comments': []};
      } else if (raw is Map) {
        data = Map<String, dynamic>.fromEntries(raw.entries.map((e) => MapEntry(e.key.toString(), e.value)));
      } else {
        data = {'comments': []};
      }

      final rawList = (data['comments'] as List?) ?? [];

      final normalized = <Map<String, dynamic>>[];
      for (var item in rawList) {
        if (item is Map) {
          normalized.add(Map<String, dynamic>.fromEntries(item.entries.map((e) => MapEntry(e.key.toString(), e.value))));
        } else {
          normalized.add(<String, dynamic>{});
        }
      }
      return normalized;
    } catch (e) {
      debugPrint('getBranchComments error: $e');
      return <Map<String, dynamic>>[];
    }
  }

  static ValueListenable<Box<dynamic>> getBranchCommentsListenable() {
    if (!Hive.isBoxOpen('branch_comments')) {
      throw StateError('LocalStorage not initialized or "branch_comments" box is not open. Call LocalStorage.init() before requesting listenables.' );
    }
    return _branchCommentsBox.listenable();
  }

  // === Simple Session Helpers (kept minimal) ===

  /// Save a very small session footprint in SharedPreferences (keeps compatibility
  /// with screens that simply check username/is_logged_in). This intentionally
  /// does NOT implement credential storage or verification.
  static Future<void> saveLoginSession({ required String username, required String role }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyUsername, username);
    await prefs.setString(_keyRole, role);
  }

  /// Clear session and close Hive boxes. This does not attempt to manage or delete
  /// credentials (those features were removed).
  static Future<void> clearSession() async {
    try {
      debugPrint('LocalStorage.clearSession: starting');

      // 1) Clear SharedPreferences login flags (if present)
      final prefs = await SharedPreferences.getInstance();
      try {
        await prefs.remove(_keyIsLoggedIn);
        await prefs.remove(_keyUsername);
        await prefs.remove(_keyRole);
      } catch (_) {}

      // 2) Close Hive boxes so next app-start re-opens them cleanly.
      try {
        if (Hive.isBoxOpen('reports')) {
          try { await _reportsBox.close(); } catch (_) {}
        }
        if (Hive.isBoxOpen('branch_comments')) {
          try { await _branchCommentsBox.close(); } catch (_) {}
        }
        if (Hive.isBoxOpen('monthly_reports')) {
          try { await _monthlyReportsBox.close(); } catch (_) {}
        }
        if (Hive.isBoxOpen('zanaco_distributions')) {
          try { await _zanacoDistributionsBox.close(); } catch (_) {}
        }
        try { await Hive.close(); } catch (_) {}
        debugPrint('LocalStorage.clearSession: Hive boxes closed');
      } catch (e) {
        debugPrint('LocalStorage.clearSession: error closing Hive boxes: $e');
      }

      debugPrint('LocalStorage.clearSession: finished');
    } catch (e) {
      debugPrint('LocalStorage.clearSession: unexpected error: $e');
      rethrow;
    }
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  static Future<bool> checkLogin() => isLoggedIn();

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUsername);
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRole);
  }

  // ================= Zanaco / Monthly / Utility methods =================

  static List<MonthlyReport> getMonthlyReports(String branchName) {
    try {
      final branchNorm = _normalizeBranch(branchName);
      return _monthlyReportsBox.values.where((r) => _normalizeBranch(r.branch) == branchNorm).toList();
    } catch (e) {
      debugPrint('getMonthlyReports error: $e');
      return <MonthlyReport>[];
    }
  }

  static Future<void> saveMonthlyReport(MonthlyReport report) async {
    // ensure the month start is normalized and keep or set updatedAt sensibly
    final normalized = report.copyWith(
      date: _normalizeToMonthStartUtc(report.date),
      updatedAt: report.updatedAt, createdAt: null,
    );

    final existingKey = _findMonthlyKeyByBranchAndMonth(normalized.branch, normalized.date);
    if (existingKey != null) {
      await _monthlyReportsBox.put(existingKey, normalized);
      debugPrint('LocalStorage: updated monthly report for ${normalized.branch} @ ${normalized.date}');
    } else {
      await _monthlyReportsBox.add(normalized);
      debugPrint('LocalStorage: added monthly report for ${normalized.branch} @ ${normalized.date}');
    }
  }

  static ValueListenable<Box<MonthlyReport>> getMonthlyReportsListenable() {
    if (!Hive.isBoxOpen('monthly_reports')) {
      throw StateError('LocalStorage not initialized or "monthly_reports" box is not open. Call LocalStorage.init() before requesting listenables.' );
    }
    return _monthlyReportsBox.listenable();
  }

  static List<MonthlyReport> getAllMonthlyReports() {
    try {
      return _monthlyReportsBox.values.toList();
    } catch (e) {
      debugPrint('getAllMonthlyReports error: $e');
      return <MonthlyReport>[];
    }
  }

  static MonthlyReport? getMonthlyReportByBranchAndMonth(String branch, DateTime monthDate) {
    try {
      final key = _findMonthlyKeyByBranchAndMonth(branch, monthDate);
      if (key != null) return _monthlyReportsBox.get(key);
      return null;
    } catch (e) {
      debugPrint('getMonthlyReportByBranchAndMonth error: $e');
      return null;
    }
  }

  static Future<void> deleteMonthlyByBranchAndMonth(String branch, DateTime monthDate) async {
    try {
      final normalized = _normalizeToMonthStartUtc(monthDate);
      final key = _findMonthlyKeyByBranchAndMonth(branch, normalized);
      if (key != null) {
        await _monthlyReportsBox.delete(key);
        debugPrint('LocalStorage: deleted monthly report for $branch @ $normalized');
      } else {
        debugPrint('LocalStorage: no monthly report found to delete for $branch @ $normalized');
      }
    } catch (e) {
      debugPrint('deleteMonthlyByBranchAndMonth error: $e');
    }
  }

  // === Zanaco Distributions support ===
  static Future<void> _ensureZanacoBoxOpen() async {
    if (Hive.isBoxOpen('zanaco_distributions')) {
      _zanacoDistributionsBox = Hive.box('zanaco_distributions');
      return;
    }
    try {
      _zanacoDistributionsBox = await Hive.openBox('zanaco_distributions');
    } catch (e) {
      try {
        await Hive.deleteBoxFromDisk('zanaco_distributions');
      } catch (_) {}
      _zanacoDistributionsBox = await Hive.openBox('zanaco_distributions');
    }
  }

  static Future<void> saveZanacoDistribution(
    Map<String, dynamic> record,
    String fromBranch,
    Map<String, Map<String, double>> allocations,
  ) async {
    await _ensureZanacoBoxOpen();

    final toStore = <String, dynamic>{};
    // copy provided record entries (normalize keys)
    record.forEach((k, v) => toStore[k.toString()] = v);

    // ensure required fields
    toStore['fromBranch'] = fromBranch;
    if (toStore['date'] == null) toStore['date'] = DateTime.now().toIso8601String();

    // Normalize allocations nested maps to Map<String, Map<String, dynamic>>
    // -> branch keys and channel keys are stored normalized (lowercase, trimmed)
    final normAlloc = <String, Map<String, dynamic>>{};
    allocations.forEach((branch, chMap) {
      final branchKeyNorm = branch.toString().toLowerCase().trim();
      final inner = <String, dynamic>{};
      chMap.forEach((ch, amt) {
        final chKeyNorm = ch.toString().toLowerCase().trim();
        inner[chKeyNorm] = (amt is num) ? amt.toDouble() : double.tryParse(amt.toString()) ?? 0.0;
      });
      if (inner.isNotEmpty) normAlloc[branchKeyNorm] = inner;
    });
    toStore['allocations'] = normAlloc;
    toStore['createdAt'] = toStore['createdAt'] ?? DateTime.now().toIso8601String();

    debugPrint('=== SAVING ZANACO DISTRIBUTION ===');
    debugPrint('From Branch: $fromBranch');
    debugPrint('Allocations: $normAlloc');
    debugPrint('Date: ${toStore['date']}');

    // persist distribution record
    await _zanacoDistributionsBox.add(toStore);

    // --- Apply allocations into daily reports (idempotent) ---
    DateTime dt;
    final dRaw = toStore['date'];
    if (dRaw is DateTime) {
      dt = dRaw;
    } else if (dRaw is String) dt = DateTime.tryParse(dRaw) ?? DateTime.now();
    else dt = DateTime.now();
    final normalizedDate = _normalizeToUtcMidnight(dt);

    // convert normAlloc to Map<String, Map<String,double>>
    final allocDouble = <String, Map<String, double>>{};
    normAlloc.forEach((branch, inner) {
      final outInner = <String, double>{};
      inner.forEach((ch, amt) {
        if (amt is num) {
          outInner[ch.toString()] = amt.toDouble();
        } else if (amt is String) outInner[ch.toString()] = double.tryParse(amt) ?? 0.0;
        else outInner[ch.toString()] = 0.0;
      });
      if (outInner.isNotEmpty) allocDouble[branch.toString()] = outInner;
    });

    try {
      await _applyZanacoAllocationsToReports(normalizedDate, allocDouble);
    } catch (e) {
      debugPrint('applyZanacoAllocationsToReports error: $e');
    }

    debugPrint('=== DISTRIBUTION SAVED SUCCESSFULLY ===');
  }

  static Future<void> _applyZanacoAllocationsToReports(
    DateTime normalizedDate,
    Map<String, Map<String, double>> allocations,
  ) async {
    // helper: find an existing key in a map that matches `key` case-insensitively,
    // otherwise return `key` (so we preserve existing key names when possible).
    String _findExistingKeyCaseInsensitive(Map m, String key) {
      final keyNorm = key.toString().toLowerCase().trim();
      for (final existingKey in m.keys) {
        try {
          if (existingKey.toString().toLowerCase().trim() == keyNorm) return existingKey.toString();
        } catch (_) {}
      }
      return key;
    }

    for (final entry in allocations.entries) {
      final targetBranch = entry.key.toString();
      final channelMap = entry.value;

      final key = _findKeyByBranchAndDate(targetBranch, normalizedDate);

      if (key != null) {
        final existing = _reportsBox.get(key);
        if (existing == null) continue;

        // copy current openings (coerce types) preserving stored key names
        final currentOpenings = <String, double>{};
        (existing.openingBalances ?? {}).forEach((k, v) {
          currentOpenings[k.toString()] = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
        });

        // copy or initialize zanacoApplied map, normalize stored keys to lowercase
        final zanacoAppliedMap = <String, bool>{};
        (existing.zanacoApplied ?? {}).forEach((k, v) {
          try {
            zanacoAppliedMap[k.toString().toLowerCase().trim()] = v == true;
          } catch (_) {}
        });

        // add each channel amount to the opening balance for that channel
        channelMap.forEach((ch, amt) {
          final channelKeyOriginal = ch.toString();
          final channelKeyLower = channelKeyOriginal.toLowerCase().trim();

          // Determine if this channel was already applied (case-insensitive)
          final alreadyApplied = zanacoAppliedMap[channelKeyLower] == true;
          if (!alreadyApplied) {
            // find matching opening key to update (preserve case if present), otherwise use normalized lower-case key
            final matchedOpeningKey = _findExistingKeyCaseInsensitive(currentOpenings, channelKeyOriginal);
            final prev = currentOpenings[matchedOpeningKey] ?? 0.0;
            currentOpenings[matchedOpeningKey] = prev + amt;
            // mark applied using normalized key
            zanacoAppliedMap[channelKeyLower] = true;
          }
        });

        final updated = existing.copyWith(
          openingBalances: currentOpenings.isEmpty ? null : currentOpenings,
          zanacoApplied: zanacoAppliedMap.isEmpty ? null : zanacoAppliedMap,
        );
        await _reportsBox.put(key, updated);
      } else {
        // create a fresh report for that branch/date with these openings and zanacoApplied set
        final newOpenings = <String, double>{};
        final appliedMap = <String, bool>{};
        channelMap.forEach((ch, amt) {
          final chKey = ch.toString().toLowerCase().trim();
          newOpenings[chKey] = (amt);
          appliedMap[chKey] = true;
        });

        final newReport = DailyReport(
          branch: targetBranch,
          date: normalizedDate,
          openingBalances: newOpenings.isEmpty ? null : newOpenings,
          loanCounts: null,
          closingBalances: null,
          totalDisbursed: 0.0,
          totalCollected: 0.0,
          collectedForOtherBranches: 0.0,
          pettyCash: 0.0,
          expenses: 0.0,
          synced: false,
          zanacoApplied: appliedMap.isEmpty ? null : appliedMap, totalLoans: null,
        );

        await _reportsBox.add(newReport);
      }
    }

    if (Hive.isBoxOpen('reports')) await _reportsBox.flush();
  }

  static List<Map<String, dynamic>> getAllZanacoDistributions() {
    try {
      if (!Hive.isBoxOpen('zanaco_distributions')) return [];
      final items = _zanacoDistributionsBox.values.toList();
      final normalized = <Map<String, dynamic>>[];
      for (var item in items) {
        if (item is Map) {
          normalized.add(Map<String, dynamic>.fromEntries(item.entries.map((e) => MapEntry(e.key.toString(), e.value))));
        } else {
          normalized.add(<String, dynamic>{});
        }
      }
      return normalized;
    } catch (e) {
      debugPrint('getAllZanacoDistributions error: $e');
      return <Map<String, dynamic>>[];
    }
  }

  /// Returns a listenable for the zanaco_distributions box, or null if box isn't open yet.
  /// This avoids throwing when callers request the listenable during app init.
  static ValueListenable<Box<dynamic>>? getZanacoDistributionsListenable() {
    try {
      if (Hive.isBoxOpen('zanaco_distributions')) {
        return Hive.box('zanaco_distributions').listenable();
      }
    } catch (e) {
      debugPrint('getZanacoDistributionsListenable error: $e');
    }
    return null;
  }

  static Future<void> deleteZanacoDistribution(dynamic key) async {
    await _ensureZanacoBoxOpen();
    await _zanacoDistributionsBox.delete(key);
  }

  // Add this method to debug distribution contents
  static void debugPrintDistributions() {
    try {
      if (!Hive.isBoxOpen('zanaco_distributions')) {
        debugPrint('Zanaco distributions box is not open');
        return;
      }
    final items = _zanacoDistributionsBox.values.toList();
    debugPrint('=== ZANACO DISTRIBUTIONS DEBUG ===');
    debugPrint('Total distributions: ${items.length}');
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is Map) {
        final map = Map<String, dynamic>.fromEntries(
          item.entries.map((e) => MapEntry(e.key.toString(), e.value))
        );
        debugPrint('Distribution $i:');
        debugPrint('  - Date: ${map['date']}');
        debugPrint('  - From Branch: ${map['fromBranch']}');
        debugPrint('  - Allocations: ${map['allocations']}');
      } else {
        debugPrint('Distribution $i: (invalid format) $item');
      }
    }
    debugPrint('=== END DISTRIBUTIONS DEBUG ===');
    } catch (e) {
      debugPrint('Error printing distributions: $e');
    }
  }

  /// Returns total allocation amount (for given channel) that was allocated to [branchName]
  /// on [normalizedDate] (UTC-midnight match). Channel lookup is case-insensitive.
  static double getZanacoAllocForBranchOnDate(DateTime normalizedDate, String channel, String branchName) {
    try {
      if (!Hive.isBoxOpen('zanaco_distributions')) {
        debugPrint('Zanaco distributions box not open');
        return 0.0;
      }
      
      double total = 0.0;
      final branchNorm = _normalizeBranch(branchName);
      final channelNorm = channel.toString().toLowerCase().trim();

      debugPrint('=== ZANACO ALLOC QUERY ===');
      debugPrint('Looking for: date=$normalizedDate, channel=$channelNorm, branch=$branchNorm');

      final items = _zanacoDistributionsBox.values.toList();
      debugPrint('Scanning ${items.length} distributions');

      for (var item in items) {
        if (item is! Map) continue;
        
        final map = Map<String, dynamic>.fromEntries(
          item.entries.map((e) => MapEntry(e.key.toString(), e.value))
        );
        
        // Parse date
        DateTime dt;
        final dateRaw = map['date'];
        if (dateRaw is DateTime) {
          dt = dateRaw;
        } else if (dateRaw is String) {
          dt = DateTime.tryParse(dateRaw) ?? DateTime.now();
        } else {
          dt = DateTime.now();
        }

        final itemDate = _normalizeToUtcMidnight(dt);
        if (!_sameDay(itemDate, normalizedDate)) {
          continue;
        }

        debugPrint('Found distribution for target date: ${map['fromBranch']} -> ${map['allocations']}');

        final allocs = map['allocations'];
        if (allocs is! Map) continue;

        // Check each branch in allocations
        for (final allocEntry in allocs.entries) {
          final storedBranchKey = allocEntry.key.toString();
          final storedBranchNorm = _normalizeBranch(storedBranchKey);
          
          debugPrint('  Checking branch: "$storedBranchKey" (normalized: "$storedBranchNorm") vs "$branchNorm"');
          
          if (storedBranchNorm != branchNorm) continue;
          
          debugPrint('  BRANCH MATCH FOUND!');
          
          final branchAlloc = allocEntry.value;
          if (branchAlloc is! Map) continue;

          for (final chEntry in branchAlloc.entries) {
            final storedChKey = chEntry.key.toString().toLowerCase().trim();
            debugPrint('    Checking channel: "$storedChKey" vs "$channelNorm"');
            
            if (storedChKey != channelNorm) continue;
            
            final v = chEntry.value;
            final amount = (v is num) ? v.toDouble() : (v is String) ? double.tryParse(v) ?? 0.0 : 0.0;
            debugPrint('    CHANNEL MATCH! Adding amount: $amount');
            total += amount;
          }
        }
      }

      debugPrint('TOTAL ALLOCATION FOUND: $total');
      debugPrint('=== END ZANACO ALLOC QUERY ===');
      return total;
    } catch (e) {
      debugPrint('getZanacoAllocForBranchOnDate error: $e');
      return 0.0;
    }
  }

  // === Utility: check if box exists by name (sync-safe) ===
  static Future<bool> boxExists(String name) async {
    try {
      return await Hive.boxExists(name);
    } catch (_) {
      return false;
    }
  }
}

// ignore: unintended_html_in_doc_comment
/// Optional: Hive adapter for Map<String, dynamic>
/// Keep if you store maps directly; otherwise optional.
class MapAdapter extends TypeAdapter<Map<String, dynamic>> {
  @override
  final int typeId = 11;
  @override
  Map<String, dynamic> read(BinaryReader reader) {
    final length = reader.readInt();
    final map = <String, dynamic>{};
    for (int i = 0; i < length; i++) {
      final key = reader.readString();
      final value = reader.read();
      map[key] = value;
    }
    return map;
  }

  @override
  void write(BinaryWriter writer, Map<String, dynamic> obj) {
    writer.writeInt(obj.length);
    obj.forEach((key, value) {
      writer.writeString(key);
      writer.write(value);
    });
  }
}