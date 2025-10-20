class DataCleaner {
  static cleanRow(row) {
    const cleaned = {};
    for (const [k, v] of Object.entries(row || {})) {
      const key = String(k).trim();
      const val = (typeof v === 'string') ? v.trim() : v;
      cleaned[key] = (val === '' ? null : val);
    }

    // Normalize common header typos / variants
    if (cleaned['Borrower Date 0f Birth'] && !cleaned['Borrower Date Of Birth']) {
      cleaned['Borrower Date Of Birth'] = cleaned['Borrower Date 0f Birth'];
    }
    if (cleaned['Borrower Date of Birth'] && !cleaned['Borrower Date Of Birth']) {
      cleaned['Borrower Date Of Birth'] = cleaned['Borrower Date of Birth'];
    }

    // Convert numeric fields (allow commas)
    const numericFields = [
      'Principal Amount', 'Total Interest Balance', 'Amortization Due',
      'Next Installment Amount', 'Penalty Amount'
    ];

    numericFields.forEach(field => {
      if (cleaned[field] != null) {
        const num = Number(String(cleaned[field]).replace(/,/g, '').trim());
        cleaned[field] = Number.isNaN(num) ? 0 : num;
      }
    });

    // Parse date fields
    if (cleaned['Next Due Date']) {
      cleaned['Next Due Date'] = this.parseDate(cleaned['Next Due Date']);
    }
    if (cleaned['Borrower Date Of Birth']) {
      cleaned['Borrower Date Of Birth'] = this.parseDate(cleaned['Borrower Date Of Birth']);
    }

    return cleaned;
  }

  static parseDate(dateString) {
    if (!dateString) return null;
    const s = String(dateString).trim();

    // ISO-like YYYY-MM-DD
    if (/^\d{4}-\d{1,2}-\d{1,2}/.test(s)) {
      const d = new Date(s);
      return isNaN(d.getTime()) ? null : d;
    }

    // DD/MM/YYYY or D/M/YYYY
    const parts = s.split('/');
    if (parts.length === 3) {
      const day = parts[0].padStart(2, '0');
      const month = parts[1].padStart(2, '0');
      const year = parts[2].length === 2 ? `20${parts[2]}` : parts[2];
      const d = new Date(`${year}-${month}-${day}`);
      return isNaN(d.getTime()) ? null : d;
    }

    // Fallback to Date parse
    const fallback = new Date(s);
    return isNaN(fallback.getTime()) ? null : fallback;
  }

  static mapToSchema(csvData) {
    return {
      fullName: csvData['Full Name'] || csvData['Borrower Name'] || '',
      borrowerLandline: csvData['Borrower Landline'] || null,
      borrowerMobile: csvData['Borrower Mobile'] || null,
      loanStatus: csvData['Loan Status Name'] || csvData['Loan Status'] || 'Unknown',
      principalAmount: Number(csvData['Principal Amount'] || 0),
      totalInterestBalance: Number(csvData['Total Interest Balance'] || 0),
      amortizationDue: Number(csvData['Amortization Due'] || 0),
      borrowerEmail: csvData['Borrower Email'] || null,
      borrowerAddress: csvData['Borrower Address'] || null,
      borrowerDateOfBirth: csvData['Borrower Date Of Birth'] || null,
      nextInstallmentAmount: Number(csvData['Next Installment Amount'] || 0),
      nextDueDate: csvData['Next Due Date'] || null,
      penaltyAmount: Number(csvData['Penalty Amount'] || 0)
    };
  }
}

module.exports = DataCleaner;
