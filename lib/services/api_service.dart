// lib/services/api_service.dart
// API client (single class) — robust and safe.
//
// Fixes included:
// ✅ One ApiService class (no duplicates)
// ✅ Robust list extraction for endpoints returning either:
//    - [ ... ]
//    - { reports: [ ... ] } / { data: [ ... ] } / { items: [ ... ] }
// ✅ Zanaco aggregate fetch: GET /api/zanaco?aggregate=true
// ✅ Monthly delete uses your backend routes (/api/monthly_reports)
// ✅ Multipart upload does NOT mutate global headers
// ✅ Admin clients list normalization (name/phone/balance/id always correct)
// ✅ NEW: Admin fetch single client by id: GET /api/clients/:id
//
// ignore_for_file: unintended_html_in_doc_comment, prefer_iterable_wheretype

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  // Base URL normalized to always end with /api
  static String baseUrl = _normalizeBaseUrl('https://directaccessapi.onrender.com');

  // Default headers for JSON requests
  static Map<String, String> defaultHeaders = {'Content-Type': 'application/json'};

  // Optional injected http client (useful for tests)
  static http.Client? _injectedClient;
  static http.Client get _client => _injectedClient ??= http.Client();

  // Request timeout
  static Duration timeout = const Duration(seconds: 12);

  // Retries (GET only)
  static int maxRetries = 2;

  // -------------------- INIT --------------------
  static void init({
    required String url,
    http.Client? client,
    Duration? requestTimeout,
  }) {
    baseUrl = _normalizeBaseUrl(url);
    if (client != null) _injectedClient = client;
    if (requestTimeout != null) timeout = requestTimeout;
  }

  static String _normalizeBaseUrl(String url) {
    if (url.isEmpty) return 'https://directaccessapi.onrender.com/api';
    var u = url.replaceAll(RegExp(r'/$'), '');
    if (u.endsWith('/api')) return u;
    return '$u/api';
  }

  static void _ensureHeaders() {
    defaultHeaders = {...defaultHeaders};
  }

  static void _debugLog(String tag, String msg) {
    if (kDebugMode) debugPrint('[ApiService::$tag] $msg');
  }

  // -------------------- ROBUST RESPONSE HELPERS --------------------

  /// Extract a list from either:
  ///  - direct list: [ ... ]
  ///  - wrapped: { reports:[...]} / { data:[...]} / { items:[...]} / etc.
  static List<dynamic> _extractList(dynamic res, List<String> keys) {
    if (res == null) return <dynamic>[];
    if (res is List) return res;
    if (res is Map) {
      for (final k in keys) {
        final v = res[k];
        if (v is List) return v;
      }
    }
    return <dynamic>[];
  }

  /// Date string in YYYY-MM-DD
  static String _yyyyMmDd(DateTime d) {
    final u = d.toUtc();
    final y = u.year.toString().padLeft(4, '0');
    final m = u.month.toString().padLeft(2, '0');
    final day = u.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  // -------------------- GENERIC REQUEST WRAPPER --------------------
  static Future<dynamic> _request(
    Future<http.Response> Function() action, {
    bool allowEmptyBody = false,
    bool treat404AsNull = false,
    bool parseJson = true,
    bool retryOnNetworkErrorForGet = false,
  }) async {
    int attempt = 0;

    while (true) {
      attempt++;
      try {
        final resp = await action().timeout(timeout);
        _debugLog('response', 'status=${resp.statusCode} bodyLen=${resp.body.length}');

        // Success (2xx)
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          if (!parseJson) return resp;

          final body = resp.body.trim();
          if (body.isEmpty) return allowEmptyBody ? {} : {};

          try {
            return jsonDecode(body);
          } catch (_) {
            _debugLog('parse', 'non-json response, returning raw body');
            return body;
          }
        }

        // 404 => null (optional behavior)
        if (resp.statusCode == 404 && treat404AsNull) return null;

        // 204 => success with empty result
        if (resp.statusCode == 204) return allowEmptyBody ? {} : {};

        // Other HTTP errors
        throw HttpException('HTTP ${resp.statusCode}: ${resp.body}');
      } catch (e) {
        final isNetworkError = e is SocketException || e is TimeoutException;

        if (isNetworkError && retryOnNetworkErrorForGet && attempt <= maxRetries) {
          final backoff = Duration(milliseconds: 200 * pow(2, attempt).toInt());
          _debugLog('retry', 'attempt=$attempt backoff=${backoff.inMilliseconds}ms error=$e');
          await Future.delayed(backoff);
          continue;
        }
        rethrow;
      }
    }
  }

  // -------------------- URL HELPERS --------------------
  static String _cleanPath(String path) {
    if (path.isEmpty) return '';
    return path.startsWith('/') ? path : '/$path';
  }

  static Uri _buildUri(String path, {Map<String, String>? query}) {
    final p = _cleanPath(path);
    final uri = Uri.parse('$baseUrl$p');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  // -------------------- GENERIC HTTP HELPERS --------------------
  static Future<dynamic> get(
    String path, {
    Map<String, String>? query,
    bool treat404AsNull = false,
    bool parseJson = true,
    bool allowEmptyBody = false,
    bool retry = true,
  }) async {
    _ensureHeaders();
    final uri = _buildUri(path, query: query);

    return _request(
      () => _client.get(uri, headers: defaultHeaders),
      treat404AsNull: treat404AsNull,
      parseJson: parseJson,
      allowEmptyBody: allowEmptyBody,
      retryOnNetworkErrorForGet: retry,
    );
  }

  static Future<dynamic> post(
    String path, {
    Map<String, String>? query,
    Object? body,
    bool parseJson = true,
  }) async {
    _ensureHeaders();
    final uri = _buildUri(path, query: query);

    return _request(
      () => _client.post(
        uri,
        headers: defaultHeaders,
        body: body == null ? null : jsonEncode(body),
      ),
      parseJson: parseJson,
    );
  }

  static Future<dynamic> put(
    String path, {
    Map<String, String>? query,
    Object? body,
    bool parseJson = true,
  }) async {
    _ensureHeaders();
    final uri = _buildUri(path, query: query);

    return _request(
      () => _client.put(
        uri,
        headers: defaultHeaders,
        body: body == null ? null : jsonEncode(body),
      ),
      parseJson: parseJson,
    );
  }

  static Future<dynamic> delete(
    String path, {
    Map<String, String>? query,
    Object? body,
    bool parseJson = true,
    bool treat404AsNull = false,
  }) async {
    _ensureHeaders();
    final uri = _buildUri(path, query: query);

    return _request(
      () => _client.delete(
        uri,
        headers: defaultHeaders,
        body: body == null ? null : jsonEncode(body),
      ),
      parseJson: parseJson,
      treat404AsNull: treat404AsNull,
    );
  }

  // -------------------- SMALL HELPERS --------------------
  static String _utcMidnightIso(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    return d.toIso8601String();
  }

  static String _utcMonthStartIso(DateTime date) {
    final d = DateTime.utc(date.year, date.month, 1);
    return d.toIso8601String();
  }

  static String _normalizePhone(String phone) {
    if (phone.isEmpty) return phone;
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    return cleaned.startsWith('0') ? cleaned.substring(1) : cleaned;
  }

  // -------------------- AUTH --------------------
  static Future<Map<String, dynamic>> register(
    String email,
    String password, {
    String? name,
    String? phone,
  }) async {
    _ensureHeaders();
    final uri = Uri.parse('$baseUrl/auth/register');
    final res = await _request(
      () => _client.post(
        uri,
        headers: defaultHeaders,
        body: jsonEncode({'email': email, 'password': password, 'name': name, 'phone': phone}),
      ),
    );
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    _ensureHeaders();
    final uri = Uri.parse('$baseUrl/auth/login');
    final res = await _request(
      () => _client.post(
        uri,
        headers: defaultHeaders,
        body: jsonEncode({'email': email, 'password': password}),
      ),
    );
    return Map<String, dynamic>.from(res as Map);
  }

  // -------------------- CLIENT (Dashboard) --------------------
  static Future<Map<String, dynamic>> fetchMyClient({bool includeLoans = false}) async {
    final params = includeLoans ? {'includeLoans': 'true'} : null;

    try {
      final res = await get('/clients/me', query: params, retry: true);

      if (res is Map) {
        final result = Map<String, dynamic>.from(res);

        if (result['success'] == true) return result;
        if (result['success'] == false) {
          throw Exception(result['message'] ?? 'Failed to fetch client data');
        }

        if (result.containsKey('client') || result.containsKey('loansSummary')) {
          return {'success': true, ...result};
        }

        return {'success': true, 'client': result};
      }

      throw Exception('Invalid response format from server');
    } catch (e) {
      _debugLog('fetchMyClient', 'Error: $e');
      rethrow;
    }
  }

  // -------------------- LOANS --------------------
  static Future<List<dynamic>> fetchLoansByQuery({
    String? email,
    String? phone,
    String? name,
    int? limit,
    bool exactMatch = false,
  }) async {
    _ensureHeaders();
    final params = <String, String>{};

    if (email != null && email.trim().isNotEmpty) params['email'] = email.trim().toLowerCase();
    if (phone != null && phone.trim().isNotEmpty) params['phone'] = _normalizePhone(phone.trim());
    if (name != null && name.trim().isNotEmpty) params['name'] = name.trim();

    if (limit != null) params['limit'] = limit.toString();
    if (exactMatch) params['exactMatch'] = 'true';

    final uri = Uri.parse('$baseUrl/loans').replace(queryParameters: params);

    try {
      final result = await _request(
        () => _client.get(uri, headers: defaultHeaders),
        retryOnNetworkErrorForGet: true,
        treat404AsNull: true,
      );

      if (result == null) return <dynamic>[];
      if (result is Map && result['loans'] is List) return result['loans'] as List;
      if (result is List) return result;

      return <dynamic>[];
    } catch (e) {
      _debugLog('fetchLoansByQuery', 'Error: $e');
      rethrow;
    }
  }

  static Future<List<dynamic>> fetchLoansByUserProfiles(
    List<Map<String, String>> profiles, {
    int limit = 20,
  }) async {
    _ensureHeaders();

    final queries = profiles
        .map((profile) => {
              'email': profile['email']?.trim().toLowerCase() ?? '',
              'phone': profile['phone'] != null ? _normalizePhone(profile['phone']!) : '',
              'name': profile['name']?.trim() ?? '',
            })
        .where((q) => q['email']!.isNotEmpty || q['phone']!.isNotEmpty || q['name']!.isNotEmpty)
        .toList();

    if (queries.isEmpty) return <dynamic>[];

    final uri = Uri.parse('$baseUrl/loans/bulk-query');
    final body = jsonEncode({'queries': queries, 'limit': limit});

    try {
      final result = await _request(() => _client.post(uri, headers: defaultHeaders, body: body));

      if (result is Map && result['loans'] is List) return result['loans'] as List;
      if (result is List) return result;

      return <dynamic>[];
    } catch (e) {
      _debugLog('fetchLoansByUserProfiles', 'Error: $e');
      return _fallbackIndividualQueries(queries, limit: limit);
    }
  }

  static Future<List<dynamic>> _fallbackIndividualQueries(
    List<Map<String, String>> queries, {
    int limit = 20,
  }) async {
    final allLoans = <dynamic>[];
    final seenIds = <String>{};

    for (final q in queries) {
      try {
        final loans = await fetchLoansByQuery(
          email: q['email'],
          phone: q['phone'],
          name: q['name'],
          limit: limit,
        );

        for (final loan in loans) {
          if (loan is Map) {
            final id = loan['_id']?.toString() ?? loan['id']?.toString();
            if (id != null && !seenIds.contains(id)) {
              seenIds.add(id);
              allLoans.add(loan);
            }
          }
        }

        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        _debugLog('_fallbackIndividualQueries', 'Query failed: $e');
      }
    }

    return allLoans;
  }

  static Future<Map<String, dynamic>?> fetchLoanById(String id) async {
    _ensureHeaders();
    if (id.trim().isEmpty) return null;

    final uri = Uri.parse('$baseUrl/loans/${Uri.encodeComponent(id)}');

    try {
      final result = await _request(
        () => _client.get(uri, headers: defaultHeaders),
        treat404AsNull: true,
        retryOnNetworkErrorForGet: true,
      );

      if (result == null) return null;

      if (result is Map && result.containsKey('loan')) {
        return Map<String, dynamic>.from(result['loan'] as Map);
      }

      if (result is Map) return Map<String, dynamic>.from(result);

      return null;
    } catch (e) {
      _debugLog('fetchLoanById', 'Error fetching loan $id: $e');
      return null;
    }
  }

  // -------------------- DAILY REPORTS --------------------
  static Future<Map<String, dynamic>> syncReports(List<Map<String, dynamic>> reports) async {
    _ensureHeaders();
    final uri = Uri.parse('$baseUrl/sync_reports');
    final res = await _request(
      () => _client.post(uri, headers: defaultHeaders, body: jsonEncode({'reports': reports})),
    );
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<Map<String, dynamic>> saveReportSingle(Map<String, dynamic> report) async {
    _ensureHeaders();
    final uri = Uri.parse('$baseUrl/report');
    try {
      final result = await _request(() => _client.post(uri, headers: defaultHeaders, body: jsonEncode(report)));
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      _debugLog('saveReportSingle', 'primary endpoint failed, attempting syncReports fallback: $e');
      return await syncReports([report]);
    }
  }

  static Future<Map<String, dynamic>?> fetchReportForBranchDate(String branch, DateTime date) async {
    final dateIso = _utcMidnightIso(date);
    final uri = Uri.parse('$baseUrl/reports/query').replace(queryParameters: {'branch': branch, 'date': dateIso});

    final result = await _request(
      () => _client.get(uri, headers: defaultHeaders),
      treat404AsNull: true,
      retryOnNetworkErrorForGet: true,
    );

    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }

  /// Supports both List and wrapped Map responses.
  static Future<List<dynamic>> fetchAllReports() async {
    final res = await get('/reports', retry: true);
    return _extractList(res, const ['reports', 'data', 'items']);
  }

  static Future<bool> deleteReportByBranchDate(String branch, DateTime date) async {
    _ensureHeaders();
    final uri = Uri.parse('$baseUrl/reports');

    final req = http.Request('DELETE', uri);
    req.headers.addAll(defaultHeaders);
    req.body = jsonEncode({'branch': branch, 'date': _utcMidnightIso(date)});

    final streamed = await _client.send(req).timeout(timeout);
    final resp = await http.Response.fromStream(streamed);

    _debugLog('deleteReportByBranchDate', 'status=${resp.statusCode} body=${resp.body}');
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  static Future<bool> deleteReportById(String id) async {
    _ensureHeaders();
    final uri = Uri.parse('$baseUrl/reports/$id');
    final resp = await _client.delete(uri, headers: defaultHeaders).timeout(timeout);
    _debugLog('deleteReportById', 'status=${resp.statusCode} body=${resp.body}');
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  // -------------------- ZANACO --------------------

  /// GET /api/zanaco?date=...&branch=...&channel=...
  static Future<dynamic> getZanaco({
    required DateTime date,
    String? branch,
    String? channel,
  }) async {
    final dateIso = _utcMidnightIso(date);
    final params = <String, String>{'date': dateIso};
    if (branch != null) params['branch'] = branch;
    if (channel != null) params['channel'] = channel;

    final uri = Uri.parse('$baseUrl/zanaco').replace(queryParameters: params);

    final resp = await _request(
      () => _client.get(uri, headers: defaultHeaders),
      retryOnNetworkErrorForGet: true,
    );

    if (resp == null) return {'success': false, 'distributions': []};
    return resp;
  }

  /// GET /api/zanaco?branch=...&date=YYYY-MM-DD&aggregate=true
  static Future<Map<String, double>> fetchZanacoAggregate({
    required String branch,
    required DateTime date,
  }) async {
    final b = branch.toLowerCase().trim();
    final d = _yyyyMmDd(date);

    final res = await get(
      '/zanaco',
      query: {'branch': b, 'date': d, 'aggregate': 'true'},
      retry: true,
      treat404AsNull: true,
    );

    if (res == null) return <String, double>{};

    if (res is Map) {
      final out = <String, double>{};
      res.forEach((k, v) {
        final key = k.toString().toLowerCase();
        final val = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
        out[key] = val;
      });
      return out;
    }

    return <String, double>{};
  }

  static Future<Map<String, dynamic>> saveZanacoSingle({
    required DateTime date,
    required String branch,
    required String channel,
    required double amount,
    Map<String, dynamic>? metadata,
  }) async {
    _ensureHeaders();
    final uri = Uri.parse('$baseUrl/zanaco');
    final body = jsonEncode({
      'date': _utcMidnightIso(date),
      'branch': branch,
      'channel': channel,
      'amount': amount,
      'metadata': metadata ?? {},
    });

    final result = await _request(() => _client.post(uri, headers: defaultHeaders, body: body));
    return Map<String, dynamic>.from(result as Map);
  }

  static Future<Map<String, dynamic>> saveZanacoBulk({
    required DateTime date,
    String? fromBranch,
    required Map<String, Map<String, double>> allocations,
    List<Map<String, dynamic>>? distributions,
  }) async {
    _ensureHeaders();
    final uri = Uri.parse('$baseUrl/zanaco/bulk');

    final Map<String, dynamic> bodyMap = {
      'date': _utcMidnightIso(date),
      'fromBranch': fromBranch,
      'allocations': allocations,
    };

    if (distributions != null) bodyMap['distributions'] = distributions;

    final result = await _request(() => _client.post(uri, headers: defaultHeaders, body: jsonEncode(bodyMap)));

    try {
      return Map<String, dynamic>.from(result as Map);
    } catch (_) {
      return {'success': true, 'raw': result};
    }
  }

  static Future<String?> getBranchForEmail(String email) async {
    if (email.trim().isEmpty) return null;
    _ensureHeaders();

    try {
      final uri = Uri.parse('$baseUrl/user/branch').replace(queryParameters: {'email': email.trim().toLowerCase()});

      final resp = await _request(
        () => _client.get(uri, headers: defaultHeaders),
        treat404AsNull: true,
        retryOnNetworkErrorForGet: true,
      );

      if (resp == null) return null;

      if (resp is Map && (resp['success'] == true || resp.containsKey('branch'))) {
        final dynamic branch = resp['branch'];
        if (branch == null) return null;
        return branch.toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, double>> fetchZanacoDistributions({
    required String branch,
    required DateTime date,
  }) async {
    _ensureHeaders();
    final dateStr = DateTime.utc(date.year, date.month, date.day).toIso8601String().split('T').first;

    final uri = Uri.parse('$baseUrl/zanaco/distributions').replace(queryParameters: {
      'branch': branch.toLowerCase().trim(),
      'date': dateStr,
    });

    final result = await _request(
      () => _client.get(uri, headers: defaultHeaders),
      retryOnNetworkErrorForGet: true,
    );

    double airtel = 0.0;
    double mtn = 0.0;

    if (result == null) return {'airtel': 0.0, 'mtn': 0.0};

    try {
      final list = result is List
          ? result
          : (result is Map && result['distributions'] is List ? result['distributions'] as List : []);

      for (final item in list) {
        if (item is Map) {
          final ch = (item['channel'] ?? item['channelName'] ?? '').toString().toLowerCase();
          final amt = _extractAmountForApi(item['amount'] ?? item['value'] ?? item['allocated'] ?? item);

          if (ch.contains('airtel')) {
            airtel += amt;
          } else if (ch.contains('mtn')) {
            mtn += amt;
          } else {
            airtel += amt;
          }
        }
      }
    } catch (_) {}

    return {'airtel': airtel, 'mtn': mtn};
  }

  static double _extractAmountForApi(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();

    if (v is String) {
      final cleaned = v.replaceAll(',', '').trim();
      return double.tryParse(cleaned) ?? 0.0;
    }

    if (v is Map) {
      for (final key in v.keys) {
        final lk = key.toString().toLowerCase();
        if (lk.contains('number')) {
          final inner = v[key];
          if (inner is String) return double.tryParse(inner.replaceAll(',', '').trim()) ?? 0.0;
          if (inner is num) return inner.toDouble();
        }
      }

      if (v.containsKey('amount')) return _extractAmountForApi(v['amount']);
      if (v.values.isNotEmpty) return _extractAmountForApi(v.values.first);
    }

    return 0.0;
  }

  // -------------------- MONTHLY REPORTS --------------------
  static Future<Map<String, dynamic>> syncMonthlyReports(List<Map<String, dynamic>> monthlyReports) async {
    _ensureHeaders();
    final uri = Uri.parse('$baseUrl/sync_monthly_reports');
    final res = await _request(
      () => _client.post(uri, headers: defaultHeaders, body: jsonEncode({'monthlyReports': monthlyReports})),
    );
    return Map<String, dynamic>.from(res as Map);
  }

  /// Supports both List and wrapped Map responses.
  static Future<List<dynamic>> fetchAllMonthlyReports() async {
    final res = await get('/monthly_reports', retry: true);
    return _extractList(res, const ['monthlyReports', 'reports', 'data', 'items']);
  }

  static Future<bool> deleteMonthlyReportById(String id) async {
    _ensureHeaders();
    final uri = Uri.parse('$baseUrl/monthly_reports/$id');
    final resp = await _client.delete(uri, headers: defaultHeaders).timeout(timeout);
    _debugLog('deleteMonthlyReportById', 'status=${resp.statusCode} body=${resp.body}');
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  static Future<bool> deleteMonthlyReportByBranchDate({
    required String branch,
    required DateTime monthDate,
  }) async {
    _ensureHeaders();
    final uri = Uri.parse('$baseUrl/monthly_reports');

    final req = http.Request('DELETE', uri);
    req.headers.addAll(defaultHeaders);
    req.body = jsonEncode({'branch': branch, 'date': _utcMonthStartIso(monthDate)});

    final streamed = await _client.send(req).timeout(timeout);
    final resp = await http.Response.fromStream(streamed);

    _debugLog('deleteMonthlyReportByBranchDate', 'status=${resp.statusCode} body=${resp.body}');
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  // -------------------- BRANCH COMMENTS --------------------
  static Future<Map<String, dynamic>> saveBranchComment(String branch, String text, String author) async {
    _ensureHeaders();
    final uri = Uri.parse('$baseUrl/branches/${Uri.encodeComponent(branch)}/comments');
    final result = await _request(
      () => _client.post(uri, headers: defaultHeaders, body: jsonEncode({'text': text, 'author': author})),
    );
    return Map<String, dynamic>.from(result as Map);
  }

  // -------------------- MULTIPART FILE UPLOAD --------------------
  static Future<Map<String, dynamic>> uploadAttachment({
    required String endpointPath, // e.g. '/branches/lumezi/attachments'
    required File file,
    required String fieldName,
    Map<String, String>? fields,
  }) async {
    final uri = Uri.parse('$baseUrl$endpointPath');
    final req = http.MultipartRequest('POST', uri);

    // IMPORTANT: do NOT mutate global defaultHeaders.
    final headers = {...defaultHeaders};
    headers.remove('Content-Type');
    req.headers.addAll(headers);

    if (fields != null) req.fields.addAll(fields);

    final part = await http.MultipartFile.fromPath(fieldName, file.path);
    req.files.add(part);

    final streamed = await _client.send(req).timeout(timeout);
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      try {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        return {'success': true, 'raw': resp.body};
      }
    }

    throw Exception('uploadAttachment failed: ${resp.statusCode} ${resp.body}');
  }

  // -------------------- NOTIFICATIONS --------------------
  static Future<Map<String, dynamic>> createNotification({
    required String toEmail,
    required String title,
    required String message,
    String type = 'info',
    Map<String, dynamic>? data,
  }) async {
    final res = await post(
      '/notifications',
      body: {
        'toEmail': toEmail.trim().toLowerCase(),
        'title': title,
        'message': message,
        'type': type,
        'data': data ?? {},
      },
    );

    if (res is Map && res['success'] == false) {
      throw Exception(res['message'] ?? 'Failed to create notification');
    }

    return (res is Map) ? Map<String, dynamic>.from(res) : {'success': true, 'raw': res};
  }

  static Future<List<Map<String, dynamic>>> fetchUnreadNotifications(String toEmail) async {
    final res = await get(
      '/notifications',
      query: {'to': toEmail.trim().toLowerCase()},
      retry: true,
      treat404AsNull: true,
    );

    if (res == null) return <Map<String, dynamic>>[];

    if (res is Map) {
      if (res['success'] == false) {
        throw Exception(res['message'] ?? 'Failed to fetch notifications');
      }
      final data = res['data'];
      if (data is List) {
        return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return <Map<String, dynamic>>[];
    }

    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    return <Map<String, dynamic>>[];
  }

  static Future<void> markAllNotificationsRead(String toEmail) async {
    final res = await post('/notifications/mark-all-read', body: {'toEmail': toEmail.trim().toLowerCase()});

    if (res is Map && res['success'] == false) {
      throw Exception(res['message'] ?? 'Failed to mark notifications read');
    }
  }

  // -------------------- CLIENTS (ADMIN LIST + MANUAL EDIT) --------------------

  // ---- Client row normalizers (fix name/phone/balance/id issues) ----
  static String _idToString(dynamic id) {
    if (id == null) return '';
    if (id is String) return id;
    if (id is Map && id[r'$oid'] != null) return id[r'$oid'].toString();
    return id.toString();
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '').trim()) ?? 0.0;

    // Mongo wrappers: { $numberDecimal: "5207.26" } etc
    if (v is Map) {
      for (final k in v.keys) {
        final lk = k.toString().toLowerCase();
        if (lk.contains('number')) {
          final inner = v[k];
          if (inner is num) return inner.toDouble();
          if (inner is String) return double.tryParse(inner.replaceAll(',', '').trim()) ?? 0.0;
        }
      }
    }
    return 0.0;
  }

  static String _phoneFromClientKey(String clientKey) {
    final ck = clientKey.trim();
    if (ck.startsWith('phone:')) return ck.substring(6).trim();
    return '';
  }

  // Smart detectors (to repair bad imports)
  static bool _looksLikeEmail(String s) {
    final t = s.trim();
    return t.contains('@') && t.contains('.');
  }

  static bool _looksLikePhone(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), '').trim();
    return RegExp(r'^\+?\d{9,13}$').hasMatch(t);
  }

  static bool _looksLikeAddress(String s) {
    final t = s.trim().toLowerCase();
    if (t.isEmpty) return false;
    if (_looksLikeEmail(t) || _looksLikePhone(t)) return false;

    // Simple address hints (matches your screenshot style)
    return t.contains('house') ||
        t.contains('plot') ||
        t.contains('no.') ||
        t.contains('near') ||
        t.contains('villa') ||
        t.contains('school') ||
        t.split(' ').length >= 2;
  }

  static Map<String, dynamic> _normalizeClientRow(Map<String, dynamic> j) {
    final clientKey = (j['clientKey'] ?? '').toString().trim();

    String name = (j['fullName'] ?? '').toString().trim();
    String email = (j['email'] ?? '').toString().trim();
    String phone = (j['phone'] ?? '').toString().trim();
    String address = (j['address'] ?? '').toString().trim();

    // Always attempt phone from clientKey
    final phoneFromKey = _phoneFromClientKey(clientKey);
    if (phone.isEmpty && phoneFromKey.isNotEmpty) phone = phoneFromKey;

    // If fullName is actually a phone number -> move it to phone
    if (name.isNotEmpty && _looksLikePhone(name) && phone.isEmpty) {
      phone = name;
      name = '';
    }

    // If email field is actually an address sentence -> move it to address
    if (email.isNotEmpty && !_looksLikeEmail(email) && address.isEmpty) {
      address = email;
      email = '';
    }

    // If fullName is actually an address -> move it to address
    if (name.isNotEmpty && _looksLikeAddress(name) && address.isEmpty) {
      address = name;
      name = '';
    }

    return {
      '_id': _idToString(j['_id']),
      'clientKey': clientKey,
      'fullName': name,
      'email': email,
      'phone': phone,
      'balance': _toDouble(j['balance']),
      'address': address,
      // optional extras
      'loanStatus': j['loanStatus'],
      'statusBucket': j['statusBucket'],
      'isExtended': j['isExtended'],
      'statementDate': j['statementDate'],
      'updatedAt': j['updatedAt'],
      'lastImportedAt': j['lastImportedAt'],
      'dateOfBirth': j['dateOfBirth'],
    };
  }

  /// GET /api/clients?q=...&limit=...&lite=true
  /// If you added server support: lite=true returns minimal fields.
  static Future<List<Map<String, dynamic>>> fetchClients({
    String? q,
    int limit = 500,
    bool lite = true,
  }) async {
    final res = await get(
      '/clients',
      query: {
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        'limit': limit.toString(),
        'lite': lite ? 'true' : 'false',
      },
      retry: true,
    );

    if (res is Map && res['success'] == false) {
      throw Exception(res['message'] ?? 'Failed to fetch clients');
    }

    final raw = (res is Map) ? (res['clients'] ?? res['data'] ?? res['items']) : res;

    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => _normalizeClientRow(Map<String, dynamic>.from(e)))
          .toList();
    }

    if (raw is List<dynamic>) {
      return raw
          .where((e) => e is Map)
          .map((e) => _normalizeClientRow(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    return <Map<String, dynamic>>[];
  }

  /// ✅ GET /api/clients/:id  (Admin fetch one client)
  static Future<Map<String, dynamic>> fetchClientById(String id) async {
    final clean = id.trim();
    if (clean.isEmpty) throw Exception('Client id is required');

    final res = await get('/clients/$clean', retry: true);

    if (res is Map && res['success'] == false) {
      throw Exception(res['message'] ?? 'Failed to fetch client');
    }

    // expected: { success:true, client:{...} }
    if (res is Map && res['client'] is Map) {
      return _normalizeClientRow(Map<String, dynamic>.from(res['client'] as Map));
    }

    // fallback: server might return raw client map
    if (res is Map) {
      return _normalizeClientRow(Map<String, dynamic>.from(res));
    }

    throw Exception('Invalid response format from server');
  }

  static Future<Map<String, dynamic>> updateClientManual({
    required String id,
    String? fullName,
    String? email,
    String? phone,
    String? address,
    double? balance,
  }) async {
    final body = <String, dynamic>{
      if (fullName != null) 'fullName': fullName,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (address != null) 'address': address,
      if (balance != null) 'balance': balance,
    };

    final res = await put('/clients/$id', body: body);

    if (res is Map && res['success'] == false) {
      throw Exception(res['message'] ?? 'Failed to update client');
    }

    if (res is Map && res['client'] is Map) {
      res['client'] = _normalizeClientRow(Map<String, dynamic>.from(res['client'] as Map));
    }

    return (res is Map) ? Map<String, dynamic>.from(res) : {'success': true, 'raw': res};
  }

  static Future<void> deleteClientById(String id) async {
    final res = await delete('/clients/$id');
    if (res is Map && res['success'] == false) {
      throw Exception(res['message'] ?? 'Failed to delete client');
    }
  }

  // -------------------- USERS / CLIENT DIRECTORY (Admin) --------------------

  /// GET /api/users
  static Future<List<Map<String, dynamic>>> fetchUsers({String? role}) async {
    final res = await get(
      '/users',
      query: (role != null && role.trim().isNotEmpty) ? {'role': role.trim()} : null,
      retry: true,
      treat404AsNull: true,
    );

    final list = _extractList(res, const ['users', 'data', 'items', 'results']);
    final out = <Map<String, dynamic>>[];

    for (final e in list) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
    }

    if (role != null && role.trim().isNotEmpty) {
      final r = role.trim().toLowerCase();
      return out.where((u) => (u['role'] ?? '').toString().toLowerCase() == r).toList();
    }

    return out;
  }

  /// GET /api/users/:email/profile
  static Future<Map<String, dynamic>?> fetchUserProfile(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    final path = '/users/${Uri.encodeComponent(normalized)}/profile';
    final res = await get(path, retry: true, treat404AsNull: true);

    if (res == null) return null;
    if (res is Map) return Map<String, dynamic>.from(res);

    return {'raw': res};
  }

  /// Convenience: fetch only: name, email, phone, actualBalance
  static Future<Map<String, dynamic>?> fetchClientInfo(String email) async {
    final profile = await fetchUserProfile(email);
    if (profile == null) return null;

    final root = (profile['profile'] is Map)
        ? Map<String, dynamic>.from(profile['profile'] as Map)
        : (profile['user'] is Map)
            ? Map<String, dynamic>.from(profile['user'] as Map)
            : (profile['client'] is Map)
                ? Map<String, dynamic>.from(profile['client'] as Map)
                : profile;

    final balances = (root['balances'] is Map)
        ? Map<String, dynamic>.from(root['balances'] as Map)
        : (profile['balances'] is Map)
            ? Map<String, dynamic>.from(profile['balances'] as Map)
            : <String, dynamic>{};

    final name = (root['name'] ?? profile['name'] ?? '').toString();
    final em = (root['email'] ?? profile['email'] ?? email).toString();
    final phone = (root['phone'] ?? profile['phone'] ?? '').toString();

    final abRaw =
        balances['actualBalance'] ?? balances['actual_balance'] ?? root['actualBalance'] ?? root['actual_balance'];

    final actualBalance = _extractAmountForApi(abRaw);

    return {
      'name': name,
      'email': em,
      'phone': phone,
      'actualBalance': actualBalance,
      'raw': profile,
    };
  }

  // -------------------- AUTH HEADER MANAGEMENT --------------------
  static void setAuthToken(String token) {
    defaultHeaders = {...defaultHeaders, 'Authorization': 'Bearer $token'};
  }

  static void clearAuthToken() {
    final h = {...defaultHeaders};
    h.remove('Authorization');
    defaultHeaders = h;
  }

  static void setHeader(String key, String value) {
    defaultHeaders = {...defaultHeaders, key: value};
  }

  static void removeHeader(String key) {
    final h = {...defaultHeaders};
    h.remove(key);
    defaultHeaders = h;
  }
}  //i think its okay - remove the logic for client edit screen and give me the full api 