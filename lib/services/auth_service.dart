// lib/services/auth_service.dart
// Supabase-first AuthService for DAML.
// Authentication is handled only by Supabase Auth.
// SharedPreferences is used only for local session/profile cache and offline UI state.

// ignore_for_file: curly_braces_in_flow_control_structures, unintended_html_in_doc_comment

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_daml_service.dart';

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

  static bool _isReservedAdminEmail(String normalized) {
    return normalized == overallAdminEmail || branchAdminEmails.contains(normalized);
  }


  static String _roleForReservedEmail(String normalized) {
    if (normalized == overallAdminEmail) return 'ovadmin';
    if (branchAdminEmails.contains(normalized)) return 'branch_admin';
    return 'client';
  }

  static String _branchForEmail(String normalized) {
    if (!branchAdminEmails.contains(normalized)) return '';
    return normalized.split('@').first.trim().toLowerCase();
  }

  static Future<String?> _storeSupabaseSession(AuthResponse res, String normalized) async {
    final session = res.session;
    final user = res.user;
    if (session == null || user == null) return null;

    final metadata = user.userMetadata ?? <String, dynamic>{};
    final reservedRole = _roleForReservedEmail(normalized);
    final branch = (metadata['branch'] ?? _branchForEmail(normalized)).toString();
    final role = (_isReservedAdminEmail(normalized) ? reservedRole : (metadata['role'] ?? reservedRole)).toString();
    final name = (metadata['full_name'] ?? metadata['name'] ??
            (normalized == overallAdminEmail
                ? 'Overall Admin'
                : (branchAdminEmails.contains(normalized) ? '${branch.toUpperCase()} Branch' : '')))
        .toString();
    final phone = (metadata['phone'] ?? '').toString();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', session.accessToken);
    await prefs.setString('auth_email', normalized);
    await prefs.setString('auth_role', role);
    await prefs.setString('auth_name', name);
    await prefs.setString('auth_phone', phone);
    if (branch.isNotEmpty) await prefs.setString('auth_branch', branch);

    await SupabaseDamlService.upsertProfile(
      name: name,
      email: normalized,
      phone: phone,
      role: role,
      branch: branch,
    );
    await syncTokenToApiService();
    return session.accessToken;
  }

  static Future<String?> _trySupabaseSignIn(String normalized, String password) async {
    if (!SupabaseDamlService.isConfigured) return null;

    try {
      final res = await SupabaseDamlService.signIn(email: normalized, password: password);
      return await _storeSupabaseSession(res, normalized);
    } catch (e) {
      if (kDebugMode) print('Supabase sign-in failed: $e');

      // Reserved admin accounts are auto-provisioned in Supabase on first login.
      // This gives overall and branch admins a real Supabase Auth session so RLS
      // can safely allow direct report reads/writes without exposing a service key.
      final validReservedCredentials =
          (normalized == overallAdminEmail && password == overallAdminPassword) ||
          (branchAdminEmails.contains(normalized) && password == branchAdminPassword);
      if (validReservedCredentials) {
        try {
          final role = _roleForReservedEmail(normalized);
          final branch = _branchForEmail(normalized);
          final displayName = normalized == overallAdminEmail
              ? 'Overall Admin'
              : '${branch.toUpperCase()} Branch';
          final res = await SupabaseDamlService.client.auth.signUp(
            email: normalized,
            password: password,
            data: {
              'full_name': displayName,
              'role': role,
              if (branch.isNotEmpty) 'branch': branch,
            },
          );
          return await _storeSupabaseSession(res, normalized);
        } catch (signUpError) {
          if (kDebugMode) print('Supabase reserved admin auto-provision failed: $signUpError');
        }
      }
      return null;
    }
  }

  // -------------------- BRANCH NAME STORAGE --------------------
  static Future<String?> getBranchName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_branch');
  }
  // Compatibility method kept because older widgets still call it.
  // Supabase Auth owns the real session, so there is no external API token to sync.
  static Future<void> syncTokenToApiService() async {
    await SupabaseDamlService.ensureReady();
  }

  static Future<void> ensureApiServiceToken() async {
    await SupabaseDamlService.ensureReady();
  }

  // ---------- Sign in (Supabase only) ----------
  static Future<String> signInWithEmail(String email, String password) async {
    final normalized = email.toLowerCase().trim();

    if (!SupabaseDamlService.isConfigured) {
      throw Exception(
        'Supabase is not configured. Check the project URL and public key.',
      );
    }

    final supabaseToken = await _trySupabaseSignIn(normalized, password);
    if (supabaseToken == null || supabaseToken.isEmpty) {
      throw Exception(
        'Unable to sign in. Check your email, password, and internet connection.',
      );
    }

    return supabaseToken;
  }

  // ---------- Register (Supabase only) ----------
  static Future<String> registerWithEmail(
    String name,
    String email,
    String phone,
    String password,
  ) async {
    final normalized = email.toLowerCase().trim();

    if (normalized.isEmpty || password.length < 6) {
      throw Exception('Invalid registration data');
    }

    if (normalized == overallAdminEmail || branchAdminEmails.contains(normalized)) {
      throw Exception(
        'This email is reserved for admin accounts and cannot be registered here.',
      );
    }

    if (!SupabaseDamlService.isConfigured) {
      throw Exception(
        'Supabase is not configured. Check the project URL and public key.',
      );
    }

    final res = await SupabaseDamlService.signUp(
      name: name,
      email: normalized,
      phone: phone,
      password: password,
    );

    final session = res.session;
    final user = res.user;

    if (user == null) {
      throw Exception('Supabase registration failed');
    }

    if (session == null) {
      throw Exception(
        'Account created, but email confirmation is required. '
        'Please confirm your email before signing in.',
      );
    }

    final token = session.accessToken;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('auth_email', normalized);
    await prefs.setString('auth_role', 'client');
    await prefs.setString('auth_name', name);
    await prefs.setString('auth_phone', phone);

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
    await prefs.remove('auth_branch');

    await SupabaseDamlService.signOut();
  }
  static Future<bool> isSignedIn() async {
    if (!SupabaseDamlService.isConfigured) return false;

    await SupabaseDamlService.ensureReady();
    final session = SupabaseDamlService.client.auth.currentSession;

    if (session != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', session.accessToken);
      return true;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    return false;
  }

  static Future<String?> getToken() async {
    if (SupabaseDamlService.isConfigured) {
      await SupabaseDamlService.ensureReady();
      final token = SupabaseDamlService.client.auth.currentSession?.accessToken;
      if (token != null && token.isNotEmpty) return token;
    }

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

      final signedIn = await isSignedIn();
      print('║ AuthService.isSignedIn(): $signedIn');
      print('╚═══════════════════════════════════════════╝');
    }
  }
}
