class Loan {
  final String id;
  final String fullName;
  final String? borrowerMobile;
  final String? borrowerEmail;
  final String? borrowerAddress;
  final String loanStatus;
  final double principalAmount;
  final double totalInterestBalance;
  final double amortizationDue;
  final double nextInstallmentAmount;
  final DateTime? nextDueDate;
  final double penaltyAmount;
  final String branchId;
  final DateTime? importedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Loan({
    required this.id,
    required this.fullName,
    this.borrowerMobile,
    this.borrowerEmail,
    this.borrowerAddress,
    required this.loanStatus,
    required this.principalAmount,
    required this.totalInterestBalance,
    required this.amortizationDue,
    required this.nextInstallmentAmount,
    this.nextDueDate,
    required this.penaltyAmount,
    required this.branchId,
    this.importedAt,
    this.createdAt,
    this.updatedAt,
  });

  static double _parseNumber(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) {
      final cleaned = v.replaceAll(',', '').trim();
      return double.tryParse(cleaned) ?? 0.0;
    }
    if (v is Map) {
      // handle mongo export shapes: { "$numberInt": "2000" } etc.
      for (final key in v.keys) {
        final lk = key.toString().toLowerCase();
        if (lk.contains('number')) {
          final inner = v[key];
          if (inner is String) return double.tryParse(inner.replaceAll(',', '').trim()) ?? 0.0;
          if (inner is num) return inner.toDouble();
        }
      }
      if (v.containsKey('amount')) return _parseNumber(v['amount']);
      if (v.values.isNotEmpty) return _parseNumber(v.values.first);
    }
    return 0.0;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    if (v is Map) {
      // mongo export: { "$date": { "$numberLong":"..."} } or similar
      if (v.containsKey('\$date')) {
        final d = v['\$date'];
        if (d is Map && d.containsKey('\$numberLong')) {
          final ms = int.tryParse(d['\$numberLong'].toString());
          if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
        } else if (d is String) {
          return DateTime.tryParse(d);
        }
      }
      // direct number-long
      for (final val in v.values) {
        final parsed = _parseDate(val);
        if (parsed != null) return parsed;
      }
    }
    // maybe it's a numeric timestamp
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    return null;
  }

  factory Loan.fromJson(Map<String, dynamic> json) {
    try {
      // id may come as _id: { $oid: "..." } or as id
      String id = '';
      if (json.containsKey('_id')) {
        final v = json['_id'];
        if (v is Map && v.containsKey('\$oid')) {
          id = v['\$oid'].toString();
        } else {
          id = v.toString();
        }
      } else if (json.containsKey('id')) {
        id = json['id'].toString();
      }

      // Validate critical fields
      if (id.isEmpty) {
        throw const FormatException('Loan must have a valid ID');
      }

      final principalAmount = _parseNumber(json['principalAmount'] ?? json['principal_amount']);
      if (principalAmount < 0) {
        throw FormatException('Principal amount cannot be negative: $principalAmount');
      }

      final fullName = (json['fullName'] ?? json['full_name'] ?? '').toString();
      if (fullName.isEmpty) {
        throw const FormatException('Loan must have a full name');
      }

      return Loan(
        id: id,
        fullName: fullName,
        borrowerMobile: (json['borrowerMobile'] ?? json['borrowerMobile'] ?? json['mobile'] ?? json['phone'])?.toString(),
        borrowerEmail: (json['borrowerEmail'] ?? json['borrower_email'])?.toString(),
        borrowerAddress: (json['borrowerAddress'] ?? json['borrower_address'] ?? '')?.toString(),
        loanStatus: (json['loanStatus'] ?? json['loan_status'] ?? 'Unknown').toString(),
        principalAmount: principalAmount,
        totalInterestBalance: _parseNumber(json['totalInterestBalance'] ?? json['total_interest_balance']),
        amortizationDue: _parseNumber(json['amortizationDue'] ?? json['amortization_due']),
        nextInstallmentAmount: _parseNumber(json['nextInstallmentAmount'] ?? json['next_installment_amount']),
        nextDueDate: _parseDate(json['nextDueDate'] ?? json['next_due_date']),
        penaltyAmount: _parseNumber(json['penaltyAmount'] ?? json['penalty_amount']),
        branchId: (json['branchId'] ?? json['branch_id'] ?? '')?.toString() ?? '',
        importedAt: _parseDate(json['importedAt'] ?? json['imported_at']),
        createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
        updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
      );
    } catch (e) {
      throw FormatException('Failed to parse Loan from JSON: $e\nJSON: $json');
    }
  }

  // Helper method to check if loan is active
  bool get isActive {
    return loanStatus != 'Fully Paid' && loanStatus != 'Write-Off';
  }

  // Helper method to get total amount due
  double get totalAmountDue {
    return amortizationDue + totalInterestBalance + penaltyAmount;
  }

  // Helper method to check if loan is overdue
  bool get isOverdue {
    return nextDueDate != null && nextDueDate!.isBefore(DateTime.now());
  }

  // Convert to map for serialization
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'borrowerMobile': borrowerMobile,
      'borrowerEmail': borrowerEmail,
      'borrowerAddress': borrowerAddress,
      'loanStatus': loanStatus,
      'principalAmount': principalAmount,
      'totalInterestBalance': totalInterestBalance,
      'amortizationDue': amortizationDue,
      'nextInstallmentAmount': nextInstallmentAmount,
      'nextDueDate': nextDueDate?.toIso8601String(),
      'penaltyAmount': penaltyAmount,
      'branchId': branchId,
      'importedAt': importedAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'Loan(id: $id, name: $fullName, status: $loanStatus, principal: $principalAmount, totalDue: $totalAmountDue)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Loan && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}