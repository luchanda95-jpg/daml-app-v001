// lib/services/sync_service.dart
// SyncService: uses AuthService.getToken() for Authorization header; robust push/pull + retries.
// Ensure LocalStorage.ensureInitialized() is called before using LocalStorage.

// ignore_for_file: unrelated_type_equality_checks

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:daml/models/report_model.dart';
import 'package:daml/models/monthly_report_model.dart';
import 'package:daml/services/local_storage.dart';
import 'package:daml/services/auth_service.dart';

class SyncService {
  final String baseUrl;
  late final String _apiUrl;
  late final String _reportsUrl;
  late final String _healthUrl;

  late final String _monthlyApiUrl;
  late final String _monthlyUrl;

  final http.Client _client = http.Client();

  // default timeouts (can adjust)
  final Duration _shortTimeout = const Duration(seconds: 10);
  final Duration _longTimeout = const Duration(seconds: 30);

  SyncService({this.baseUrl = 'https://directaccessapi.onrender.com'}) {
    _apiUrl = '$baseUrl/api/sync_reports';
    _reportsUrl = '$baseUrl/api/reports';
    _healthUrl = '$baseUrl/health';

    _monthlyApiUrl = '$baseUrl/api/sync_monthly_reports';
    _monthlyUrl = '$baseUrl/api/monthly_reports';
  }

  void dispose() {
    try {
      _client.close();
    } catch (_) {}
  }

  // ---------- Helpers for headers / auth ----------
  Future<Map<String, String>> _getHeaders() async {
    final token = await AuthService.getToken(); // uses AuthService
    final Map<String, String> headers = {'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  // ---------- Connectivity & health ----------
  Future<bool> _checkInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet = connectivityResult != ConnectivityResult.none;
      debugPrint("🌐 Internet connection: $hasInternet");
      return hasInternet;
    } catch (e) {
      debugPrint("❌ Internet connection check failed: $e");
      return false;
    }
  }

  Future<bool> _checkServerConnection() async {
    try {
      debugPrint("🌐 Testing connection to: $_healthUrl");
      final headers = await _getHeaders();
      final response = await _client.get(Uri.parse(_healthUrl), headers: headers).timeout(_shortTimeout);
      debugPrint("✅ Server connection test: ${response.statusCode}");
      if (response.statusCode == 401) {
        // server reachable but token unauthorized
        debugPrint('⚠️ Server returned 401 during health check. Token may be invalid.');
        return true; // treat server reachable, leave auth handling to callers
      }
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("❌ Server connection test failed: $e");
      return false;
    }
  }

  Future<Map<String, dynamic>> testConnections() async {
    try {
      debugPrint("🧪 Running connection tests...");
      final hasInternet = await _checkInternetConnection();
      if (!hasInternet) {
        return {'internet': false, 'server': false, 'message': 'No internet connection'};
      }
      final serverAvailable = await _checkServerConnection();
      return {
        'internet': true,
        'server': serverAvailable,
        'message': serverAvailable ? 'All connections OK' : 'Internet available but server not reachable'
      };
    } catch (e) {
      debugPrint("❌ Connection test failed: $e");
      return {'internet': false, 'server': false, 'message': 'Connection test failed'};
    }
  }

  // -----------------------
  // Date helpers
  // -----------------------
  DateTime _normalizeToUtcMidnight(DateTime d) {
    final utc = d.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  DateTime _normalizeToUtcMonthStart(DateTime d) {
    final u = d.toUtc();
    return DateTime.utc(u.year, u.month, 1);
  }

  String _dayKey(String branch, DateTime date) {
    final d = _normalizeToUtcMidnight(date);
    return '${branch.trim()}|${d.toIso8601String()}';
  }

  String _monthlyKey(String branch, DateTime monthStart) {
    final d = _normalizeToUtcMonthStart(monthStart);
    return '${branch.trim()}|${d.toIso8601String()}';
  }

  // -----------------------
  // Retry helpers (exponential backoff)
  // -----------------------
  Future<T> _withRetries<T>(Future<T> Function() fn, {int retries = 2, Duration baseDelay = const Duration(seconds: 2)}) async {
    int attempt = 0;
    while (true) {
      try {
        return await fn();
      } catch (e) {
        attempt++;
        if (attempt > retries) rethrow;
        final wait = Duration(milliseconds: baseDelay.inMilliseconds * (1 << (attempt - 1)));
        debugPrint('🔁 Retry #$attempt after ${wait.inSeconds}s due to error: $e');
        await Future.delayed(wait);
      }
    }
  }

  // -----------------------
  // Push local unsynced reports to server
  // -----------------------
  Future<void> syncReports({int retryCount = 0}) async {
    await LocalStorage.ensureInitialized();
    await _withRetries(() => _syncReportsOnce(), retries: 3);
  }

  Future<void> _syncReportsOnce() async {
    debugPrint("🔄 Starting sync push...");

    final hasInternet = await _checkInternetConnection();
    if (!hasInternet) throw Exception("No internet connection available");

    final serverAvailable = await _checkServerConnection();
    if (!serverAvailable) throw Exception("Server not reachable");

    final all = LocalStorage.getAllReports();
    final reports = all.where((r) => !r.synced).toList();

    if (reports.isEmpty) {
      debugPrint("📭 No unsynced reports found.");
      return;
    }

    debugPrint("📦 Preparing ${reports.length} unsynced reports for upload...");

    final mappingLocalKeyToReport = <String, DailyReport>{};
    final jsonReports = reports.map((r) {
      final normalizedDate = _normalizeToUtcMidnight(r.date);
      final key = _dayKey(r.branch, normalizedDate);
      mappingLocalKeyToReport[key] = r;
      return {
        'branch': r.branch,
        'date': normalizedDate.toIso8601String(),
        'openingBalances': r.openingBalances ?? {},
        'loanCounts': r.loanCounts ?? {},
        'closingBalances': r.closingBalances ?? {},
        'totalDisbursed': r.totalDisbursed ?? 0.0,
        'totalCollected': r.totalCollected ?? 0.0,
        'collectedForOtherBranches': r.collectedForOtherBranches ?? 0.0,
        'pettyCash': r.pettyCash ?? 0.0,
        'expenses': r.expenses ?? 0.0,
        'updatedAt': (r.updatedAt).toUtc().toIso8601String(),
        // include localKey for idempotency mapping on server if desired
        'localKey': key,
      };
    }).toList();

    debugPrint("📤 Sending data to server...");
    final headers = await _getHeaders();
    final resp = await _client
        .post(Uri.parse(_apiUrl), headers: headers, body: jsonEncode({'reports': jsonReports}))
        .timeout(_longTimeout);

    if (resp.statusCode == 401) {
      // Token expired / unauthorized
      debugPrint('❌ Sync push returned 401 - token invalid.');
      throw Exception('Unauthorized (401). Please sign in again.');
    }

    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body);
      if (body is Map && body['success'] == true) {
        final List saved = (body['saved'] is List) ? body['saved'] as List : [];

        if (saved.isNotEmpty) {
          final Set<String> savedKeys = saved.map((s) {
            try {
              // ensure s is a map-like object
              if (s is Map) {
                final sMap = Map<String, dynamic>.from(s);
                final dt = DateTime.parse(sMap['date'].toString()).toUtc();
                final key = '${sMap['branch'].toString().trim()}|${DateTime.utc(dt.year, dt.month, dt.day).toIso8601String()}';
                return key;
              }
              return '';
            } catch (_) {
              return '';
            }
          }).where((k) => k.isNotEmpty).toSet();

          int confirmed = 0;
          for (final key in savedKeys) {
            final local = mappingLocalKeyToReport[key];
            if (local != null) {
              final updated = local.copyWith(synced: true, date: _normalizeToUtcMidnight(local.date));
              await LocalStorage.saveReport(updated);
              confirmed++;
            }
          }
          debugPrint("✅ Sync push successful! $confirmed reports confirmed saved (server).");
          return;
        } else {
          for (final r in reports) {
            final updated = r.copyWith(synced: true, date: _normalizeToUtcMidnight(r.date));
            await LocalStorage.saveReport(updated);
          }
          debugPrint("✅ Sync push successful (no saved list). Marked ${reports.length} local reports as synced.");
          return;
        }
      } else {
        final errors = body['errors'] ?? body;
        throw Exception("Server responded with error: $errors");
      }
    } else {
      throw Exception("Server returned ${resp.statusCode}: ${resp.reasonPhrase}");
    }
  }

  // -----------------------
  // Fetch reports from server
  // -----------------------
  Future<List<DailyReport>> fetchReportsFromServer() async {
    await LocalStorage.ensureInitialized();
    try {
      debugPrint("📥 Fetching reports from server...");
      final headers = await _getHeaders();
      final resp = await _client.get(Uri.parse(_reportsUrl), headers: headers).timeout(_longTimeout);

      if (resp.statusCode == 401) {
        throw Exception('Unauthorized (401) while fetching reports');
      }
      if (resp.statusCode != 200) {
        throw Exception("Failed to fetch reports: ${resp.statusCode}");
      }

      final data = jsonDecode(resp.body);
      if (data is! List) {
        throw Exception("Unexpected server response format (expected list)");
      }

      final List<DailyReport> out = [];
      for (final item in data) {
        if (item == null || item is! Map) continue;

        final Map<String, dynamic> itemMap = Map<String, dynamic>.from(item);
        final branch = (itemMap['branch'] ?? '').toString().trim();
        final dateStr = itemMap['date']?.toString();
        if (branch.isEmpty || dateStr == null) {
          debugPrint("⚠️ Skipping server item missing branch/date: $itemMap");
          continue;
        }

        final openingBalances = _toDoubleMap(itemMap['openingBalances']);
        final closingBalances = _toDoubleMap(itemMap['closingBalances']);
        final loanCounts = _toIntMap(itemMap['loanCounts']);

        final totalDisbursed = _numToDouble(itemMap['totalDisbursed']);
        final totalCollected = _numToDouble(itemMap['totalCollected']);
        final collectedForOtherBranches = _numToDouble(itemMap['collectedForOtherBranches']);
        final pettyCash = _numToDouble(itemMap['pettyCash']);
        final expenses = _numToDouble(itemMap['expenses']);
        final updatedAt = DateTime.tryParse(itemMap['updatedAt']?.toString() ?? '') ?? DateTime.now();

        try {
          final parsedDate = DateTime.parse(dateStr);
          final normalized = _normalizeToUtcMidnight(parsedDate);
          final report = DailyReport(
            branch: branch,
            date: normalized,
            openingBalances: openingBalances.isEmpty ? null : openingBalances,
            loanCounts: loanCounts.isEmpty ? null : loanCounts,
            closingBalances: closingBalances.isEmpty ? null : closingBalances,
            totalDisbursed: totalDisbursed,
            totalCollected: totalCollected,
            collectedForOtherBranches: collectedForOtherBranches,
            pettyCash: pettyCash,
            expenses: expenses,
            synced: true,
            updatedAt: updatedAt, totalLoans: null,
          );
          out.add(report);
        } catch (e) {
          debugPrint("⚠️ Skipping server item with invalid date: $itemMap — $e");
          continue;
        }
      }

      debugPrint("📦 Parsed ${out.length} server reports");
      return out;
    } catch (e) {
      debugPrint("❌ Error fetching reports: $e");
      rethrow;
    }
  }

  Map<String, double> _toDoubleMap(dynamic maybeMap) {
    if (maybeMap == null) return <String, double>{};
    if (maybeMap is Map) {
      final out = <String, double>{};
      final map = Map<String, dynamic>.from(maybeMap);
      map.forEach((k, v) {
        double val;
        if (v is num) {
          val = v.toDouble();
        } else if (v is String) {
          val = double.tryParse(v) ?? 0.0;
        } else {
          val = 0.0;
        }
        out[k.toString()] = val;
      });
      return out;
    }
    return <String, double>{};
  }

  Map<String, int> _toIntMap(dynamic maybeMap) {
    if (maybeMap == null) return <String, int>{};
    if (maybeMap is Map) {
      final out = <String, int>{};
      final map = Map<String, dynamic>.from(maybeMap);
      map.forEach((k, v) {
        int val;
        if (v is num) {
          val = v.toInt();
        } else if (v is String) {
          val = int.tryParse(v) ?? (double.tryParse(v)?.toInt() ?? 0);
        } else {
          val = 0;
        }
        out[k.toString()] = val;
      });
      return out;
    }
    return <String, int>{};
  }

  double _numToDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  // -----------------------
  // Pull and merge server -> local
  // -----------------------
  Future<void> pullReports() async {
    await LocalStorage.ensureInitialized();
    try {
      debugPrint("📥 Starting data pull from server...");
      final hasInternet = await _checkInternetConnection();
      if (!hasInternet) throw Exception("No internet");

      final serverAvailable = await _checkServerConnection();
      if (!serverAvailable) throw Exception("Server not reachable");

      final serverReports = await fetchReportsFromServer();
      final _ = LocalStorage.getAllReports();

      int added = 0, updated = 0, kept = 0;
      for (final serverReport in serverReports) {
        if (serverReport.branch.trim().isEmpty) {
          debugPrint("⚠️ Skipping server report with empty branch");
          continue;
        }

        final local = LocalStorage.getReportByBranchAndDate(serverReport.branch, serverReport.date);

        if (local == null) {
          await LocalStorage.saveReport(serverReport);
          added++;
        } else {
          if (serverReport.updatedAt.isAfter(local.updatedAt)) {
            await LocalStorage.saveReport(serverReport);
            updated++;
          } else {
            kept++;
          }
        }
      }

      debugPrint("✅ Data pull done — added: $added, updated: $updated, kept(local newer): $kept");
    } catch (e) {
      debugPrint("❌ Error during data pull: $e");
      rethrow;
    }
  }

  // -----------------------
  // Full sync (push then pull)
  // -----------------------
  Future<void> fullSync() async {
    await LocalStorage.ensureInitialized();
    try {
      await syncReports();
      await syncMonthlyReports(); // push monthly unsynced
      await pullReports();
      await pullMonthlyReports(); // pull monthly from server
    } catch (e) {
      debugPrint("❌ Full sync failed: $e");
      rethrow;
    }
  }

  // -----------------------
  // Delete helper: remote then local
  // -----------------------
  Future<void> deleteReport(DailyReport report, {int retryCount = 0}) async {
    await LocalStorage.ensureInitialized();
    await _withRetries(() => _deleteReportOnce(report), retries: 3);
  }

  Future<void> _deleteReportOnce(DailyReport report) async {
    debugPrint("🗑️ Deleting report ${report.branch} @ ${report.date}...");

    final hasInternet = await _checkInternetConnection();
    if (!hasInternet) throw Exception("No internet connection available");

    final serverAvailable = await _checkServerConnection();
    if (!serverAvailable) throw Exception("Server not reachable");

    final normalizedDate = _normalizeToUtcMidnight(report.date);

    final body = jsonEncode({
      'branch': report.branch,
      'date': normalizedDate.toIso8601String(),
    });

    final headers = await _getHeaders();
    final resp =
        await _client.delete(Uri.parse(_reportsUrl), headers: headers, body: body).timeout(const Duration(seconds: 15));

    if (resp.statusCode == 401) {
      debugPrint('❌ Delete returned 401 - token invalid.');
      throw Exception('Unauthorized (401). Please sign in again.');
    }

    if (resp.statusCode == 200) {
      final respBody = jsonDecode(resp.body);
      if (respBody is Map && respBody['success'] == true) {
        await LocalStorage.deleteByBranchAndDate(report.branch, normalizedDate);
        debugPrint("✅ Deleted report remote + local for ${report.branch} @ $normalizedDate");
        return;
      } else {
        throw Exception("Server deletion failed: ${resp.body}");
      }
    } else if (resp.statusCode == 404) {
      debugPrint("⚠️ Report not found on server (404), deleting local copy.");
      await LocalStorage.deleteByBranchAndDate(report.branch, normalizedDate);
      return;
    } else {
      throw Exception("Server returned ${resp.statusCode}: ${resp.reasonPhrase ?? ''}");
    }
  }

  // -----------------------
  // Monthly report helpers
  // -----------------------
  Future<void> syncMonthlyReports({int retryCount = 0}) async {
    await LocalStorage.ensureInitialized();
    await _withRetries(() => _syncMonthlyReportsOnce(), retries: 3);
  }

  Future<void> _syncMonthlyReportsOnce() async {
    debugPrint("🔄 Starting monthly sync push...");

    final hasInternet = await _checkInternetConnection();
    if (!hasInternet) throw Exception("No internet connection available");

    final serverAvailable = await _checkServerConnection();
    if (!serverAvailable) throw Exception("Server not reachable");

    final allMonthly = LocalStorage.getAllMonthlyReports();
    final unsynced = allMonthly.where((m) => m.synced == false).toList();

    if (unsynced.isEmpty) {
      debugPrint("📭 No unsynced monthly reports found.");
      return;
    }

    final mapping = <String, MonthlyReport>{};
    final payload = unsynced.map((m) {
      final normalized = _normalizeToUtcMonthStart(m.date);
      final key = _monthlyKey(m.branch, normalized);
      mapping[key] = m;

      if ((m as dynamic).toJson != null) {
        // Ensure the toJson map is strongly typed
        final dyn = (m as dynamic).toJson();
        final jsonObj = dyn is Map ? Map<String, dynamic>.from(dyn) : <String, dynamic>{};
        jsonObj['localKey'] = key;
        return jsonObj;
      } else {
        // Guarantee updatedAt/createdAt fields exist in payload
        final safeUpdated = m.updatedAt;
        final safeCreated = m.createdAt;
        return {
          'branch': m.branch,
          'date': normalized.toIso8601String(),
          'updatedAt': safeUpdated.toUtc().toIso8601String(),
          'createdAt': safeCreated.toUtc().toIso8601String(),
          'localKey': key,
        };
      }
    }).toList();

    debugPrint("📤 Sending ${payload.length} monthly reports to server...");
    final headers = await _getHeaders();
    final resp = await _client
        .post(Uri.parse(_monthlyApiUrl), headers: headers, body: jsonEncode({'monthlyReports': payload}))
        .timeout(_longTimeout);

    if (resp.statusCode == 401) {
      debugPrint('❌ Monthly sync returned 401 - token invalid.');
      throw Exception('Unauthorized (401). Please sign in again.');
    }

    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body);
      if (body is Map && body['success'] == true) {
        final List saved = (body['saved'] is List) ? (body['saved'] as List) : [];
        if (saved.isNotEmpty) {
          final Set<String> savedKeys = saved.map((s) {
            try {
              if (s is Map) {
                final sMap = Map<String, dynamic>.from(s);
                final dt = DateTime.parse(sMap['date'].toString()).toUtc();
                final key = '${sMap['branch'].toString().trim()}|${DateTime.utc(dt.year, dt.month, 1).toIso8601String()}';
                return key;
              }
              return '';
            } catch (_) {
              return '';
            }
          }).where((k) => k.isNotEmpty).toSet();

          int confirmed = 0;
          for (final key in savedKeys) {
            final local = mapping[key];
            if (local != null) {
              final updated = local.copyWith(synced: true, updatedAt: DateTime.now());
              await LocalStorage.saveMonthlyReport(updated);
              confirmed++;
            }
          }
          debugPrint("✅ Monthly sync push successful! $confirmed monthly reports confirmed saved (server).");
          return;
        } else {
          for (final m in unsynced) {
            final updated = m.copyWith(synced: true, updatedAt: DateTime.now());
            await LocalStorage.saveMonthlyReport(updated);
          }
          debugPrint("✅ Monthly sync push succeeded (no saved list). Marked ${unsynced.length} monthly reports as synced.");
          return;
        }
      } else {
        final errors = body['errors'] ?? body;
        throw Exception("Server responded with error: $errors");
      }
    } else {
      throw Exception("Server returned ${resp.statusCode}: ${resp.reasonPhrase}");
    }
  }

  Future<void> pushMonthlyReport(MonthlyReport report, {int retryCount = 0}) async {
    await LocalStorage.ensureInitialized();
    await _withRetries(() => _pushMonthlyOnce(report), retries: 2);
  }

  Future<void> _pushMonthlyOnce(MonthlyReport report) async {
    debugPrint("🔄 Pushing single monthly report for ${report.branch} @ ${report.date}...");

    final hasInternet = await _checkInternetConnection();
    if (!hasInternet) throw Exception("No internet connection available");

    final serverAvailable = await _checkServerConnection();
    if (!serverAvailable) throw Exception("Server not reachable");

    final normalized = _normalizeToUtcMonthStart(report.date);

    final dyn = (report.copyWith(date: normalized) as dynamic).toJson();
    final payloadObj = dyn is Map ? Map<String, dynamic>.from(dyn) : <String, dynamic>{};

    final headers = await _getHeaders();
    final resp = await _client
        .post(Uri.parse(_monthlyApiUrl), headers: headers, body: jsonEncode({'monthlyReports': [payloadObj]}))
        .timeout(_longTimeout);

    if (resp.statusCode == 401) {
      debugPrint('❌ pushMonthlyReport returned 401 - token invalid.');
      throw Exception('Unauthorized (401). Please sign in again.');
    }

    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body);
      if (body is Map && body['success'] == true) {
        final List saved = (body['saved'] is List) ? (body['saved'] as List) : [];
        bool confirmed = false;
        if (saved.isNotEmpty) {
          for (final s in saved) {
            try {
              if (s is Map) {
                final sMap = Map<String, dynamic>.from(s);
                final dt = DateTime.parse(sMap['date'].toString()).toUtc();
                final sKey = '${sMap['branch'].toString().trim()}|${DateTime.utc(dt.year, dt.month, 1).toIso8601String()}';
                final localKey = _monthlyKey(report.branch, normalized);
                if (sKey == localKey) {
                  confirmed = true;
                  break;
                }
              }
            } catch (_) {}
          }
        } else {
          confirmed = true;
        }

        if (confirmed) {
          final updated = report.copyWith(synced: true, updatedAt: DateTime.now(), date: normalized);
          await LocalStorage.saveMonthlyReport(updated);
          debugPrint("✅ Single monthly report push confirmed by server.");
          return;
        } else {
          throw Exception("Server did not confirm saved monthly report");
        }
      } else {
        throw Exception("Server error: ${body['errors'] ?? resp.body}");
      }
    } else {
      throw Exception("Server returned ${resp.statusCode}: ${resp.reasonPhrase}");
    }
  }

  Future<List<MonthlyReport>> fetchMonthlyReportsFromServer() async {
    await LocalStorage.ensureInitialized();
    try {
      debugPrint("📥 Fetching monthly reports from server...");
      final headers = await _getHeaders();
      final resp = await _client.get(Uri.parse(_monthlyUrl), headers: headers).timeout(_longTimeout);

      if (resp.statusCode == 401) {
        throw Exception('Unauthorized (401) while fetching monthly reports');
      }
      if (resp.statusCode != 200) {
        throw Exception("Failed to fetch monthly reports: ${resp.statusCode}");
      }

      final data = jsonDecode(resp.body);
      if (data is! List) {
        throw Exception("Unexpected server response format for monthly reports (expected list)");
      }

      final List<MonthlyReport> out = [];
      for (final item in data) {
        if (item == null || item is! Map) continue;

        final Map<String, dynamic> itemMap = Map<String, dynamic>.from(item);
        final branch = (itemMap['branch'] ?? '').toString().trim();
        final dateStr = itemMap['date']?.toString();
        if (branch.isEmpty || dateStr == null) {
          debugPrint("⚠️ Skipping monthly server item missing branch/date: $itemMap");
          continue;
        }

        try {
          final parsedDate = DateTime.parse(dateStr);
          final normalized = _normalizeToUtcMonthStart(parsedDate);

          // Try to parse with generated/fromJson; if that fails fall back to a minimal constructor.
          MonthlyReport report;
          try {
            report = MonthlyReport.fromJson(itemMap);
          } catch (_) {
            // Build fallback with safe defaults — ensure createdAt/updatedAt are non-null DateTime
            final fallbackUpdated = DateTime.tryParse(itemMap['updatedAt']?.toString() ?? '') ?? DateTime.now();
            final fallbackCreated = DateTime.tryParse(itemMap['createdAt']?.toString() ?? '') ?? DateTime.now();
            report = MonthlyReport(
              branch: branch,
              date: normalized,
              synced: true,
              createdAt: fallbackCreated,
              updatedAt: fallbackUpdated, year: null, month: null, totalCollected: null, totalDisbursed: null, totalExpenses: null,
            );
          }

          // Ensure non-null updatedAt for comparisons downstream
          final safeUpdated = report.updatedAt;
          final safeCreated = report.createdAt;

          final normalizedReport = report.copyWith(date: normalized, synced: true, updatedAt: safeUpdated, createdAt: safeCreated);
          out.add(normalizedReport);
        } catch (e) {
          debugPrint("⚠️ Skipping server monthly item with invalid date/format: $itemMap — $e");
          continue;
        }
      }

      debugPrint("📦 Parsed ${out.length} server monthly reports");
      return out;
    } catch (e) {
      debugPrint("❌ Error fetching monthly reports: $e");
      rethrow;
    }
  }

  Future<void> pullMonthlyReports() async {
    await LocalStorage.ensureInitialized();
    try {
      debugPrint("📥 Starting monthly data pull from server...");
      final hasInternet = await _checkInternetConnection();
      if (!hasInternet) throw Exception("No internet");

      final serverAvailable = await _checkServerConnection();
      if (!serverAvailable) throw Exception("Server not reachable");

      final serverReports = await fetchMonthlyReportsFromServer();

      int added = 0, updated = 0, kept = 0;
      for (final serverReport in serverReports) {
        if (serverReport.branch.trim().isEmpty) {
          debugPrint("⚠️ Skipping server monthly report with empty branch");
          continue;
        }

        // Local lookup expects a DateTime month-start; make sure we have one
        final normalized = _normalizeToUtcMonthStart(serverReport.date);
        final local = LocalStorage.getMonthlyReportByBranchAndMonth(serverReport.branch, normalized);

        // normalize serverReport for local comparisons (guarantee updatedAt non-null)
        final serverUpdated = serverReport.updatedAt;
        final normalizedServerReport = serverReport.copyWith(date: normalized, synced: true, updatedAt: serverUpdated);

        if (local == null) {
          await LocalStorage.saveMonthlyReport(normalizedServerReport);
          added++;
        } else {
          // If local or server updatedAt missing, treat that side as DateTime.now() to avoid null comparison
          final localUpdated = local.updatedAt;
          if (serverUpdated.isAfter(localUpdated)) {
            await LocalStorage.saveMonthlyReport(normalizedServerReport);
            updated++;
          } else {
            kept++;
          }
        }
      }

      debugPrint("✅ Monthly data pull done — added: $added, updated: $updated, kept(local newer): $kept");
    } catch (e) {
      debugPrint("❌ Error during monthly data pull: $e");
      rethrow;
    }
  }

  Future<void> deleteMonthlyReport(MonthlyReport report, {int retryCount = 0}) async {
    await LocalStorage.ensureInitialized();
    await _withRetries(() => _deleteMonthlyOnce(report), retries: 3);
  }

  Future<void> _deleteMonthlyOnce(MonthlyReport report) async {
    debugPrint("🗑️ Deleting monthly report ${report.branch} @ ${report.date}...");

    final hasInternet = await _checkInternetConnection();
    if (!hasInternet) throw Exception("No internet connection available");

    final serverAvailable = await _checkServerConnection();
    if (!serverAvailable) throw Exception("Server not reachable");

    final normalizedDate = _normalizeToUtcMonthStart(report.date);

    final body = jsonEncode({
      'branch': report.branch,
      'date': normalizedDate.toIso8601String(),
    });

    final headers = await _getHeaders();
    final resp =
        await _client.delete(Uri.parse(_monthlyUrl), headers: headers, body: body).timeout(const Duration(seconds: 15));

    if (resp.statusCode == 401) {
      debugPrint('❌ Monthly delete returned 401 - token invalid.');
      throw Exception('Unauthorized (401). Please sign in again.');
    }

    if (resp.statusCode == 200) {
      final respBody = jsonDecode(resp.body);
      if (respBody is Map && respBody['success'] == true) {
        await LocalStorage.deleteMonthlyByBranchAndMonth(report.branch, normalizedDate);
        debugPrint("✅ Deleted monthly report remote + local for ${report.branch} @ $normalizedDate");
        return;
      } else {
        throw Exception("Server deletion failed: ${resp.body}");
      }
    } else if (resp.statusCode == 404) {
      debugPrint("⚠️ Monthly report not found on server (404), deleting local copy.");
      await LocalStorage.deleteMonthlyByBranchAndMonth(report.branch, normalizedDate);
      return;
    } else {
      throw Exception("Server returned ${resp.statusCode}: ${resp.reasonPhrase ?? ''}");
    }
  }
}
