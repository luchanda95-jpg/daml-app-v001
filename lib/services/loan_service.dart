// lib/services/loan_service.dart
import 'package:daml/models/loan.dart';
import 'package:daml/services/api_service.dart';

class LoanService {
  /// Search loans using ApiService.fetchLoansByQuery and map to Loan model.
  static Future<List<Loan>> searchLoans({
    String? phone,
    String? email,
    String? name,
    int limit = 100,
  }) async {
    final results = await ApiService.fetchLoansByQuery(
      phone: phone,
      email: email,
      name: name,
      limit: limit,
    );

    // tolerant mapping
    final loans = <Loan>[];
    for (final raw in results) {
      try {
        final map = raw is Map ? Map<String, dynamic>.from(raw) : Map<String, dynamic>.from(raw as Map);
        loans.add(Loan.fromJson(map));
      } catch (e) {
        // ignore malformed entries, but you can log if needed 
      }
    }
    return loans; 
  } 
}
