// lib/services/client_service.dart
import 'package:daml/services/api_service.dart';
import 'package:daml/models/client_response.dart';

class ClientService {
  /// Fetch complete client data with loans summary
  static Future<ClientResponse> fetchMyClient({bool includeLoans = false}) async {
    try {
      final response = await ApiService.fetchMyClient(includeLoans: includeLoans);
      return ClientResponse.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  /// Simplified method to get only client details (fast)
  static Future<Map<String, dynamic>> getClientDetails() async {
    try {
      final response = await ApiService.fetchMyClient(includeLoans: false);
      
      if (response['success'] == true) {
        final clientData = response['client'] ?? {};
        final loansSummary = response['loansSummary'] ?? {};
        
        // Extract only client details
        return {
          'success': true,
          'client': clientData,
          'loansSummary': loansSummary,
        };
      }
      
      throw Exception(response['message'] ?? 'Failed to fetch client data');
    } catch (e) {
      rethrow;
    }
  }
  
  /// Get detailed loans breakdown
  static Future<List<Map<String, dynamic>>> getClientLoans() async {
    try {
      final response = await ApiService.fetchMyClient(includeLoans: true);
      
      if (response['success'] == true) {
        final loans = response['loans'] ?? [];
        return List<Map<String, dynamic>>.from(loans);
      }
      
      throw Exception(response['message'] ?? 'Failed to fetch loans');
    } catch (e) {
      rethrow;
    }
  }
}