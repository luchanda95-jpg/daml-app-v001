const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const Loan = require('../models/Loan');

function escapeRegex(s = '') {
  return String(s).replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&');
}

function normalizePhone(phone) {
  if (!phone) return '';
  return phone.replace(/\D/g, '').replace(/^0/, '');
}

function extractPrimaryName(fullName) {
  if (!fullName) return '';
  const parts = fullName.trim().split(/\s+/);
  return parts.length > 0 ? parts[0] : fullName;
}

function normalizeLoanForClient(raw) {
  const get = (k) => raw[k];
  const id = raw && (raw._id ? String(raw._id) : (raw.id ? String(raw.id) : '')) || '';
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
  };
}

// GET /api/loans?email=...&phone=...&name=...&limit=...&exactMatch=...
router.get('/', async (req, res) => {
  try {
    const { email, phone, name, limit, exactMatch } = req.query;
    const qLimit = Math.min(parseInt(limit || '50', 10), 200);
    const useExactMatch = exactMatch === 'true';
    
    const matchStages = [];

    // Enhanced phone matching with normalization
    if (phone && phone.trim()) {
      const cleanPhone = normalizePhone(phone.trim());
      if (cleanPhone) {
        if (useExactMatch) {
          matchStages.push({ 
            $expr: { 
              $eq: [
                { $replaceAll: { input: { $replaceAll: { input: '$borrowerMobile', find: ' ', replacement: '' } }, find: '-', replacement: '' } },
                cleanPhone
              ]
            }
          });
        } else {
          matchStages.push({ 
            borrowerMobile: { $regex: cleanPhone, $options: 'i' } 
          });
        }
      }
    }

    // Enhanced email matching
    if (email && email.trim()) {
      const cleanEmail = email.toLowerCase().trim();
      if (useExactMatch) {
        matchStages.push({ borrowerEmail: { $regex: `^${escapeRegex(cleanEmail)}$`, $options: 'i' } });
      } else {
        matchStages.push({ borrowerEmail: { $regex: escapeRegex(cleanEmail), $options: 'i' } });
      }
    }

    // Enhanced name matching
    if (name && name.trim()) {
      const cleanName = name.trim();
      const primaryName = extractPrimaryName(cleanName);
      
      if (useExactMatch) {
        matchStages.push({ fullName: { $regex: `^${escapeRegex(cleanName)}$`, $options: 'i' } });
      } else {
        // Try full name first, then primary name
        matchStages.push({ fullName: { $regex: escapeRegex(cleanName), $options: 'i' } });
        if (primaryName !== cleanName) {
          matchStages.push({ fullName: { $regex: escapeRegex(primaryName), $options: 'i' } });
        }
      }
    }

    const pipeline = [];
    
    if (matchStages.length > 0) {
      pipeline.push({ $match: { $or: matchStages } });
    }

    // Add scoring and sorting
    pipeline.push(
      {
        $addFields: {
          matchScore: {
            $add: [
              { $cond: [{ $eq: ['$borrowerEmail', email] }, 10, 0] },
              { $cond: [{ $eq: [{ $replaceAll: { input: { $replaceAll: { input: '$borrowerMobile', find: ' ', replacement: '' } }, find: '-', replacement: '' } }, normalizePhone(phone)] }, 8, 0] },
              { $cond: [{ $eq: ['$fullName', name] }, 6, 0] },
              { $cond: [{ $gt: ['$principalAmount', 0] }, 1, 0] }
            ]
          }
        }
      },
      { $sort: { matchScore: -1, nextDueDate: 1, createdAt: -1 } },
      { $limit: qLimit }
    );

    let raws = [];
    if (pipeline.length > 0) {
      raws = await Loan.aggregate(pipeline).exec();
    } else {
      raws = await Loan.find().limit(qLimit).lean().exec();
    }

    const loans = raws.map(normalizeLoanForClient);
    
    // Log matching results for debugging
    console.log(`Loan query: email=${email}, phone=${phone}, name=${name}, found=${loans.length}`);
    
    return res.json({ 
      success: true, 
      count: loans.length, 
      loans,
      query: { email, phone, name }
    });
  } catch (err) {
    console.error('GET /api/loans error', err);
    return res.status(500).json({ 
      success: false, 
      error: 'Internal Server Error',
      message: err.message 
    });
  }
});

// GET /api/loans/:id - Enhanced single loan lookup
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    if (!id || id.trim() === '') {
      return res.status(400).json({ 
        success: false, 
        error: 'Loan ID is required' 
      });
    }

    let doc = null;
    
    // Try multiple lookup strategies
    const lookupConditions = [];
    
    // ObjectId lookup
    if (mongoose.Types.ObjectId.isValid(id)) {
      lookupConditions.push({ _id: new mongoose.Types.ObjectId(id) });
    }
    
    // String ID lookup
    lookupConditions.push({ _id: id });
    lookupConditions.push({ id: id });
    
    // Branch ID lookup
    lookupConditions.push({ branchId: id });
    
    // Phone number lookup (with normalization)
    const cleanPhone = normalizePhone(id);
    if (cleanPhone) {
      lookupConditions.push({ 
        $expr: { 
          $eq: [
            { $replaceAll: { input: { $replaceAll: { input: '$borrowerMobile', find: ' ', replacement: '' } }, find: '-', replacement: '' } },
            cleanPhone
          ]
        }
      });
    }

    doc = await Loan.findOne({ $or: lookupConditions }).lean().exec();

    if (!doc) {
      return res.status(404).json({ 
        success: false, 
        error: 'Loan not found',
        searchedId: id 
      });
    }

    const normalized = normalizeLoanForClient(doc);
    return res.json({ 
      success: true, 
      loan: normalized 
    });
  } catch (err) {
    console.error('GET /api/loans/:id error', err);
    return res.status(500).json({ 
      success: false, 
      error: 'Internal Server Error',
      message: err.message 
    });
  }
});

// POST /api/loans/bulk-query - For complex queries
router.post('/bulk-query', async (req, res) => {
  try {
    const { queries, limit = 50 } = req.body;
    
    if (!Array.isArray(queries)) {
      return res.status(400).json({ 
        success: false, 
        error: 'Queries array is required' 
      });
    }

    const allLoans = [];
    const processedQueries = new Set();

    for (const query of queries) {
      const { email, phone, name } = query;
      const queryKey = `${email}|${phone}|${name}`;
      
      // Avoid duplicate queries
      if (processedQueries.has(queryKey)) continue;
      processedQueries.add(queryKey);

      const matchStages = [];
      
      if (email && email.trim()) {
        const cleanEmail = email.toLowerCase().trim();
        matchStages.push({ borrowerEmail: { $regex: `^${escapeRegex(cleanEmail)}$`, $options: 'i' } });
      }

      if (phone && phone.trim()) {
        const cleanPhone = normalizePhone(phone.trim());
        if (cleanPhone) {
          matchStages.push({ 
            $expr: { 
              $eq: [
                { $replaceAll: { input: { $replaceAll: { input: '$borrowerMobile', find: ' ', replacement: '' } }, find: '-', replacement: '' } },
                cleanPhone
              ]
            }
          });
        }
      }

      if (name && name.trim()) {
        const cleanName = name.trim();
        matchStages.push({ fullName: { $regex: escapeRegex(cleanName), $options: 'i' } });
      }

      if (matchStages.length > 0) {
        const pipeline = [
          { $match: { $or: matchStages } },
          { $limit: Math.min(limit, 20) }
        ];

        const results = await Loan.aggregate(pipeline).exec();
        allLoans.push(...results.map(normalizeLoanForClient));
      }
    }

    // Remove duplicates based on loan ID
    const uniqueLoans = Array.from(new Map(allLoans.map(loan => [loan.id, loan])).values());

    return res.json({
      success: true,
      count: uniqueLoans.length,
      loans: uniqueLoans,
      queryCount: processedQueries.size
    });
  } catch (err) {
    console.error('POST /api/loans/bulk-query error', err);
    return res.status(500).json({ 
      success: false, 
      error: 'Internal Server Error',
      message: err.message 
    });
  }
});

module.exports = router;