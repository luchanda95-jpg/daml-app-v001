// lib/services/supabase_daml_service.dart
// Direct Supabase backend for DAML Flutter app.
// Handles: Auth, legacy loan search, client dashboard data, application PDF upload,
// admin application list, notifications.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class SupabaseDamlService {
  SupabaseDamlService._();

  static bool _initialized = false;

  static bool get isConfigured => SupabaseConfig.isConfigured;

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    if (_initialized) return;
    if (!SupabaseConfig.isConfigured) {
      if (kDebugMode) {
        debugPrint('[SupabaseDamlService] Supabase is not configured. Backend operations are disabled.');
      }
      return;
    }

    await Supabase.initialize(
      url: SupabaseConfig.url,
      // ignore: deprecated_member_use
      anonKey: SupabaseConfig.anonKey,
    );
    _initialized = true;

    if (kDebugMode) debugPrint('[SupabaseDamlService] Supabase initialized.');
  }

  static Future<void> ensureReady() async {
    if (!_initialized) await initialize();
    if (!_initialized) {
      throw Exception('Supabase is not configured. Set SUPABASE_URL and SUPABASE_ANON_KEY.');
    }
  }

  static String normalizePhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '').trim();
    if (cleaned.startsWith('+260')) return '0${cleaned.substring(4)}';
    if (cleaned.startsWith('260')) return '0${cleaned.substring(3)}';
    return cleaned;
  }

  static double parseAmount(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '').trim()) ?? 0.0;
  }



  static bool _statusLooksCleared(String status) {
    final s = status.toLowerCase();
    return s.contains('fully paid') ||
        s.contains('cleared') ||
        s.contains('closed') ||
        s.contains('paid off') ||
        s.contains('write-off') ||
        s.contains('written off') ||
        s.contains('cancelled') ||
        s.contains('canceled');
  }

  static double currentBalanceFromLoanRow(Map<String, dynamic> row) {
    final status = (row['loanStatus'] ?? row['loan_status'] ?? '').toString();
    if (_statusLooksCleared(status)) return 0.0;

    final currentBalance = parseAmount(row['currentBalance'] ?? row['current_balance']);
    if (currentBalance > 0) return currentBalance;

    final balanceAmount = parseAmount(row['balanceAmount'] ?? row['balance_amount']);
    if (balanceAmount > 0) return balanceAmount;

    final pendingDue = parseAmount(row['pendingDue'] ?? row['pending_due']);
    if (pendingDue > 0) return pendingDue;

    final pendingBreakdown =
        parseAmount(row['pendingPrincipalDue'] ?? row['pending_principal_due']) +
            parseAmount(row['pendingInterestDue'] ?? row['pending_interest_due']) +
            parseAmount(row['pendingPenaltyDue'] ?? row['pending_penalty_due']) +
            parseAmount(row['pendingFeesDue'] ?? row['pending_fees_due']);
    if (pendingBreakdown > 0) return pendingBreakdown;

    final due = parseAmount(row['amortizationDue'] ?? row['amortization_due']) +
        parseAmount(row['totalInterestBalance'] ?? row['total_interest_balance']) +
        parseAmount(row['penaltyAmount'] ?? row['penalty_amount']);
    return due > 0 ? due : 0.0;
  }

  static bool _isCurrentLoanRow(Map<String, dynamic> row) {
    return currentBalanceFromLoanRow(row) > 0;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  static Map<String, dynamic> _normalizeDashboardResponse(dynamic res, {required bool includeLoans}) {
    if (res is List && res.isNotEmpty) {
      return _normalizeDashboardResponse(res.first, includeLoans: includeLoans);
    }
    if (res is! Map) {
      throw Exception('Invalid Supabase dashboard response.');
    }

    final map = Map<String, dynamic>.from(res);
    final clientData = map['client'] is Map ? Map<String, dynamic>.from(map['client'] as Map) : <String, dynamic>{};
    final summaryData = map['loansSummary'] is Map
        ? Map<String, dynamic>.from(map['loansSummary'] as Map)
        : (map['loans_summary'] is Map ? Map<String, dynamic>.from(map['loans_summary'] as Map) : <String, dynamic>{});
    final rawLoans = map['loans'] is List ? map['loans'] as List : const <dynamic>[];

    final rawBalance = parseAmount(clientData['balance'] ?? summaryData['totalBalance'] ?? summaryData['total_balance']);
    final balance = rawBalance > 0.01 ? rawBalance : 0.0;

    // The live dashboard represents only the current account.
    // When cleared, historical principal/count must not leak back into the UI.
    final rawBorrowed = parseAmount(summaryData['totalBorrowed'] ?? summaryData['total_borrowed']);
    final currentBorrowed = balance > 0.0 ? rawBorrowed : 0.0;
    final rawLoanCount = summaryData['loanCount'] ?? summaryData['loan_count'] ?? 0;
    final currentLoanCount = balance > 0.0 ? rawLoanCount : 0;

    final status = (clientData['loanStatus'] ?? clientData['loan_status'] ?? (balance > 0 ? 'Active' : 'Cleared')).toString();
    final bucket = (clientData['statusBucket'] ?? clientData['status_bucket'] ?? (balance > 0 ? 'balance' : 'cleared')).toString();

    return {
      'success': map['success'] ?? true,
      'client': {
        'clientKey': clientData['clientKey'] ?? clientData['client_key'] ?? '',
        'fullName': clientData['fullName'] ?? clientData['full_name'] ?? clientData['client_name'] ?? '',
        'email': clientData['email'] ?? clientData['client_email'] ?? '',
        'phone': clientData['phone'] ?? clientData['client_phone'] ?? '',
        'balance': balance,
        'loanStatus': status,
        'statusBucket': bucket,
        'isExtended': clientData['isExtended'] ?? clientData['is_extended'] ?? false,
        'updatedAt': clientData['updatedAt'] ?? clientData['updated_at'] ?? map['lastUpdated'] ?? map['last_updated'],
      },
      'loansSummary': {
        'loanCount': currentLoanCount,
        'totalBorrowed': currentBorrowed,
        'totalBalance': balance,
        'nextDueDate': summaryData['nextDueDate'] ?? summaryData['next_due_date'],
        'nextDueAmount': parseAmount(summaryData['nextDueAmount'] ?? summaryData['next_due_amount']),
        'source': summaryData['source'] ?? map['source'] ?? 'supabase',
        'pastLoanCount': summaryData['pastLoanCount'] ?? summaryData['past_loan_count'] ?? 0,
      },
      if (includeLoans)
        'loans': rawLoans.whereType<Map>().map((loan) {
          final l = Map<String, dynamic>.from(loan);
          return legacyLoanToAppLoan(l);
        }).toList(),
    };
  }

  static String _safeFileSegment(String value) {
    final safe = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return safe.isEmpty ? 'client' : safe;
  }

  static String _loanId(Map<String, dynamic> row) {
    return (row['id'] ?? row['loan_id'] ?? row['loan_number'] ?? row['source_row_hash'] ?? '').toString();
  }

  static String _nameFromRow(Map<String, dynamic> row) {
    return (row['full_name'] ?? row['fullName'] ?? row['name'] ?? '').toString();
  }

  static Map<String, dynamic> legacyLoanToAppLoan(Map<String, dynamic> row) {
    // The existing app model understands camelCase and snake_case; we provide both for safety.
    final id = _loanId(row);
    final fullName = _nameFromRow(row);
    return {
      ...row,
      'id': id,
      '_id': id,
      'fullName': fullName,
      'borrowerMobile': row['borrower_mobile'] ?? row['borrowerMobile'] ?? row['phone'],
      'borrowerEmail': row['borrower_email'] ?? row['borrowerEmail'] ?? row['email'],
      'borrowerAddress': row['borrower_address'] ?? row['borrowerAddress'] ?? row['address'],
      'loanStatus': row['loan_status'] ?? row['loanStatus'] ?? 'Unknown',
      'principalAmount': row['principal_amount'] ?? row['principalAmount'] ?? 0,
      'totalInterestBalance': row['total_interest_balance'] ?? row['totalInterestBalance'] ?? 0,
      'amortizationDue': row['amortization_due'] ?? row['amortizationDue'] ?? row['currentBalance'] ?? 0,
      'nextInstallmentAmount': row['next_installment_amount'] ?? row['nextInstallmentAmount'] ?? 0,
      'nextDueDate': row['next_due_date'] ?? row['nextDueDate'],
      'penaltyAmount': row['penalty_amount'] ?? row['penaltyAmount'] ?? 0,
      'balanceAmount': row['balance_amount'] ?? row['balanceAmount'] ?? 0,
      'pendingDue': row['pending_due'] ?? row['pendingDue'] ?? 0,
      'pendingPrincipalDue': row['pending_principal_due'] ?? row['pendingPrincipalDue'] ?? 0,
      'pendingInterestDue': row['pending_interest_due'] ?? row['pendingInterestDue'] ?? 0,
      'pendingPenaltyDue': row['pending_penalty_due'] ?? row['pendingPenaltyDue'] ?? 0,
      'pendingFeesDue': row['pending_fees_due'] ?? row['pendingFeesDue'] ?? 0,
      'currentBalance': currentBalanceFromLoanRow(row),
      'branchId': row['source_file'] ?? row['source'] ?? '',
      'createdAt': row['created_at'] ?? row['createdAt'],
      'updatedAt': row['updated_at'] ?? row['updatedAt'],
    };
  }

  static Future<AuthResponse> signIn({required String email, required String password}) async {
    await ensureReady();
    return client.auth.signInWithPassword(email: email.trim().toLowerCase(), password: password);
  }

  static Future<AuthResponse> signUp({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    await ensureReady();
    final response = await client.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      data: {
        'full_name': name.trim(),
        'phone': phone.trim(),
        'role': 'client',
      },
    );

    if (response.user != null) {
      await upsertProfile(name: name, email: email, phone: phone, role: 'client');
    }
    return response;
  }

  static Future<void> signOut() async {
    if (!_initialized) return;
    try {
      await client.auth.signOut();
    } catch (_) {}
  }

  static Future<void> upsertProfile({
    required String name,
    required String email,
    required String phone,
    String role = 'client',
    String? branch,
  }) async {
    await ensureReady();
    final user = client.auth.currentUser;
    if (user == null) return;

    await client.from('profiles').upsert({
      'id': user.id,
      'email': email.trim().toLowerCase(),
      'full_name': name.trim(),
      'phone': normalizePhone(phone),
      'role': role,
      if (branch != null && branch.trim().isNotEmpty) 'branch': branch.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> searchMyLegacyLoans({int limit = 20}) async {
    await ensureReady();

    try {
      final res = await client.rpc('search_my_legacy_loans', params: {'p_limit': limit});
      final list = (res as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      return list.map(legacyLoanToAppLoan).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseDamlService] RPC search_my_legacy_loans failed: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchLoansByQuery({
    String? email,
    String? phone,
    String? name,
    int? limit,
    bool exactMatch = false,
  }) async {
    await ensureReady();

    final filters = <String>[];
    String esc(String v) => v.replaceAll(',', ' ').replaceAll('%', '').trim();

    if (email != null && email.trim().isNotEmpty) {
      final e = esc(email.toLowerCase());
      filters.add(exactMatch ? 'borrower_email.eq.$e' : 'borrower_email.ilike.%$e%');
    }
    if (phone != null && phone.trim().isNotEmpty) {
      final p = esc(normalizePhone(phone));
      filters.add(exactMatch ? 'borrower_mobile.eq.$p' : 'borrower_mobile.ilike.%$p%');
    }
    if (name != null && name.trim().isNotEmpty) {
      final n = esc(name);
      filters.add(exactMatch ? 'full_name.eq.$n' : 'full_name.ilike.%$n%');
    }

    if (filters.isEmpty) return <Map<String, dynamic>>[];

    dynamic query = client.from('legacy_loans').select();
    query = query.or(filters.join(','));
    query = query.limit(limit ?? 20);

    final res = await query;
    final list = (res as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    return list.map(legacyLoanToAppLoan).toList();
  }

  static Future<Map<String, dynamic>?> fetchLoanById(String id) async {
    await ensureReady();
    if (id.trim().isEmpty) return null;

    final res = await client
        .from('legacy_loans')
        .select()
        .or('id.eq.$id,loan_id.eq.$id,loan_number.eq.$id,source_row_hash.eq.$id')
        .limit(1);

    final list = (res as List).whereType<Map>().toList();
    if (list.isEmpty) return null;
    return legacyLoanToAppLoan(Map<String, dynamic>.from(list.first));
  }

  static Future<Map<String, dynamic>> fetchMyClientDashboard({bool includeLoans = false}) async {
    await ensureReady();

    // Preferred path: use the Supabase RPC that returns one current account balance.
    // This prevents old/past legacy loans from appearing as active debt.
    try {
      final res = await client.rpc('get_my_current_loan_summary', params: {'p_include_loans': includeLoans});
      return _normalizeDashboardResponse(res, includeLoans: includeLoans);
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseDamlService] RPC get_my_current_loan_summary failed, using local fallback: $e');
    }

    final profile = await getCurrentProfile();
    final allLoans = await searchMyLegacyLoans(limit: includeLoans ? 100 : 50);
    final currentLoans = allLoans.where(_isCurrentLoanRow).map((loan) {
      final balance = currentBalanceFromLoanRow(loan);
      return {
        ...loan,
        'currentBalance': balance,
        'loanStatus': balance > 0 ? (loan['loanStatus'] ?? 'Active') : 'Cleared',
      };
    }).toList();

    final totalBorrowed = currentLoans.fold<double>(0.0, (s, l) => s + parseAmount(l['principalAmount']));
    final totalBalance = currentLoans.fold<double>(0.0, (s, l) => s + currentBalanceFromLoanRow(l));

    DateTime? nextDate;
    double nextDueAmount = 0.0;
    for (final loan in currentLoans) {
      final parsed = _parseDate(loan['nextDueDate'] ?? loan['next_due_date']);
      if (parsed == null) continue;
      if (nextDate == null || parsed.isBefore(nextDate)) {
        nextDate = parsed;
        nextDueAmount = parseAmount(loan['nextInstallmentAmount'] ?? loan['next_installment_amount']);
      }
    }

    final clientName = (profile?['full_name'] ?? profile?['name'] ?? (allLoans.isNotEmpty ? allLoans.first['fullName'] : '')).toString();
    final clientEmail = (profile?['email'] ?? client.auth.currentUser?.email ?? '').toString();
    final clientPhone = (profile?['phone'] ?? (allLoans.isNotEmpty ? allLoans.first['borrowerMobile'] : '') ?? '').toString();
    final hasHistory = allLoans.isNotEmpty;

    return {
      'success': true,
      'client': {
        'clientKey': clientEmail.isNotEmpty ? 'email:$clientEmail' : 'phone:$clientPhone',
        'fullName': clientName,
        'email': clientEmail,
        'phone': clientPhone,
        'balance': totalBalance,
        'loanStatus': totalBalance > 0 ? 'Active' : (hasHistory ? 'Cleared' : 'No Loans'),
        'statusBucket': totalBalance > 0 ? 'balance' : 'cleared',
        'isExtended': false,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      'loansSummary': {
        'loanCount': currentLoans.length,
        'totalBorrowed': totalBorrowed,
        'totalBalance': totalBalance,
        'nextDueDate': nextDate?.toIso8601String(),
        'nextDueAmount': nextDueAmount,
        'source': 'legacy_fallback',
        'pastLoanCount': (allLoans.length - currentLoans.length).clamp(0, allLoans.length),
      },
      if (includeLoans) 'loans': currentLoans,
    };
  }

  static Future<Map<String, dynamic>?> getCurrentProfile() async {
    await ensureReady();
    final user = client.auth.currentUser;
    if (user == null) return null;

    try {
      final res = await client.from('profiles').select().eq('id', user.id).maybeSingle();
      if (res == null) return null;
      return Map<String, dynamic>.from(res as Map);
    } catch (_) {
      return {
        'id': user.id,
        'email': user.email,
        'full_name': user.userMetadata?['full_name'],
        'phone': user.userMetadata?['phone'],
        'role': user.userMetadata?['role'] ?? 'client',
      };
    }
  }

  static Future<Map<String, dynamic>> submitApplicationWithPdf({
    required File pdfFile,
    required Map<String, dynamic> formData,
  }) async {
    await ensureReady();

    final user = client.auth.currentUser;
    if (user == null) {
      throw Exception('Please sign in before submitting an application.');
    }

    final now = DateTime.now().toUtc();
    final safeName = _safeFileSegment((formData['name'] ?? user.email ?? 'client').toString());
    final random = Random().nextInt(999999).toString().padLeft(6, '0');
    final filename = 'DirectAccess_${safeName}_${now.millisecondsSinceEpoch}_$random.pdf';
    final storagePath = 'applications/${now.year}/${now.month.toString().padLeft(2, '0')}/$filename';

    await client.storage.from(SupabaseConfig.applicationBucket).upload(
          storagePath,
          pdfFile,
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
            upsert: false,
          ),
        );

    final inserted = await client
        .from('applications')
        .insert({
          'submitted_by_user_id': user.id,
          'submitted_by_email': user.email,
          'client_name': formData['name'],
          'phone': normalizePhone((formData['mobile'] ?? '').toString()),
          'nrc': formData['nrc'],
          'loan_amount': parseAmount(formData['loanAmount']),
          'loan_purpose': formData['modeOfPayment'],
          'employment_status': formData['employerName'],
          'status': 'pending',
          'pdf_path': storagePath,
          'pdf_filename': filename,
          'form_data': formData,
        })
        .select()
        .single();

    final application = Map<String, dynamic>.from(inserted as Map);

    await client.from('notifications').insert({
      'title': 'New loan application',
      'message': '${formData['name'] ?? 'Client'} submitted a new loan application.',
      'type': 'application',
      'is_read': false,
      'application_id': application['id'],
      'created_by_user_id': user.id,
      'target_role': 'admin',
      'target_email': 'directaccessmoney@gmail.com',
      'data': {
        'application_id': application['id'],
        'pdf_path': storagePath,
        'pdf_filename': filename,
      },
    });

    return application;
  }

  static Future<List<Map<String, dynamic>>> fetchApplicationSubmissions({int limit = 100}) async {
    await ensureReady();
    final res = await client
        .from('applications')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);

    final list = (res as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    return list.map((item) {
      final data = item['form_data'];
      return {
        'id': item['id'],
        'from': item['client_name'] ?? item['submitted_by_email'] ?? item['phone'] ?? 'unknown',
        'ts': item['created_at'],
        'status': item['status'],
        'pdf_path': item['pdf_path'],
        'pdf_filename': item['pdf_filename'],
        'data': data is Map ? Map<String, dynamic>.from(data) : item,
        'raw': item,
      };
    }).toList();
  }

  static Future<String> createPdfSignedUrl(String pdfPath, {int expiresInSeconds = 3600}) async {
    await ensureReady();
    return client.storage.from(SupabaseConfig.applicationBucket).createSignedUrl(pdfPath, expiresInSeconds);
  }

  static String _safePdfFilename(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (cleaned.isEmpty) return 'application.pdf';
    return cleaned.toLowerCase().endsWith('.pdf') ? cleaned : '$cleaned.pdf';
  }

  static Future<Directory> _downloadDirectory() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    } catch (_) {}

    try {
      final external = await getExternalStorageDirectory();
      if (external != null) return external;
    } catch (_) {}

    return getApplicationDocumentsDirectory();
  }

  static Future<File> downloadPdfToDevice(String pdfPath, {String? filename}) async {
    await ensureReady();
    if (pdfPath.trim().isEmpty) {
      throw Exception('No PDF path found for this application.');
    }

    final bytes = await client.storage.from(SupabaseConfig.applicationBucket).download(pdfPath);
    final baseDir = await _downloadDirectory();
    final saveDir = Directory('${baseDir.path}/DAML_Applications');
    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }

    final fallbackName = pdfPath.split('/').isNotEmpty ? pdfPath.split('/').last : 'application.pdf';
    final safeName = _safePdfFilename((filename == null || filename.trim().isEmpty) ? fallbackName : filename);
    final file = File('${saveDir.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> markApplicationHandled(String id, {String status = 'handled'}) async {
    await ensureReady();
    if (id.trim().isEmpty) return;

    // Preferred path: one database function updates application status, creates/updates
    // the client's current loan account when confirmed, and notifies the client.
    try {
      await client.rpc('confirm_application_and_update_loan_account', params: {
        'p_application_id': id,
        'p_status': status,
      });
      return;
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseDamlService] RPC confirm_application_and_update_loan_account failed, using fallback: $e');
    }

    Map<String, dynamic>? application;
    try {
      final res = await client.from('applications').select().eq('id', id).maybeSingle();
      if (res != null) application = Map<String, dynamic>.from(res as Map);
    } catch (_) {}

    await client.from('applications').update({
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);

    if (application != null && (status.toLowerCase() == 'confirmed' || status.toLowerCase() == 'approved')) {
      await _upsertLoanAccountFromApplication(application, status: status);
    }

    final targetEmail = (application?['submitted_by_email'] ?? '').toString().trim().toLowerCase();
    final clientName = (application?['client_name'] ?? 'Client').toString();
    if (targetEmail.isNotEmpty) {
      try {
        await client.from('notifications').insert({
          'title': status == 'confirmed' || status == 'approved' ? 'Loan approved' : 'Application handled',
          'message': status == 'confirmed' || status == 'approved'
              ? '$clientName, your loan has been approved. Your current balance has been updated.'
              : '$clientName, your loan application has been received and handled by Direct Access Money Lending.',
          'type': status == 'confirmed' || status == 'approved' ? 'loan_update' : 'success',
          'is_read': false,
          'application_id': id,
          'target_email': targetEmail,
          'target_role': 'client',
          'data': {
            'application_id': id,
            'status': status,
            'pdf_path': application?['pdf_path'],
            'pdf_filename': application?['pdf_filename'],
          },
        });
      } catch (e) {
        if (kDebugMode) debugPrint('[SupabaseDamlService] Failed to notify client after status update: $e');
      }
    }
  }

  static Future<void> _upsertLoanAccountFromApplication(Map<String, dynamic> application, {required String status}) async {
    final formData = application['form_data'] is Map ? Map<String, dynamic>.from(application['form_data'] as Map) : <String, dynamic>{};
    final applicationId = (application['id'] ?? '').toString();
    if (applicationId.isEmpty) return;

    final loanAmount = parseAmount(application['loan_amount'] ?? formData['loanAmount']);
    final monthlyInstallment = parseAmount(formData['monthlyInstallment']);
    final clientName = (application['client_name'] ?? formData['name'] ?? '').toString();
    final email = (application['submitted_by_email'] ?? '').toString().trim().toLowerCase();
    final phone = normalizePhone((application['phone'] ?? formData['mobile'] ?? '').toString());
    final userId = application['submitted_by_user_id'];

    try {
      await client.from('loan_accounts').upsert({
        'user_id': userId,
        'application_id': applicationId,
        'client_name': clientName,
        'client_email': email,
        'client_phone': phone,
        'source': 'application',
        'principal_amount': loanAmount,
        'current_balance': loanAmount,
        'next_due_amount': monthlyInstallment,
        'next_due_date': formData['loanEnd'],
        'loan_status': status == 'approved' ? 'approved' : 'confirmed',
        'approved_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'metadata': {
          'form_data': formData,
          'pdf_path': application['pdf_path'],
          'pdf_filename': application['pdf_filename'],
        },
      }, onConflict: 'application_id');
    } catch (e) {
      if (kDebugMode) debugPrint('[SupabaseDamlService] Failed to update loan_accounts fallback: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> fetchLoanAccounts({int limit = 500}) async {
    await ensureReady();
    final res = await client
        .from('loan_accounts')
        .select()
        .order('updated_at', ascending: false)
        .limit(limit);
    return (res as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<Map<String, dynamic>> recordLoanPayment({
    required String loanAccountId,
    required double amount,
    String? reference,
    String? notes,
  }) async {
    await ensureReady();
    if (loanAccountId.trim().isEmpty) {
      throw Exception('Loan account is missing.');
    }
    if (amount <= 0) {
      throw Exception('Payment amount must be greater than zero.');
    }

    final res = await client.rpc('record_loan_payment', params: {
      'p_loan_account_id': loanAccountId,
      'p_amount': amount,
      'p_reference': reference?.trim().isEmpty == true ? null : reference?.trim(),
      'p_notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
    });

    if (res is Map) return Map<String, dynamic>.from(res);
    if (res is List && res.isNotEmpty && res.first is Map) {
      return Map<String, dynamic>.from(res.first as Map);
    }
    return {'success': true};
  }

  static Future<Map<String, dynamic>> clearLoanAccount({
    required String loanAccountId,
    String? reason,
  }) async {
    await ensureReady();
    if (loanAccountId.trim().isEmpty) {
      throw Exception('Loan account is missing.');
    }

    final res = await client.rpc('clear_loan_account', params: {
      'p_loan_account_id': loanAccountId,
      'p_reason': reason?.trim().isEmpty == true ? null : reason?.trim(),
    });

    if (res is Map) return Map<String, dynamic>.from(res);
    if (res is List && res.isNotEmpty && res.first is Map) {
      return Map<String, dynamic>.from(res.first as Map);
    }
    return {'success': true};
  }

  static Future<List<Map<String, dynamic>>> fetchNotifications({String? targetEmail, int limit = 50}) async {
    await ensureReady();
    dynamic query = client.from('notifications').select();

    final email = targetEmail?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) {
      query = query.eq('target_email', email);
    }

    final res = await query.order('created_at', ascending: false).limit(limit);
    return (res as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> markAllNotificationsRead({String? targetEmail}) async {
    await ensureReady();
    dynamic query = client.from('notifications').update({'is_read': true}).eq('is_read', false);

    final email = targetEmail?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) {
      query = query.eq('target_email', email);
    }

    await query;
  }

  static Future<List<Map<String, dynamic>>> fetchAdminClientDirectory({String? q, int limit = 10000}) async {
    await ensureReady();

    final safeLimit = limit.clamp(1, 10000).toInt();
    final res = await client.rpc('admin_client_directory', params: {
      'p_query': q?.trim().isEmpty == true ? null : q?.trim(),
      'p_limit': safeLimit,
    });

    final rows = (res as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    String normEmail(dynamic value) => value?.toString().trim().toLowerCase() ?? '';
    String normPhone(dynamic value) => normalizePhone(value?.toString() ?? '');
    String normName(dynamic value) => (value?.toString() ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');

    final merged = <Map<String, dynamic>>[];
    final emailIndex = <String, int>{};
    final phoneIndex = <String, int>{};
    final nameIndex = <String, int>{};

    for (final row in rows) {
      final email = normEmail(row['email']);
      final phone = normPhone(row['phone']);
      final name = normName(row['full_name']);

      int? index;
      if (email.isNotEmpty) index = emailIndex[email];
      if (index == null && phone.isNotEmpty) index = phoneIndex[phone];
      if (index == null && name.isNotEmpty) index = nameIndex[name];

      final candidate = <String, dynamic>{
        '_id': (row['client_key'] ?? row['row_id'] ?? '').toString(),
        'clientKey': (row['client_key'] ?? row['row_id'] ?? '').toString(),
        'fullName': (row['full_name'] ?? '').toString().trim(),
        'email': email,
        'phone': (row['phone'] ?? '').toString().trim(),
        'source': (row['source'] ?? '').toString(),
        'updatedAt': row['updated_at'],
      };

      if (index == null) {
        index = merged.length;
        merged.add(candidate);
      } else {
        final existing = merged[index];
        if ((existing['fullName'] ?? '').toString().trim().isEmpty && candidate['fullName'].toString().isNotEmpty) {
          existing['fullName'] = candidate['fullName'];
        }
        if ((existing['email'] ?? '').toString().trim().isEmpty && candidate['email'].toString().isNotEmpty) {
          existing['email'] = candidate['email'];
        }
        if ((existing['phone'] ?? '').toString().trim().isEmpty && candidate['phone'].toString().isNotEmpty) {
          existing['phone'] = candidate['phone'];
        }
      }

      final current = merged[index];
      final currentEmail = normEmail(current['email']);
      final currentPhone = normPhone(current['phone']);
      final currentName = normName(current['fullName']);
      if (currentEmail.isNotEmpty) emailIndex[currentEmail] = index;
      if (currentPhone.isNotEmpty) phoneIndex[currentPhone] = index;
      if (currentName.isNotEmpty) nameIndex[currentName] = index;
    }

    final needle = (q ?? '').trim().toLowerCase();
    final filtered = needle.isEmpty
        ? merged
        : merged.where((row) {
            return [row['fullName'], row['phone'], row['email']]
                .map((v) => (v ?? '').toString().toLowerCase())
                .join(' ')
                .contains(needle);
          }).toList();

    filtered.sort((a, b) {
      final av = ((a['fullName'] ?? '').toString().trim().isNotEmpty
              ? a['fullName']
              : ((a['email'] ?? '').toString().trim().isNotEmpty ? a['email'] : a['phone']))
          .toString()
          .toLowerCase();
      final bv = ((b['fullName'] ?? '').toString().trim().isNotEmpty
              ? b['fullName']
              : ((b['email'] ?? '').toString().trim().isNotEmpty ? b['email'] : b['phone']))
          .toString()
          .toLowerCase();
      return av.compareTo(bv);
    });

    return filtered.take(safeLimit).toList();
  }

  static Future<List<Map<String, dynamic>>> fetchLegacyClients({String? q, int limit = 500}) async {
    await ensureReady();

    dynamic query = client
        .from('legacy_loans')
        .select('id,source_file,full_name,borrower_mobile,borrower_email,borrower_address,loan_status,balance_amount,principal_amount,next_due_date,created_at')
        .limit(limit);

    if (q != null && q.trim().isNotEmpty) {
      final t = q.replaceAll(',', ' ').replaceAll('%', '').trim();
      query = query.or('full_name.ilike.%$t%,borrower_mobile.ilike.%$t%,borrower_email.ilike.%$t%');
    }

    final res = await query;
    final rows = (res as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

    return rows.map((row) {
      final balance = parseAmount(row['balance_amount']);
      return {
        '_id': row['id']?.toString() ?? '',
        'clientKey': (row['borrower_email'] ?? row['borrower_mobile'] ?? row['id'] ?? '').toString(),
        'fullName': row['full_name'] ?? '',
        'email': row['borrower_email'] ?? '',
        'phone': row['borrower_mobile'] ?? '',
        'address': row['borrower_address'] ?? '',
        'balance': balance,
        'loanStatus': row['loan_status'] ?? '',
        'statusBucket': balance > 0 ? 'balance' : 'none',
        'isExtended': false,
        'updatedAt': row['created_at'],
      };
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // REPORTING BACKEND — direct Supabase
  // ---------------------------------------------------------------------------

  static String _dateOnly(dynamic value) {
    final dt = value is DateTime
        ? value
        : DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
    final u = dt.toUtc();
    return '${u.year.toString().padLeft(4, '0')}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')}';
  }

  static String _monthOnly(dynamic value) {
    final dt = value is DateTime
        ? value
        : DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
    final u = dt.toUtc();
    return '${u.year.toString().padLeft(4, '0')}-${u.month.toString().padLeft(2, '0')}-01';
  }

  static Map<String, dynamic> _dailyRowToApp(Map<String, dynamic> row) {
    return {
      'id': row['id']?.toString(),
      '_id': row['id']?.toString(),
      'branch': row['branch'] ?? '',
      'date': row['report_date']?.toString(),
      'openingBalances': row['opening_balances'] ?? const <String, dynamic>{},
      'loanCounts': row['loan_counts'] ?? const <String, dynamic>{},
      'closingBalances': row['closing_balances'] ?? const <String, dynamic>{},
      'totalDisbursed': row['total_disbursed'] ?? 0,
      'totalCollected': row['total_collected'] ?? 0,
      'collectedForOtherBranches': row['collected_for_other_branches'] ?? 0,
      'pettyCash': row['petty_cash'] ?? 0,
      'expenses': row['expenses'] ?? 0,
      'zanacoApplied': row['zanaco_applied'] ?? const <String, dynamic>{},
      'totalLoans': row['total_loans'] ?? 0,
      'updatedAt': row['updated_at']?.toString(),
      'createdAt': row['created_at']?.toString(),
      'synced': true,
    };
  }

  static Future<Map<String, dynamic>> saveDailyReport(Map<String, dynamic> report) async {
    await ensureReady();
    final user = client.auth.currentUser;
    final branch = (report['branch'] ?? '').toString().trim();
    if (branch.isEmpty) throw Exception('Branch is required.');

    final payload = <String, dynamic>{
      'branch': branch,
      'report_date': _dateOnly(report['date']),
      'opening_balances': report['openingBalances'] ?? report['opening_balances'] ?? {},
      'loan_counts': report['loanCounts'] ?? report['loan_counts'] ?? {},
      'closing_balances': report['closingBalances'] ?? report['closing_balances'] ?? {},
      'total_disbursed': parseAmount(report['totalDisbursed'] ?? report['total_disbursed']),
      'total_collected': parseAmount(report['totalCollected'] ?? report['total_collected']),
      'collected_for_other_branches': parseAmount(report['collectedForOtherBranches'] ?? report['collected_for_other_branches']),
      'petty_cash': parseAmount(report['pettyCash'] ?? report['petty_cash']),
      'expenses': parseAmount(report['expenses']),
      'zanaco_applied': report['zanacoApplied'] ?? report['zanaco_applied'] ?? {},
      'total_loans': (report['totalLoans'] ?? report['total_loans'] ?? 0),
      'submitted_by': user?.id,
      'submitted_email': user?.email?.toLowerCase(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    final res = await client
        .from('daily_reports')
        .upsert(payload, onConflict: 'branch,report_date')
        .select()
        .single();
    return {'success': true, 'report': _dailyRowToApp(Map<String, dynamic>.from(res))};
  }

  static Future<Map<String, dynamic>> syncDailyReports(List<Map<String, dynamic>> reports) async {
    final saved = <Map<String, dynamic>>[];
    for (final report in reports) {
      final result = await saveDailyReport(report);
      final row = result['report'];
      if (row is Map) saved.add(Map<String, dynamic>.from(row));
    }
    return {'success': true, 'saved': saved, 'message': '${saved.length} report(s) synced'};
  }

  static Future<List<Map<String, dynamic>>> fetchDailyReports({int limit = 5000}) async {
    await ensureReady();
    final res = await client
        .from('daily_reports')
        .select()
        .order('report_date', ascending: false)
        .limit(limit);
    return (res as List)
        .whereType<Map>()
        .map((e) => _dailyRowToApp(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<Map<String, dynamic>?> fetchDailyReportForBranchDate(String branch, DateTime date) async {
    await ensureReady();
    final res = await client
        .from('daily_reports')
        .select()
        .ilike('branch', branch.trim())
        .eq('report_date', _dateOnly(date))
        .maybeSingle();
    if (res == null) return null;
    return _dailyRowToApp(Map<String, dynamic>.from(res));
  }

  static Future<bool> deleteDailyReport({required String branch, required DateTime date}) async {
    await ensureReady();
    await client
        .from('daily_reports')
        .delete()
        .ilike('branch', branch.trim())
        .eq('report_date', _dateOnly(date));
    return true;
  }


  static Future<bool> deleteDailyReportById(String id) async {
    await ensureReady();
    await client.from('daily_reports').delete().eq('id', id.trim());
    return true;
  }

  static Map<String, dynamic> _monthlyRowToApp(Map<String, dynamic> row) {
    final raw = row['report_data'];
    final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return {
      ...data,
      'id': row['id']?.toString(),
      '_id': row['id']?.toString(),
      'branch': row['branch'] ?? data['branch'] ?? '',
      'date': row['report_month']?.toString(),
      'collected': row['collected'] ?? data['collected'] ?? 0,
      'totalCollected': row['total_collected'] ?? data['totalCollected'] ?? 0,
      'totalDisbursed': row['total_disbursed'] ?? data['totalDisbursed'] ?? 0,
      'totalExpenses': row['total_expenses'] ?? data['totalExpenses'] ?? 0,
      'updatedAt': row['updated_at']?.toString(),
      'createdAt': row['created_at']?.toString(),
      'synced': true,
    };
  }

  static Future<Map<String, dynamic>> saveMonthlyReport(Map<String, dynamic> report) async {
    await ensureReady();
    final user = client.auth.currentUser;
    final branch = (report['branch'] ?? '').toString().trim();
    if (branch.isEmpty) throw Exception('Branch is required.');
    final now = DateTime.now().toUtc().toIso8601String();
    final payload = <String, dynamic>{
      'branch': branch,
      'report_month': _monthOnly(report['date']),
      'report_data': report,
      'collected': parseAmount(report['collected']),
      'total_collected': parseAmount(report['totalCollected'] ?? report['totalCollections'] ?? report['collected']),
      'total_disbursed': parseAmount(report['totalDisbursed'] ?? report['principalReloaned']),
      'total_expenses': parseAmount(report['totalExpenses'] ?? report['defaultAmount']),
      'submitted_by': user?.id,
      'submitted_email': user?.email?.toLowerCase(),
      'updated_at': now,
    };
    final res = await client
        .from('monthly_reports')
        .upsert(payload, onConflict: 'branch,report_month')
        .select()
        .single();
    return {'success': true, 'report': _monthlyRowToApp(Map<String, dynamic>.from(res))};
  }

  static Future<Map<String, dynamic>> syncMonthlyReportRows(List<Map<String, dynamic>> reports) async {
    final saved = <Map<String, dynamic>>[];
    for (final report in reports) {
      final result = await saveMonthlyReport(report);
      final row = result['report'];
      if (row is Map) saved.add(Map<String, dynamic>.from(row));
    }
    return {'success': true, 'saved': saved, 'message': '${saved.length} monthly report(s) synced'};
  }

  static Future<List<Map<String, dynamic>>> fetchMonthlyReports({int limit = 5000}) async {
    await ensureReady();
    final res = await client
        .from('monthly_reports')
        .select()
        .order('report_month', ascending: false)
        .limit(limit);
    return (res as List)
        .whereType<Map>()
        .map((e) => _monthlyRowToApp(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<bool> deleteMonthlyReport({required String branch, required DateTime date}) async {
    await ensureReady();
    await client
        .from('monthly_reports')
        .delete()
        .ilike('branch', branch.trim())
        .eq('report_month', _monthOnly(date));
    return true;
  }


  static Future<bool> deleteMonthlyReportById(String id) async {
    await ensureReady();
    await client.from('monthly_reports').delete().eq('id', id.trim());
    return true;
  }

  static Future<Map<String, dynamic>> saveBranchCommentDirect({
    required String branch,
    required String text,
    required String author,
  }) async {
    await ensureReady();
    final user = client.auth.currentUser;
    final res = await client.from('branch_comments').insert({
      'branch': branch.trim(),
      'comment_text': text.trim(),
      'author': author.trim(),
      'submitted_by': user?.id,
      'submitted_email': user?.email?.toLowerCase(),
    }).select().single();
    return {'success': true, 'comment': res};
  }

  static Future<Map<String, dynamic>> saveZanacoBulkDirect({
    required DateTime date,
    String? fromBranch,
    required Map<String, Map<String, double>> allocations,
  }) async {
    await ensureReady();
    final user = client.auth.currentUser;
    final rows = <Map<String, dynamic>>[];
    allocations.forEach((targetBranch, channels) {
      channels.forEach((channel, amount) {
        if (amount <= 0) return;
        rows.add({
          'distribution_date': _dateOnly(date),
          'from_branch': (fromBranch ?? '').trim().toLowerCase(),
          'target_branch': targetBranch.trim().toLowerCase(),
          'channel': channel.trim().toLowerCase(),
          'amount': amount,
          'submitted_by': user?.id,
          'submitted_email': user?.email?.toLowerCase(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      });
    });
    if (rows.isEmpty) return {'success': true, 'saved': 0, 'message': 'No allocations to save'};
    await client.from('zanaco_distributions').upsert(
      rows,
      onConflict: 'distribution_date,from_branch,target_branch,channel',
    );
    return {'success': true, 'saved': rows.length, 'message': 'Zanaco distribution saved'};
  }

  static Future<Map<String, dynamic>> saveZanacoSingleDirect({
    required DateTime date,
    required String branch,
    required String channel,
    required double amount,
    Map<String, dynamic>? metadata,
  }) async {
    await ensureReady();
    final user = client.auth.currentUser;
    final metadataBranch = (user?.userMetadata?['branch'] ?? '').toString().trim();
    final emailBranch = (user?.email ?? '').split('@').first.trim();
    final fromBranch = (metadataBranch.isNotEmpty ? metadataBranch : emailBranch).toLowerCase();
    await client.from('zanaco_distributions').upsert({
      'distribution_date': _dateOnly(date),
      'from_branch': fromBranch,
      'target_branch': branch.trim().toLowerCase(),
      'channel': channel.trim().toLowerCase(),
      'amount': amount,
      'metadata': metadata ?? {},
      'submitted_by': user?.id,
      'submitted_email': user?.email?.toLowerCase(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'distribution_date,from_branch,target_branch,channel');
    return {'success': true};
  }

  static Future<List<Map<String, dynamic>>> fetchZanacoRows({
    required DateTime date,
    String? branch,
    String? channel,
  }) async {
    await ensureReady();
    dynamic query = client
        .from('zanaco_distributions')
        .select()
        .eq('distribution_date', _dateOnly(date));
    if (branch != null && branch.trim().isNotEmpty) {
      query = query.eq('target_branch', branch.trim().toLowerCase());
    }
    if (channel != null && channel.trim().isNotEmpty) {
      query = query.eq('channel', channel.trim().toLowerCase());
    }
    final res = await query.order('created_at', ascending: false);
    return (res as List).whereType<Map>().map((e) {
      final row = Map<String, dynamic>.from(e);
      return {
        ...row,
        'branch': row['target_branch'],
        'fromBranch': row['from_branch'],
        'date': row['distribution_date'],
      };
    }).toList();
  }

  static Future<Map<String, double>> fetchZanacoAggregateDirect({
    required String branch,
    required DateTime date,
  }) async {
    final rows = await fetchZanacoRows(date: date, branch: branch);
    final out = <String, double>{};
    for (final row in rows) {
      final channel = (row['channel'] ?? '').toString().toLowerCase();
      out[channel] = (out[channel] ?? 0.0) + parseAmount(row['amount']);
    }
    return out;
  }

}
