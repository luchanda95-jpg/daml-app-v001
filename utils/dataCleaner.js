class DataCleaner {
  static cleanRow(row) {
    const cleaned = {};
    for (const [k, v] of Object.entries(row || {})) {
      const key = String(k).trim();
      const val = typeof v === "string" ? v.trim() : v;
      cleaned[key] = val === "" ? null : val;
    }

    // Normalize common header variants
    if (cleaned["Borrower Date 0f Birth"] && !cleaned["Borrower Date Of Birth"]) {
      cleaned["Borrower Date Of Birth"] = cleaned["Borrower Date 0f Birth"];
    }
    if (cleaned["Borrower Date of Birth"] && !cleaned["Borrower Date Of Birth"]) {
      cleaned["Borrower Date Of Birth"] = cleaned["Borrower Date of Birth"];
    }

    // Convert numeric-like fields (commas allowed)
    const numericFields = [
      "Principal Amount",
      "Total Interest Balance",
      "Amortization Due",
      "Next Installment Amount",
      "Penalty Amount",
      "Client Balance",
      "Outstanding Balance",
      "Balance",
    ];

    numericFields.forEach((field) => {
      if (cleaned[field] != null) {
        const num = Number(String(cleaned[field]).replace(/,/g, "").trim());
        cleaned[field] = Number.isNaN(num) ? 0 : num;
      }
    });

    // Parse date fields
    if (cleaned["Next Due Date"]) cleaned["Next Due Date"] = this.parseDate(cleaned["Next Due Date"]);
    if (cleaned["Borrower Date Of Birth"]) cleaned["Borrower Date Of Birth"] = this.parseDate(cleaned["Borrower Date Of Birth"]);

    // Optional “as at / report date” columns (if they exist)
    if (cleaned["As At"]) cleaned["As At"] = this.parseDate(cleaned["As At"]);
    if (cleaned["Report Date"]) cleaned["Report Date"] = this.parseDate(cleaned["Report Date"]);
    if (cleaned["Statement Date"]) cleaned["Statement Date"] = this.parseDate(cleaned["Statement Date"]);

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
    const parts = s.split("/");
    if (parts.length === 3) {
      const day = parts[0].padStart(2, "0");
      const month = parts[1].padStart(2, "0");
      const year = parts[2].length === 2 ? `20${parts[2]}` : parts[2];
      const d = new Date(`${year}-${month}-${day}`);
      return isNaN(d.getTime()) ? null : d;
    }

    const fallback = new Date(s);
    return isNaN(fallback.getTime()) ? null : fallback;
  }

  static normalizePhone(phone) {
    if (!phone) return null;
    // Keep digits only
    const digits = String(phone).replace(/\D/g, "");
    // Example: turn 097xxxxxxx into 26097xxxxxxx if you want
    // (optional) — keep simple for now:
    return digits.length ? digits : null;
  }

  static normalizeEmail(email) {
    if (!email) return null;
    return String(email).trim().toLowerCase();
  }

  static makeClientKey(csvData) {
    const email = this.normalizeEmail(csvData["Borrower Email"]);
    const phone = this.normalizePhone(csvData["Borrower Mobile"] || csvData["Borrower Landline"]);

    // Best unique keys first
    if (phone) return `phone:${phone}`;
    if (email) return `email:${email}`;

    // Fallback (less safe): name + dob
    const name = (csvData["Full Name"] || csvData["Borrower Name"] || "").trim().toLowerCase();
    const dob = csvData["Borrower Date Of Birth"]
      ? new Date(csvData["Borrower Date Of Birth"]).toISOString().slice(0, 10)
      : "nodob";

    return `name:${name}|dob:${dob}`;
  }

  static computeBalance(csvData) {
    // Prefer explicit balance columns if present
    const direct =
      csvData["Client Balance"] ??
      csvData["Outstanding Balance"] ??
      csvData["Balance"] ??
      null;

    if (direct != null) return Number(direct || 0);

    // Otherwise fall back to a sensible “due/outstanding” field
    // (this is usually closer to current balance than Principal Amount)
    if (csvData["Amortization Due"] != null) return Number(csvData["Amortization Due"] || 0);

    // last fallback: penalty + interest (avoid principal because it may be original amount)
    const interest = Number(csvData["Total Interest Balance"] || 0);
    const penalty = Number(csvData["Penalty Amount"] || 0);
    return interest + penalty;
  }

  static classifyStatus(loanStatusRaw) {
    const s = String(loanStatusRaw || "Unknown").toLowerCase();

    const clearedWords = ["cleared", "closed", "paid", "settled", "completed"];
    const extendedWords = ["extended", "rescheduled", "restructured", "rollover"];

    const isCleared = clearedWords.some((w) => s.includes(w));
    const isExtended = extendedWords.some((w) => s.includes(w));

    return { isCleared, isExtended };
  }

  static pickStatementDate(csvData) {
    // Prefer a report date if your CSV has it
    return (
      csvData["Statement Date"] ||
      csvData["Report Date"] ||
      csvData["As At"] ||
      csvData["Next Due Date"] ||
      null
    );
  }

  static mapToClientSchema(csvData) {
    const loanStatus = csvData["Loan Status Name"] || csvData["Loan Status"] || "Unknown";
    const { isCleared, isExtended } = this.classifyStatus(loanStatus);

    let balance = this.computeBalance(csvData);
    if (isCleared) balance = 0; // force cleared to zero

    const statusBucket = isExtended ? "extended" : isCleared ? "cleared" : "balance";

    return {
      clientKey: this.makeClientKey(csvData),

      fullName: csvData["Full Name"] || csvData["Borrower Name"] || "",
      phone: this.normalizePhone(csvData["Borrower Mobile"] || csvData["Borrower Landline"]),
      email: this.normalizeEmail(csvData["Borrower Email"]),
      address: csvData["Borrower Address"] || null,
      dateOfBirth: csvData["Borrower Date Of Birth"] || null,

      loanStatus,
      isExtended,
      statusBucket,

      balance,
      statementDate: this.pickStatementDate(csvData),
    };
  }
}

module.exports = DataCleaner;
