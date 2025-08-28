// routes/reports.js
const express = require('express');
const router = express.Router();
const DailyReport = require('../models/DailyReport');
const MonthlyReport = require('../models/MonthlyReport'); // <- added

/**
 * Normalize a date string / Date to UTC midnight (00:00:00 UTC)
 * Returns a Date object representing UTC midnight for that day, or null if invalid.
 */
function normalizeDateToDay(dateInput) {
  const d = new Date(dateInput);
  if (isNaN(d.getTime())) return null;
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

/**
 * Normalize a date to UTC month start (first day at 00:00:00 UTC)
 */
function normalizeDateToMonthStart(dateInput) {
  const d = new Date(dateInput);
  if (isNaN(d.getTime())) return null;
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1));
}

/**
 * Ensure a "map-like" value from client is converted to a plain object
 * with numeric (float) values. Non-numeric values become 0.
 */
function sanitizeNumericMap(maybe) {
  if (!maybe || typeof maybe !== 'object') return {};
  const out = {};
  for (const [k, v] of Object.entries(maybe)) {
    const num = (typeof v === 'number') ? v : (v === null || v === '' ? 0 : Number(v));
    out[k] = Number.isNaN(num) ? 0 : num;
  }
  return out;
}

/**
 * Like sanitizeNumericMap but coerces to integers.
 */
function sanitizeIntegerMap(maybe) {
  if (!maybe || typeof maybe !== 'object') return {};
  const out = {};
  for (const [k, v] of Object.entries(maybe)) {
    if (typeof v === 'number') out[k] = Math.trunc(v);
    else if (typeof v === 'string') {
      const asInt = parseInt(v, 10);
      if (!Number.isNaN(asInt)) out[k] = asInt;
      else {
        const asFloat = parseFloat(v);
        out[k] = Number.isNaN(asFloat) ? 0 : Math.trunc(asFloat);
      }
    } else out[k] = 0;
  }
  return out;
}

/**
 * Coerce a scalar to number (float). Null/invalid -> 0.
 */
function toNumber(v) {
  if (v == null) return 0;
  if (typeof v === 'number') return v;
  if (typeof v === 'string') {
    const n = Number(v);
    return Number.isNaN(n) ? 0 : n;
  }
  return 0;
}

// -----------------------------
// DAILY routes
// -----------------------------

// POST /api/sync_reports - using bulkWrite for performance
router.post('/sync_reports', async (req, res) => {
  try {
    const { reports } = req.body;
    if (!reports || !Array.isArray(reports)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid request: expected { reports: [...] }'
      });
    }

    const operations = [];
    const skipped = [];
    const errors = [];
    const canonicalTargets = [];

    for (const raw of reports) {
      try {
        if (!raw || typeof raw !== 'object') {
          skipped.push({ reason: 'invalid item (not object)', item: raw });
          continue;
        }

        const branch = raw.branch ? String(raw.branch).trim() : '';
        if (!branch) {
          skipped.push({ reason: 'missing branch', item: raw });
          continue;
        }

        const normalizedDate = normalizeDateToDay(raw.date);
        if (!normalizedDate) {
          skipped.push({ reason: 'invalid date', item: raw });
          continue;
        }

        const openingBalances = sanitizeNumericMap(raw.openingBalances);
        const closingBalances = sanitizeNumericMap(raw.closingBalances);
        const loanCounts = sanitizeIntegerMap(raw.loanCounts);

        const updateData = {
          branch,
          date: normalizedDate,
          openingBalances,
          loanCounts,
          closingBalances,
          totalDisbursed: toNumber(raw.totalDisbursed),
          totalCollected: toNumber(raw.totalCollected),
          collectedForOtherBranches: toNumber(raw.collectedForOtherBranches),
          pettyCash: toNumber(raw.pettyCash),
          expenses: toNumber(raw.expenses),
          synced: true,
          updatedAt: raw.updatedAt ? new Date(raw.updatedAt) : new Date()
        };

        operations.push({
          updateOne: {
            filter: { branch: branch, date: normalizedDate },
            update: {
              $set: updateData,
              $setOnInsert: { createdAt: new Date() }
            },
            upsert: true
          }
        });

        canonicalTargets.push({ branch, date: normalizedDate });
      } catch (inner) {
        console.error('prepare op error:', inner);
        errors.push({ item: raw, error: inner.message || String(inner) });
      }
    }

    if (operations.length === 0) {
      return res.json({
        success: true,
        message: 'No valid reports to process',
        saved: [],
        skipped,
        errors
      });
    }

    let bulkResult;
    try {
      bulkResult = await DailyReport.bulkWrite(operations, { ordered: false });
    } catch (bulkErr) {
      console.error('bulkWrite error:', bulkErr);
      errors.push({ error: 'bulkWrite failed', detail: bulkErr.message || String(bulkErr) });
    }

    const orFilters = canonicalTargets.map(t => ({ branch: t.branch, date: t.date }));

    let savedDocs = [];
    if (orFilters.length > 0) {
      try {
        savedDocs = await DailyReport.find({ $or: orFilters }).select('branch date _id').lean();
      } catch (qerr) {
        console.error('Query after bulkWrite failed:', qerr);
        errors.push({ error: 'post-query failed', detail: qerr.message || String(qerr) });
      }
    }

    const saved = savedDocs.map(d => ({
      branch: d.branch,
      date: new Date(d.date).toISOString(),
      id: d._id ? d._id.toString() : null
    }));

    return res.json({
      success: true,
      message: `${saved.length} reports processed (bulkWrite)`,
      saved,
      skipped,
      errors,
      bulkWriteResult: bulkResult ? {
        insertedCount: bulkResult.insertedCount || 0,
        matchedCount: bulkResult.matchedCount || 0,
        modifiedCount: bulkResult.modifiedCount || 0,
        upsertedCount: bulkResult.upsertedCount || 0,
        upsertedIds: bulkResult.upsertedIds || {}
      } : undefined
    });

  } catch (err) {
    console.error('POST /sync_reports catastrophic error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

// GET /api/reports - returns all reports sorted desc by date
router.get('/reports', async (req, res) => {
  try {
    const reports = await DailyReport.find().sort({ date: -1 });
    return res.json(reports);
  } catch (err) {
    console.error('GET /reports error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

// DELETE /api/reports (by branch + date day)
router.delete('/reports', async (req, res) => {
  try {
    const { branch, date } = req.body;
    if (!branch || !date) {
      return res.status(400).json({ success: false, error: 'branch and date are required' });
    }

    const parsed = new Date(date);
    if (isNaN(parsed.getTime())) {
      return res.status(400).json({ success: false, error: 'invalid date format' });
    }

    const startOfDay = new Date(Date.UTC(parsed.getUTCFullYear(), parsed.getUTCMonth(), parsed.getUTCDate(), 0, 0, 0));
    const endOfDay = new Date(startOfDay);
    endOfDay.setUTCDate(endOfDay.getUTCDate() + 1);

    const deleted = await DailyReport.findOneAndDelete({
      branch: branch,
      date: { $gte: startOfDay, $lt: endOfDay }
    });

    if (!deleted) {
      return res.status(404).json({ success: false, error: 'Report not found' });
    }

    return res.json({ success: true, message: 'Report deleted', deletedId: deleted._id.toString() });
  } catch (err) {
    console.error('DELETE /reports error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

// DELETE /api/reports/:id
router.delete('/reports/:id', async (req, res) => {
  try {
    const id = req.params.id;
    const deleted = await DailyReport.findByIdAndDelete(id);
    if (!deleted) return res.status(404).json({ success: false, error: 'Not found' });
    return res.json({ success: true, message: 'Report deleted', deletedId: deleted._id.toString() });
  } catch (err) {
    console.error('DELETE /reports/:id error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

// -----------------------------
// MONTHLY routes (new)
// -----------------------------

// POST /api/sync_monthly_reports - bulk upsert monthly reports
router.post('/sync_monthly_reports', async (req, res) => {
  try {
    const { monthlyReports } = req.body;
    if (!monthlyReports || !Array.isArray(monthlyReports)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid request: expected { monthlyReports: [...] }'
      });
    }

    const operations = [];
    const skipped = [];
    const errors = [];
    const canonicalTargets = [];

    for (const raw of monthlyReports) {
      try {
        if (!raw || typeof raw !== 'object') {
          skipped.push({ reason: 'invalid item (not object)', item: raw });
          continue;
        }

        const branch = raw.branch ? String(raw.branch).trim() : '';
        if (!branch) {
          skipped.push({ reason: 'missing branch', item: raw });
          continue;
        }

        const normalizedDate = normalizeDateToMonthStart(raw.date);
        if (!normalizedDate) {
          skipped.push({ reason: 'invalid date', item: raw });
          continue;
        }

        // coerce numeric fields defensively
        const updateData = {
          branch,
          date: normalizedDate,
          expected: toNumber(raw.expected),
          inputs: Number.isInteger(raw.inputs) ? raw.inputs : (raw.inputs ? parseInt(raw.inputs, 10) || 0 : 0),
          collected: toNumber(raw.collected),
          collectedInput: Number.isInteger(raw.collectedInput) ? raw.collectedInput : (raw.collectedInput ? parseInt(raw.collectedInput, 10) || 0 : 0),
          totalUncollected: toNumber(raw.totalUncollected),
          uncollectedInput: Number.isInteger(raw.uncollectedInput) ? raw.uncollectedInput : (raw.uncollectedInput ? parseInt(raw.uncollectedInput, 10) || 0 : 0),
          insufficient: toNumber(raw.insufficient),
          insufficientInput: Number.isInteger(raw.insufficientInput) ? raw.insufficientInput : (raw.insufficientInput ? parseInt(raw.insufficientInput, 10) || 0 : 0),
          unreported: toNumber(raw.unreported),
          unreportedInput: Number.isInteger(raw.unreportedInput) ? raw.unreportedInput : (raw.unreportedInput ? parseInt(raw.unreportedInput, 10) || 0 : 0),
          lateCollection: toNumber(raw.lateCollection),
          uncollected: toNumber(raw.uncollected),
          permicExpectedNextMonth: toNumber(raw.permicExpectedNextMonth),
          totalInputs: Number.isInteger(raw.totalInputs) ? raw.totalInputs : (raw.totalInputs ? parseInt(raw.totalInputs, 10) || 0 : 0),
          oldInputsAmount: toNumber(raw.oldInputsAmount),
          oldInputsCount: Number.isInteger(raw.oldInputsCount) ? raw.oldInputsCount : (raw.oldInputsCount ? parseInt(raw.oldInputsCount, 10) || 0 : 0),
          newInputsAmount: toNumber(raw.newInputsAmount),
          newInputsCount: Number.isInteger(raw.newInputsCount) ? raw.newInputsCount : (raw.newInputsCount ? parseInt(raw.newInputsCount, 10) || 0 : 0),
          cashAdvance: toNumber(raw.cashAdvance),
          overallExpected: toNumber(raw.overallExpected),
          actualExpected: toNumber(raw.actualExpected),
          collected2: toNumber(raw.collected2),
          principalReloaned: toNumber(raw.principalReloaned),
          defaultAmount: toNumber(raw.defaultAmount),
          clearance: toNumber(raw.clearance),
          totalCollections: toNumber(raw.totalCollections),
          permicCashAdvance: toNumber(raw.permicCashAdvance),
          synced: true,
          updatedAt: raw.updatedAt ? new Date(raw.updatedAt) : new Date()
        };

        operations.push({
          updateOne: {
            filter: { branch: branch, date: normalizedDate },
            update: {
              $set: updateData,
              $setOnInsert: { createdAt: new Date() }
            },
            upsert: true
          }
        });

        canonicalTargets.push({ branch, date: normalizedDate });
      } catch (inner) {
        console.error('prepare monthly op error:', inner);
        errors.push({ item: raw, error: inner.message || String(inner) });
      }
    }

    if (operations.length === 0) {
      return res.json({
        success: true,
        message: 'No valid monthly reports to process',
        saved: [],
        skipped,
        errors
      });
    }

    let bulkResult;
    try {
      bulkResult = await MonthlyReport.bulkWrite(operations, { ordered: false });
    } catch (bulkErr) {
      console.error('monthly bulkWrite error:', bulkErr);
      errors.push({ error: 'bulkWrite failed', detail: bulkErr.message || String(bulkErr) });
    }

    const orFilters = canonicalTargets.map(t => ({ branch: t.branch, date: t.date }));
    let savedDocs = [];
    if (orFilters.length > 0) {
      try {
        savedDocs = await MonthlyReport.find({ $or: orFilters }).select('branch date _id').lean();
      } catch (qerr) {
        console.error('Query after monthly bulkWrite failed:', qerr);
        errors.push({ error: 'post-query failed', detail: qerr.message || String(qerr) });
      }
    }

    const saved = savedDocs.map(d => ({
      branch: d.branch,
      date: new Date(d.date).toISOString(),
      id: d._id ? d._id.toString() : null
    }));

    return res.json({
      success: true,
      message: `${saved.length} monthly reports processed (bulkWrite)`,
      saved,
      skipped,
      errors,
      bulkWriteResult: bulkResult ? {
        insertedCount: bulkResult.insertedCount || 0,
        matchedCount: bulkResult.matchedCount || 0,
        modifiedCount: bulkResult.modifiedCount || 0,
        upsertedCount: bulkResult.upsertedCount || 0,
        upsertedIds: bulkResult.upsertedIds || {}
      } : undefined
    });

  } catch (err) {
    console.error('POST /sync_monthly_reports catastrophic error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

// GET /api/monthly_reports - returns all monthly reports sorted desc by date
router.get('/monthly_reports', async (req, res) => {
  try {
    const reports = await MonthlyReport.find().sort({ date: -1 });
    return res.json(reports);
  } catch (err) {
    console.error('GET /monthly_reports error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

// DELETE /api/monthly_reports - deletes by branch + month (body: { branch, date })
router.delete('/monthly_reports', async (req, res) => {
  try {
    const { branch, date } = req.body;
    if (!branch || !date) {
      return res.status(400).json({ success: false, error: 'branch and date are required' });
    }

    const parsed = new Date(date);
    if (isNaN(parsed.getTime())) {
      return res.status(400).json({ success: false, error: 'invalid date format' });
    }

    const startOfMonth = new Date(Date.UTC(parsed.getUTCFullYear(), parsed.getUTCMonth(), 1, 0, 0, 0));
    const startOfNextMonth = new Date(Date.UTC(parsed.getUTCFullYear(), parsed.getUTCMonth() + 1, 1, 0, 0, 0));

    const deleted = await MonthlyReport.findOneAndDelete({
      branch: branch,
      date: { $gte: startOfMonth, $lt: startOfNextMonth }
    });

    if (!deleted) {
      return res.status(404).json({ success: false, error: 'Monthly report not found' });
    }

    return res.json({ success: true, message: 'Monthly report deleted', deletedId: deleted._id.toString() });
  } catch (err) {
    console.error('DELETE /monthly_reports error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

// DELETE /api/monthly_reports/:id - delete by _id
router.delete('/monthly_reports/:id', async (req, res) => {
  try {
    const id = req.params.id;
    const deleted = await MonthlyReport.findByIdAndDelete(id);
    if (!deleted) return res.status(404).json({ success: false, error: 'Not found' });
    return res.json({ success: true, message: 'Monthly report deleted', deletedId: deleted._id.toString() });
  } catch (err) {
    console.error('DELETE /monthly_reports/:id error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

module.exports = router;
