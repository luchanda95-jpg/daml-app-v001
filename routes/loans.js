// routes/loans.js
const express = require('express');
const router = express.Router();
const Loan = require('../models/Loan');

function escapeRegex(s = '') {
  return String(s).replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&');
}

function normalizeLoanForClient(raw) {
  // safe getters
  const get = (k) => raw[k];
  // convert ObjectId -> string
  const id = raw._id ? String(raw._id) : (raw.id ? String(raw.id) : '');
  // helper to coerce numbers
  const num = (v) => {
    if (v == null) return 0;
    if (typeof v === 'number') return v;
    if (typeof v === 'string') {
      const cleaned = v.replace(/,/g, '').trim();
      const n = Number(cleaned);
      return Number.isNaN(n) ? 0 : n;
    }
    // handle nested mongo shapes like { $numberInt: "10" } or { $numberLong: "123" }
    if (typeof v === 'object') {
      for (const val of Object.values(v)) {
        if (typeof val === 'string') {
          const cleaned = val.replace(/,/g, '').trim();
          const n = Number(cleaned);
          if (!Number.isNaN(n)) return n;
        }
        if (typeof val === 'number') return val;
      }
    }
    return 0;
  };
  const dateToIso = (x) => {
    if (!x) return null;
    // Date instance
    if (x instanceof Date && !isNaN(x.getTime())) return x.toISOString();
    // number (ms)
    if (typeof x === 'number') return new Date(x).toISOString();
    // string
    if (typeof x === 'string') {
      const d = new Date(x);
      if (!isNaN(d.getTime())) return d.toISOString();
      return x; // leave string (maybe already ISO-like)
    }
    // nested mongo date shapes
    if (typeof x === 'object') {
      // { $date: "..." } or { $date: { $numberLong: "..." } }
      if (x.$date) {
        if (typeof x.$date === 'string') return new Date(x.$date).toISOString();
        if (typeof x.$date === 'object' && x.$date.$numberLong) {
          const ms = Number(x.$date.$numberLong);
          if (!Number.isNaN(ms)) return new Date(ms).toISOString();
        }
      }
      // try to find any number-like child
      for (const v of Object.values(x)) {
        const maybe = dateToIso(v);
        if (maybe) return maybe;
      }
    }
    return null;
  };

  return {
    _id: id, // keep _id but as string (your Dart accepts either _id.{ $oid } or id or _id string)
    id,     // help frontends that look for `id` top-level
    fullName: (get('fullName') || get('full_name') || '').toString(),
    borrowerMobile: (get('borrowerMobile') || get('borrower_mobile') || get('mobile') || get('phone') || '') || null,
    borrowerLandline: (get('borrowerLandline') || get('borrower_landline') || '') || null,
    borrowerEmail: (get('borrowerEmail') || get('borrower_email') || '') || null,
    borrowerAddress: (get('borrowerAddress') || get('borrower_address') || '') || null,
    borrowerDateOfBirth: dateToIso(get('borrowerDateOfBirth') || get('borrower_date_of_birth') || null),
    loanStatus: (get('loanStatus') || get('loan_status') || 'Unknown').toString(),
    principalAmount: num(get('principalAmount') || get('principal_amount')),
    totalInterestBalance: num(get('totalInterestBalance') || get('total_interest_balance')),
    amortizationDue: num(get('amortizationDue') || get('amortization_due')),
    nextInstallmentAmount: num(get('nextInstallmentAmount') || get('next_installment_amount')),
    nextDueDate: dateToIso(get('nextDueDate') || get('next_due_date') || null),
    penaltyAmount: num(get('penaltyAmount') || get('penalty_amount')),
    branchId: (get('branchId') || get('branch_id') || '')?.toString() || '',
    importedAt: dateToIso(get('importedAt') || get('imported_at') || get('createdAt') || null),
    createdAt: dateToIso(get('createdAt') || get('created_at') || null),
    updatedAt: dateToIso(get('updatedAt') || get('updated_at') || null),
    // include any other fields raw if you want to debug (optional)
    // raw: raw
  };
}

// GET /api/loans?email=...&phone=...&name=...&limit=...
router.get('/', async (req, res) => {
  try {
    const { email, phone, name, limit } = req.query;
    const qLimit = Math.min(parseInt(limit || '50', 10), 200);
    const or = [];

    if (phone && phone.trim()) {
      const p = phone.trim();
      or.push({ borrowerMobile: { $regex: escapeRegex(p), $options: 'i' } });
      const digits = p.replace(/\D/g, '');
      if (digits) or.push({ borrowerMobile: { $regex: digits, $options: 'i' } });
      or.push({ borrowerLandline: { $regex: escapeRegex(p), $options: 'i' } });
    }

    if (email && email.trim()) {
      const e = String(email).toLowerCase().trim();
      or.push({ borrowerEmail: { $regex: `^${escapeRegex(e)}$`, $options: 'i' } });
      or.push({ borrowerEmail: { $regex: escapeRegex(e), $options: 'i' } });
    }

    if (name && name.trim()) {
      const n = name.trim();
      or.push({ fullName: { $regex: escapeRegex(n), $options: 'i' } });
      const tokens = n.split(/\s+/).filter(Boolean);
      if (tokens.length) {
        or.push({ fullName: { $regex: tokens.join('|'), $options: 'i' } });
      }
    }

    const filter = or.length ? { $or: or } : {};
    // fetch as lean (POJOs)
    const raws = await Loan.find(filter).limit(qLimit).lean().exec();
    const loans = raws.map(normalizeLoanForClient);
    return res.json({ success: true, count: loans.length, loans });
  } catch (err) {
    console.error('GET /api/loans error', err);
    return res.status(500).json({ success: false, error: 'Internal Server Error' });
  }
});

module.exports = router;
