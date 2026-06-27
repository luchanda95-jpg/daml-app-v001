// lib/models/client.dart

class Client {
  final String clientKey;
  final String fullName;
  final String? phone;
  final String? email;
  final String? address;
  final DateTime? dateOfBirth;
  final String loanStatus;
  final String statusBucket;
  final bool isExtended;
  final double balance;
  final DateTime? statementDate;
  final DateTime? lastImportedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Client({
    required this.clientKey,
    required this.fullName,
    this.phone,
    this.email,
    this.address,
    this.dateOfBirth,
    required this.loanStatus,
    required this.statusBucket,
    required this.isExtended,
    required this.balance,
    this.statementDate,
    this.lastImportedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory Client.fromJson(Map<String, dynamic> json) {
    return Client(
      clientKey: json['clientKey'] ?? '',
      fullName: json['fullName'] ?? '',
      phone: json['phone'],
      email: json['email'],
      address: json['address'],
      dateOfBirth: json['dateOfBirth'] != null 
          ? DateTime.parse(json['dateOfBirth']) 
          : null,
      loanStatus: json['loanStatus'] ?? 'Unknown',
      statusBucket: json['statusBucket'] ?? 'balance',
      isExtended: json['isExtended'] ?? false,
      balance: (json['balance'] ?? 0.0).toDouble(),
      statementDate: json['statementDate'] != null
          ? DateTime.parse(json['statementDate'])
          : null,
      lastImportedAt: json['lastImportedAt'] != null
          ? DateTime.parse(json['lastImportedAt'])
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'clientKey': clientKey,
      'fullName': fullName,
      'phone': phone,
      'email': email,
      'address': address,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'loanStatus': loanStatus,
      'statusBucket': statusBucket,
      'isExtended': isExtended,
      'balance': balance,
      'statementDate': statementDate?.toIso8601String(),
      'lastImportedAt': lastImportedAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}