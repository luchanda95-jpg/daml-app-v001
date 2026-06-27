// lib/models/client_response.dart
import 'package:daml/models/client.dart';
import 'package:daml/models/loan.dart';

class ClientResponse {
  final bool success;
  final Client? client;
  final Map<String, dynamic>? loansSummary;
  final List<Loan>? loans;
  final String? message;

  ClientResponse({
    required this.success,
    this.client,
    this.loansSummary,
    this.loans,
    this.message,
  });

  factory ClientResponse.fromJson(Map<String, dynamic> json) {
    return ClientResponse(
      success: json['success'] ?? false,
      client: json['client'] != null 
          ? Client.fromJson(Map<String, dynamic>.from(json['client']))
          : null,
      loansSummary: json['loansSummary'] != null
          ? Map<String, dynamic>.from(json['loansSummary'])
          : null,
      loans: json['loans'] != null
          ? (json['loans'] as List).map((loan) => Loan.fromJson(loan)).toList()
          : null,
      message: json['message'],
    );
  }
}