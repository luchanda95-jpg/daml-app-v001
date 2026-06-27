// lib/services/auth_service.dart
// Remote-first AuthService with SharedPreferences fallback (local user store + balances).
// Uses ApiClient for remote auth/health only.
// UPDATED: Now syncs tokens with ApiService for cross-service compatibility

// ignore_for_file: curly_braces_in_flow_control_structures, unintended_html_in_doc_comment

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'api_service.dart'; // Added import for ApiService

class AuthService {
  AuthService._();

  // --------- Reserved admin accounts (roles are fixed) ----------
  static const String overallAdminEmail = 'directaccessmoney@gmail.com';
  static final Set<String> branchAdminEmails = {
    'monze@directaccess.com',
    'mazabuka@directaccess.com',
    'lusaka@directaccess.com',
    'solwezi@directaccess.com',
    'lumezi@directaccess.com',
    'nakonde@directaccess.com',

    // ✅ Added
    'mbala@directaccess.com',
    'kitwe@directaccess.com',
  };

  // Passwords for reserved accounts (DEV ONLY)
  static const String branchAdminPassword = 'admin';
  static const String overallAdminPassword = 'ovadmin';

  // Key for persisted users (clients)
  static const String _kUsersKey = 'auth_users';
  static const String _kAdminSubmissionsKey = 'admin_submissions';

  // Remote API base (set to your base)
  // NOTE: no trailing slash required; ApiClient will normalize.
  static String? apiBase = 'https://directaccessapi.onrender.com';

  // Api client instance (created on demand)
  static ApiClient get _apiClient => ApiClient(baseUrl: apiBase ?? '', client: http.Client());

  // Small timeouts / checks
  static Future<bool> _serverAvailable() async {
    if (apiBase == null) return false;
    try {
      return await _apiClient.healthcheck();
    } catch (_) {
      return false;
    }
  }

  // -------------------- BRANCH NAME STORAGE --------------------
  static Future<String?> getBranchName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_branch');
  }

  // ============ SOLUTION 1: TOKEN SYNC WITH API SERVICE ============

  /// Sync the current auth token to ApiService
  static Future<void> syncTokenToApiService() async {
    final token = await getToken();
    if (token != null && token.isNotEmpty) {
      ApiService.setAuthToken(token);
      if (kDebugMode) {
        final shortToken = token.length > 20 ? '${token.substring(0, 20)}...' : token;
        print('[AuthService] Token synced to ApiService: $shortToken');
      }
    } else {
      ApiService.clearAuthToken();
      if (kDebugMode) {
        print('[AuthService] No token found, cleared ApiService auth');
      }
    }
  }

  /// Manually trigger token sync (useful for app initialization)
  static Future<void> ensureApiServiceToken() async {
    await syncTokenToApiService();
  }

  // ------------ local users helpers -------------
  static Future<Map<String, dynamic>> _loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kUsersKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveUsers(Map<String, dynamic> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUsersKey, json.encode(users));
  }

  // local sign-in logic
  static Future<String> _signInLocal(String normalized, String password) async {
    // Reserved overall admin
    if (normalized == overallAdminEmail) {
      if (password == overallAdminPassword) {
        final token = 'ovadmin-token-${DateTime.now().millisecondsSinceEpoch}';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', token);
        await prefs.setString('auth_email', normalized);
        await prefs.setString('auth_role', 'ovadmin');
        return token;
      } else {
        throw Exception('Invalid credentials');
      }
    }

    // Branch admin
    if (branchAdminEmails.contains(normalized)) {
      if (password == branchAdminPassword) {
        final token = 'branch-token-${DateTime.now().millisecondsSinceEpoch}';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', token);
        await prefs.setString('auth_email', normalized);
        await prefs.setString('auth_role', 'branch_admin');
        return token;
      } else {
        throw Exception('Invalid credentials');
      }
    }

    // Persisted client users
    final users = await _loadUsers();
    if (users.containsKey(normalized)) {
      final dynamicEntry = users[normalized];
      if (dynamicEntry is Map) {
        final entry = Map<String, dynamic>.from(dynamicEntry);
        if (entry['password'] == password) {
          final role = entry['role'] as String? ?? 'client';
          final token = 'client-token-${DateTime.now().millisecondsSinceEpoch}';
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', token);
          await prefs.setString('auth_email', normalized);
          await prefs.setString('auth_role', role);
          await prefs.setString('auth_name', (entry['name'] ?? '').toString());
          await prefs.setString('auth_phone', (entry['phone'] ?? '').toString());
          return token;
        }
      }
    }

    throw Exception('Invalid credentials');
  }

  // ---------- Utility: read persisted (local) registered users ----------
  /// Returns a map keyed by normalized email -> user entry (Map<String,dynamic>).
  static Future<Map<String, Map<String, dynamic>>> getAllLocalUsers() async {
    final users = await _loadUsers();
    final out = <String, Map<String, dynamic>>{};
    users.forEach((email, entry) {
      if (entry is Map) out[email.toString()] = Map<String, dynamic>.from(entry);
    });
    return out;
  }

  /// Returns a simple List of user summaries suitable for UI display.
  /// Each element contains keys: 'email', 'name', 'phone', 'role'.
  static Future<List<Map<String, String>>> getRegisteredUsersList() async {
    final raw = await getAllLocalUsers();
    final out = <Map<String, String>>[];
    raw.forEach((email, entry) {
      out.add({
        'email': email,
        'name': (entry['name'] ?? '').toString(),
        'phone': (entry['phone'] ?? '').toString(),
        'role': (entry['role'] ?? 'client').toString(),
      });
    });
    return out;
  }

  // ---------- Sign in (remote-first, fallback to local) ----------
  static Future<String> signInWithEmail(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final normalized = email.toLowerCase().trim();

    if (await _serverAvailable()) {
      try {
        // ApiClient.login returns a User model which includes token & email
        final user = await _apiClient.login(normalized, password);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', user.token);
        await prefs.setString('auth_email', user.email.toLowerCase().trim());
        await prefs.setString('auth_role', user.role);
        await prefs.setString('auth_name', user.name);
        await prefs.setString('auth_phone', user.phone);

        await syncTokenToApiService();
        return user.token;
      } catch (e) {
        if (kDebugMode) print('Remote login failed, falling back locally: $e');
      }
    }

    final token = await _signInLocal(normalized, password);
    await syncTokenToApiService();
    return token;
  }

  // ---------- Register (remote-first, fallback to local) ----------
  static Future<String> registerWithEmail(String name, String email, String phone, String password) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final normalized = email.toLowerCase().trim();

    if (normalized.isEmpty || password.length < 6) {
      throw Exception('Invalid registration data');
    }

    if (normalized == overallAdminEmail || branchAdminEmails.contains(normalized)) {
      throw Exception('This email is reserved for admin accounts and cannot be registered here.');
    }

    if (await _serverAvailable()) {
      try {
        // ApiClient.register returns a User model (token included)
        final user = await _apiClient.register(name, normalized, phone, password);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', user.token);
        await prefs.setString('auth_email', user.email.toLowerCase().trim());
        await prefs.setString('auth_role', user.role);
        await prefs.setString('auth_name', user.name);
        await prefs.setString('auth_phone', user.phone);

        await syncTokenToApiService();
        return user.token;
      } catch (e) {
        if (kDebugMode) print('Remote register failed, falling back locally: $e');
      }
    }

    final users = await _loadUsers();
    if (users.containsKey(normalized)) throw Exception('Email already registered');

    users[normalized] = <String, dynamic>{
      'password': password,
      'role': 'client',
      'name': name,
      'phone': phone,
    };
    await _saveUsers(users);

    final token = 'client-token-registered-${Random().nextInt(999999)}';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('auth_email', normalized);
    await prefs.setString('auth_role', 'client');
    await prefs.setString('auth_name', name);
    await prefs.setString('auth_phone', phone);

    await syncTokenToApiService();
    return token;
  }

  // ---------- OTP (simple stub) ----------
  static Future<void> sendOtp(String phone) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final otp = _generateOtp();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_otp', otp);
    await prefs.setString('pending_otp_phone', phone);
    // ignore: avoid_print
    print('DEBUG: OTP for $phone is $otp');
  }

  static Future<bool> verifyOtp(String phone, String otp) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final prefs = await SharedPreferences.getInstance();
    final expected = prefs.getString('pending_otp');
    final expectedPhone = prefs.getString('pending_otp_phone');
    if (expected != null && expectedPhone != null && expectedPhone == phone && expected == otp) {
      await prefs.remove('pending_otp');
      await prefs.remove('pending_otp_phone');
      return true;
    }
    return false;
  }

  static String _generateOtp() {
    final rnd = Random();
    return (rnd.nextInt(900000) + 100000).toString();
  }

  // ---------- Sign out / helpers ----------
  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_email');
    await prefs.remove('auth_role');
    await prefs.remove('auth_name');
    await prefs.remove('auth_phone');

    ApiService.clearAuthToken();
  }

  static Future<bool> isSignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return token != null && token.trim().isNotEmpty;
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_role');
  }

  static Future<Map<String, String>> getLocalProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'email': prefs.getString('auth_email') ?? '',
      'name': prefs.getString('auth_name') ?? '',
      'phone': prefs.getString('auth_phone') ?? '',
      'role': prefs.getString('auth_role') ?? 'client',
    };
  }

  // -------------------- PROFILE HELPERS (your added methods) --------------------
  static Future<Map<String, String>> getValidatedProfile() async {
    final profile = await getLocalProfile();
    final email = (profile['email'] ?? '').trim().toLowerCase();
    final phone = (profile['phone'] ?? '').trim();
    final name = (profile['name'] ?? '').trim();

    if (email.isEmpty && phone.isEmpty && name.isEmpty) {
      throw Exception(
        'Your profile is missing contact information. '
        'Please update your email, phone number, or name in account settings.',
      );
    }

    return {'email': email, 'phone': phone, 'name': name};
  }

  static Future<bool> isProfileCompleteForLoans() async {
    final profile = await getLocalProfile();
    final hasEmail = (profile['email'] ?? '').trim().isNotEmpty;
    final hasPhone = (profile['phone'] ?? '').trim().isNotEmpty;
    final hasName = (profile['name'] ?? '').trim().isNotEmpty;
    return hasEmail || hasPhone || hasName;
  }

  static Future<void> updateProfileForLoanMatching({
    required String email,
    required String phone,
    required String name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_email', email.trim().toLowerCase());
    await prefs.setString('auth_phone', phone.trim());
    await prefs.setString('auth_name', name.trim());
  }

  // ---------- Balances (LOCAL ONLY) ----------
  static Future<void> setBalancesForUser(
    String email, {
    required double amountBorrowed,
    required double amountPaid,
    required double actualBalance,
    double interestRate = 0.0,
    double? nextPaymentAmount,
    DateTime? nextPaymentDate,
  }) async {
    final normalized = email.toLowerCase().trim();

    final payload = <String, dynamic>{
      'amountBorrowed': amountBorrowed,
      'amountPaid': amountPaid,
      'actualBalance': actualBalance,
      'interestRate': interestRate,
      if (nextPaymentAmount != null || nextPaymentDate != null)
        'next_payment': {
          if (nextPaymentAmount != null) 'amount': nextPaymentAmount,
          if (nextPaymentDate != null) 'date': nextPaymentDate.toIso8601String(),
        }
    };

    await _saveBalancesLocally(normalized, payload, updatedAt: DateTime.now().toIso8601String());
  }

  static Future<void> _saveBalancesLocally(
    String normalizedEmail,
    Map<String, dynamic> payload, {
    String? updatedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '_balances_$normalizedEmail';
    final decoded = Map<String, dynamic>.from(payload);
    decoded['updatedAt'] = updatedAt ?? DateTime.now().toIso8601String();
    await prefs.setString(key, json.encode(decoded));
  }

  static Future<Map<String, double>> getBalancesForUser(String email) async {
    final normalized = email.toLowerCase().trim();
    return _getBalancesLocally(normalized);
  }

  static Future<Map<String, double>> _getBalancesLocally(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '_balances_${email.toLowerCase().trim()}';
    final raw = prefs.getString(key);

    if (raw == null || raw.isEmpty) {
      return {'amountBorrowed': 0.0, 'amountPaid': 0.0, 'actualBalance': 0.0, 'interestRate': 0.0};
    }

    try {
      final decodedRaw = json.decode(raw);
      if (decodedRaw is! Map) {
        return {'amountBorrowed': 0.0, 'amountPaid': 0.0, 'actualBalance': 0.0, 'interestRate': 0.0};
      }
      final decoded = Map<String, dynamic>.from(decodedRaw);

      double toDouble(dynamic x) {
        if (x == null) return 0.0;
        if (x is double) return x;
        if (x is int) return x.toDouble();
        if (x is String) return double.tryParse(x) ?? 0.0;
        return 0.0;
      }

      return {
        'amountBorrowed': toDouble(decoded['amountBorrowed']),
        'amountPaid': toDouble(decoded['amountPaid']),
        'actualBalance': toDouble(decoded['actualBalance']),
        'interestRate': toDouble(decoded['interestRate']),
      };
    } catch (_) {
      return {'amountBorrowed': 0.0, 'amountPaid': 0.0, 'actualBalance': 0.0, 'interestRate': 0.0};
    }
  }

  static Future<Map<String, double>> getBalancesForCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('auth_email') ?? '';
    if (email.isEmpty) {
      return {'amountBorrowed': 0.0, 'amountPaid': 0.0, 'actualBalance': 0.0, 'interestRate': 0.0};
    }
    return getBalancesForUser(email);
  }

  static Future<Map<String, dynamic>?> getNextPaymentForUser(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '_balances_${email.toLowerCase().trim()}';
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decodedRaw = json.decode(raw);
      if (decodedRaw is! Map) return null;

      final decoded = Map<String, dynamic>.from(decodedRaw);
      final np = decoded['next_payment'];
      if (np == null || np is! Map) return null;

      double? amount;
      if (np.containsKey('amount')) {
        final a = np['amount'];
        if (a is double) amount = a;
        else if (a is int) amount = a.toDouble();
        else amount = double.tryParse(a.toString());
      }

      DateTime? date;
      if (np.containsKey('date')) {
        final d = np['date'];
        if (d is String) date = DateTime.tryParse(d);
        else if (d is DateTime) date = d;
      }

      return {if (amount != null) 'amount': amount, if (date != null) 'date': date};
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getNextPaymentForCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('auth_email') ?? '';
    if (email.isEmpty) return null;
    return getNextPaymentForUser(email);
  }

  // ---------- Notifications (LOCAL ONLY) ----------
  static Future<void> addNotificationForUser(
    String email, {
    required String title,
    required String message,
    String type = 'info',
  }) async {
    final normalized = email.toLowerCase().trim();

    final prefs = await SharedPreferences.getInstance();
    final key = '_balances_$normalized';

    Map<String, dynamic> decoded = {};
    final raw = prefs.getString(key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final d = json.decode(raw);
        if (d is Map) decoded = Map<String, dynamic>.from(d);
      } catch (_) {
        decoded = {};
      }
    }

    final List<dynamic> notifications =
        (decoded['notifications'] is List) ? List<dynamic>.from(decoded['notifications'] as List) : <dynamic>[];

    final n = <String, dynamic>{
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': title,
      'message': message,
      'type': type,
      'ts': DateTime.now().toIso8601String(),
    };

    notifications.insert(0, n);
    decoded['notifications'] = notifications;
    await prefs.setString(key, json.encode(decoded));
  }

  static Future<List<Map<String, dynamic>>> getNotificationsForUser(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '_balances_${email.toLowerCase().trim()}';
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decodedRaw = json.decode(raw);
      if (decodedRaw is! Map) return [];
      final decoded = Map<String, dynamic>.from(decodedRaw);

      final list = decoded['notifications'];
      if (list == null || list is! List) return [];

      final out = <Map<String, dynamic>>[];
      for (final e in list) {
        if (e is Map) out.add(Map<String, dynamic>.from(e));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<void> clearNotificationsForUser(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '_balances_${email.toLowerCase().trim()}';
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return;

    try {
      final decodedRaw = json.decode(raw);
      if (decodedRaw is! Map) return;
      final decoded = Map<String, dynamic>.from(decodedRaw);
      decoded.remove('notifications');
      await prefs.setString(key, json.encode(decoded));
    } catch (_) {}
  }

  static Future<void> clearNotificationsForCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('auth_email') ?? '';
    if (email.isEmpty) return;
    await clearNotificationsForUser(email);
  }

  static Future<List<Map<String, dynamic>>> getNotificationsForCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('auth_email') ?? '';
    if (email.isEmpty) return [];
    return getNotificationsForUser(email);
  }

  // ---------- DEBUG METHOD ----------
  static Future<void> debugAuthState() async {
    if (kDebugMode) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final email = prefs.getString('auth_email');
      final role = prefs.getString('auth_role');
      final name = prefs.getString('auth_name');
      final phone = prefs.getString('auth_phone');

      print('╔═══════════════════════════════════════════╗');
      print('║           AUTH STATE DEBUG                ║');
      print('╠═══════════════════════════════════════════╣');
      print('║ Token exists: ${token != null && token.isNotEmpty}');
      print('║ Token length: ${token?.length ?? 0}');
      if (token != null && token.isNotEmpty) {
        print('║ Token preview: ${token.substring(0, min(30, token.length))}...');
      }
      print('║ Email: ${email ?? "Not set"}');
      print('║ Role: ${role ?? "Not set"}');
      print('║ Name: ${name ?? "Not set"}');
      print('║ Phone: ${phone ?? "Not set"}');
      print('║ ApiService auth header: ${ApiService.defaultHeaders.containsKey('Authorization')}');

      final signedIn = await isSignedIn();
      print('║ AuthService.isSignedIn(): $signedIn');
      print('╚═══════════════════════════════════════════╝');
    }
  }

  // ---------- Admin submissions (LOCAL ONLY) ----------
  static Future<void> addAdminSubmission(Map<String, dynamic> submission) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAdminSubmissionsKey) ?? '[]';

    List<dynamic> list;
    try {
      final decoded = json.decode(raw);
      list = decoded is List ? decoded : <dynamic>[];
    } catch (_) {
      list = <dynamic>[];
    }

    list.insert(0, submission);
    await prefs.setString(_kAdminSubmissionsKey, json.encode(list));
  }

  static Future<List<Map<String, dynamic>>> getAdminSubmissions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAdminSubmissionsKey) ?? '[]';

    try {
      final decoded = json.decode(raw);
      if (decoded is List) {
        final out = <Map<String, dynamic>>[];
        for (final e in decoded) {
          if (e is Map) out.add(Map<String, dynamic>.from(e));
        }
        return out;
      }
    } catch (_) {}

    return <Map<String, dynamic>>[];
  }

  static Future<void> removeAdminSubmissionById(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAdminSubmissionsKey) ?? '[]';

    List<dynamic> list;
    try {
      final decoded = json.decode(raw);
      list = decoded is List ? decoded : <dynamic>[];
    } catch (_) {
      list = <dynamic>[];
    }

    list.removeWhere((e) => e is Map && e['id']?.toString() == id);
    await prefs.setString(_kAdminSubmissionsKey, json.encode(list));
  }
}
