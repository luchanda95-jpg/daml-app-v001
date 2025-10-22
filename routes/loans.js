// routes/loans.js (append or replace existing file content)
const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const Loan = require('../models/Loan'); // path as before

function escapeRegex(s = '') {
  return String(s).replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&');
}

// (keep your existing list/search route at router.get('/', ...) )

// helper used to normalize a Loan document for client (same as used earlier)
function normalizeLoanForClient(raw) {
  if (!raw) return null;
  const get = (k) => raw[k];
  const id = raw._id ? String(raw._id) : (raw.id ? String(raw.id) : '');
  const num = (v) => {
    if (v == null) return 0;
    if (typeof v === 'number') return v;
    if (typeof v === 'string') {
      const cleaned = v.replace(/,/g, '').trim();
      const n = Number(cleaned);
      return Number.isNaN(n) ? 0 : n;
    }
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
    if (x instanceof Date && !isNaN(x.getTime())) return x.toISOString();
    if (typeof x === 'number') return new Date(x).toISOString();
    if (typeof x === 'string') {
      const d = new Date(x);
      if (!isNaN(d.getTime())) return d.toISOString();
      return x;
    }
    if (typeof x === 'object') {
      if (x.$date) {
        if (typeof x.$date === 'string') return new Date(x.$date).toISOString();
        if (typeof x.$date === 'object' && x.$date.$numberLong) {
          const ms = Number(x.$date.$numberLong);
          if (!Number.isNaN(ms)) return new Date(ms).toISOString();
        }
      }
      for (const v of Object.values(x)) {
        const maybe = dateToIso(v);
        if (maybe) return maybe;
      }
    }
    return null;
  };

  return {
    _id: id,
    id,
    fullName: (get('fullName') || get('full_name') || '').toString(),
    borrowerMobile: (get('borrowerMobile') || get('borrower_mobile') || get('mobile') || get('phone') || null),
    borrowerLandline: (get('borrowerLandline') || get('borrower_landline') || null),
    borrowerEmail: (get('borrowerEmail') || get('borrower_email') || null),
    borrowerAddress: (get('borrowerAddress') || get('borrower_address') || null),
    borrowerDateOfBirth: dateToIso(get('borrowerDateOfBirth') || get('borrower_date_of_birth') || null),
    loanStatus: (get('loanStatus') || get('loan_status') || 'Unknown').toString(),
    principalAmount: num(get('principalAmount') || get('principal_amount')),
    totalInterestBalance: num(get('totalInterestBalance') || get('total_interest_balance')),
    amortizationDue: num(get('amortizationDue') || get('amortization_due')),
    nextInstallmentAmount: num(get('nextInstallmentAmount') || get('next_installment_amount')),
    nextDueDate: dateToIso(get('nextDueDate') || get('next_due_date') || null),
    penaltyAmount: num(get('penaltyAmount') || get('penalty_amount')),
    branchId: (get('branchId') || get('branch_id') || '')?.toString() || '',
    importedAt: dateToIso(get('importedAt') || get('imported_at') || null),
    createdAt: dateToIso(get('createdAt') || get('created_at') || null),
    updatedAt: dateToIso(get('updatedAt') || get('updated_at') || null),
  };
}

// GET single loan by id: /api/loans/:id
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    if (!id) return res.status(400).json({ success: false, error: 'id required' });

    // support either ObjectId or string id
    let doc;
    if (mongoose.Types.ObjectId.isValid(id)) {
      doc = await Loan.findById(id).lean().exec();
    } else {
      // fallback: try searching by branchId or custom id field
      doc = await Loan.findOne({ $or: [{ _id: id }, { id: id }, { branchId: id }] }).lean().exec();
    }

    if (!doc) return res.status(404).json({ success: false, error: 'Loan not found' });

    const normalized = normalizeLoanForClient(doc);
    return res.json({ success: true, loan: normalized });
  } catch (err) {
    console.error('GET /api/loans/:id error', err);
    return res.status(500).json({ success: false, error: 'Internal Server Error' });
  }
});

module.exports = router;
