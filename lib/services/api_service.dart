// lib/services/api_service.dart
// Supabase-only compatibility facade for DAML.
//
// This class keeps the existing screen/service method names so the UI does not
// need a large rewrite, but every data operation now goes directly to
// SupabaseDamlService. There is no secondary network backend or HTTP fallback.

import 'supabase_daml_service.dart';

class ApiService {
  ApiService._();

  static Future<void> _ready() => SupabaseDamlService.ensureReady();

  // Compatibility only. Existing screens may still call these while moving
  // between routes. Supabase Auth manages the real session automatically.
  static Map<String, String> defaultHeaders = <String, String>{};

  static void setAuthToken(String token) {}
  static void clearAuthToken() {}
  static void setHeader(String key, String value) {}
  static void removeHeader(String key) {}

  // -------------------- CLIENT DASHBOARD / LOANS --------------------

  static Future<Map<String, dynamic>> fetchMyClient({
    bool includeLoans = false,
  }) async {
    await _ready();
    return SupabaseDamlService.fetchMyClientDashboard(
      includeLoans: includeLoans,
    );
  }

  static Future<List<dynamic>> fetchLoansByQuery({
    String? email,
    String? phone,
    String? name,
    int limit = 20,
  }) async {
    await _ready();
    return SupabaseDamlService.fetchLoansByQuery(
      email: email,
      phone: phone,
      name: name,
      limit: limit,
    );
  }

  static Future<Map<String, dynamic>?> fetchLoanById(String id) async {
    await _ready();
    if (id.trim().isEmpty) return null;
    return SupabaseDamlService.fetchLoanById(id);
  }

  // -------------------- DAILY REPORTS --------------------

  static Future<Map<String, dynamic>> syncReports(
    List<Map<String, dynamic>> reports,
  ) async {
    await _ready();
    return SupabaseDamlService.syncDailyReports(reports);
  }

  static Future<Map<String, dynamic>> saveReportSingle(
    Map<String, dynamic> report,
  ) async {
    await _ready();
    return SupabaseDamlService.saveDailyReport(report);
  }

  static Future<Map<String, dynamic>?> fetchReportForBranchDate(
    String branch,
    DateTime date,
  ) async {
    await _ready();
    return SupabaseDamlService.fetchDailyReportForBranchDate(branch, date);
  }

  static Future<List<dynamic>> fetchAllReports() async {
    await _ready();
    return SupabaseDamlService.fetchDailyReports();
  }

  static Future<bool> deleteReportByBranchDate(
    String branch,
    DateTime date,
  ) async {
    await _ready();
    return SupabaseDamlService.deleteDailyReport(
      branch: branch,
      date: date,
    );
  }

  static Future<bool> deleteReportById(String id) async {
    await _ready();
    return SupabaseDamlService.deleteDailyReportById(id);
  }

  // -------------------- ZANACO --------------------

  static Future<dynamic> getZanaco({
    required DateTime date,
    String? branch,
    String? channel,
  }) async {
    await _ready();
    final rows = await SupabaseDamlService.fetchZanacoRows(
      date: date,
      branch: branch,
      channel: channel,
    );
    return <String, dynamic>{
      'success': true,
      'distributions': rows,
    };
  }

  static Future<Map<String, double>> fetchZanacoAggregate({
    required String branch,
    required DateTime date,
  }) async {
    await _ready();
    return SupabaseDamlService.fetchZanacoAggregateDirect(
      branch: branch,
      date: date,
    );
  }

  static Future<Map<String, dynamic>> saveZanacoSingle({
    required DateTime date,
    required String branch,
    required String channel,
    required double amount,
    Map<String, dynamic>? metadata,
  }) async {
    await _ready();
    return SupabaseDamlService.saveZanacoSingleDirect(
      date: date,
      branch: branch,
      channel: channel,
      amount: amount,
      metadata: metadata,
    );
  }

  static Future<Map<String, dynamic>> saveZanacoBulk({
    required DateTime date,
    String? fromBranch,
    required Map<String, Map<String, double>> allocations,
    List<Map<String, dynamic>>? distributions,
  }) async {
    await _ready();
    return SupabaseDamlService.saveZanacoBulkDirect(
      date: date,
      fromBranch: fromBranch,
      allocations: allocations,
    );
  }

  static Future<String?> getBranchForEmail(String email) async {
    await _ready();
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    try {
      final profile = await SupabaseDamlService.client
          .from('profiles')
          .select('branch')
          .eq('email', normalized)
          .maybeSingle();

      final branch = profile?['branch']?.toString().trim();
      if (branch != null && branch.isNotEmpty) return branch;
    } catch (_) {
      // Reserved branch accounts can still resolve from their canonical email.
    }

    if (normalized.endsWith('@directaccess.com')) {
      final local = normalized.split('@').first.trim();
      if (local.isNotEmpty) return local;
    }
    return null;
  }

  static Future<Map<String, double>> fetchZanacoDistributions({
    required String branch,
    required DateTime date,
  }) async {
    await _ready();
    return SupabaseDamlService.fetchZanacoAggregateDirect(
      branch: branch,
      date: date,
    );
  }

  // -------------------- MONTHLY REPORTS --------------------

  static Future<Map<String, dynamic>> syncMonthlyReports(
    List<Map<String, dynamic>> monthlyReports,
  ) async {
    await _ready();
    return SupabaseDamlService.syncMonthlyReportRows(monthlyReports);
  }

  static Future<List<dynamic>> fetchAllMonthlyReports() async {
    await _ready();
    return SupabaseDamlService.fetchMonthlyReports();
  }

  static Future<bool> deleteMonthlyReportById(String id) async {
    await _ready();
    return SupabaseDamlService.deleteMonthlyReportById(id);
  }

  static Future<bool> deleteMonthlyReportByBranchDate({
    required String branch,
    required DateTime monthDate,
  }) async {
    await _ready();
    return SupabaseDamlService.deleteMonthlyReport(
      branch: branch,
      date: monthDate,
    );
  }

  // -------------------- BRANCH COMMENTS --------------------

  static Future<Map<String, dynamic>> saveBranchComment(
    String branch,
    String text,
    String author,
  ) async {
    await _ready();
    return SupabaseDamlService.saveBranchCommentDirect(
      branch: branch,
      text: text,
      author: author,
    );
  }

  // -------------------- NOTIFICATIONS --------------------

  static Future<Map<String, dynamic>> createNotification({
    required String toEmail,
    required String title,
    required String message,
    String type = 'info',
    Map<String, dynamic>? data,
  }) async {
    await _ready();
    await SupabaseDamlService.client.from('notifications').insert({
      'title': title,
      'message': message,
      'type': type,
      'is_read': false,
      'target_email': toEmail.trim().toLowerCase(),
      'data': data ?? <String, dynamic>{},
    });
    return <String, dynamic>{'success': true};
  }

  static Future<List<Map<String, dynamic>>> fetchUnreadNotifications(
    String toEmail,
  ) async {
    await _ready();
    final rows = await SupabaseDamlService.fetchNotifications(
      targetEmail: toEmail,
    );
    return rows.where((n) => n['is_read'] != true).toList();
  }

  static Future<void> markAllNotificationsRead(String toEmail) async {
    await _ready();
    await SupabaseDamlService.markAllNotificationsRead(
      targetEmail: toEmail,
    );
  }

  // -------------------- ADMIN CLIENT DIRECTORY --------------------

  static Future<List<Map<String, dynamic>>> fetchClients({
    String? q,
    int limit = 500,
    bool lite = true,
  }) async {
    await _ready();
    return SupabaseDamlService.fetchAdminClientDirectory(
      q: q,
      limit: limit,
    );
  }

  static Future<Map<String, dynamic>> fetchClientById(String id) async {
    await _ready();
    final loan = await SupabaseDamlService.fetchLoanById(id);
    if (loan == null) throw Exception('Client/loan not found');

    return <String, dynamic>{
      '_id': loan['id'] ?? id,
      'clientKey':
          loan['borrowerEmail'] ?? loan['borrowerMobile'] ?? id,
      'fullName': loan['fullName'] ?? '',
      'email': loan['borrowerEmail'] ?? '',
      'phone': loan['borrowerMobile'] ?? '',
      'address': loan['borrowerAddress'] ?? '',
      'balance':
          SupabaseDamlService.parseAmount(loan['amortizationDue']) +
          SupabaseDamlService.parseAmount(loan['totalInterestBalance']) +
          SupabaseDamlService.parseAmount(loan['penaltyAmount']),
      'loanStatus': loan['loanStatus'] ?? '',
      'statusBucket': 'balance',
      'isExtended': false,
    };
  }
}
