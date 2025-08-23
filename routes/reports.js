// routes/reports.js
const express = require('express');
const router = express.Router();
const DailyReport = require('../models/DailyReport');

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
    const canonicalTargets = []; // array of { branch, date } for post-query

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

        // sanitize
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

        // Build updateOne op for bulkWrite
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

        // store target so we can query saved docs afterwards
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

    // Execute bulkWrite unordered for speed; capture any top-level write errors
    let bulkResult;
    try {
      bulkResult = await DailyReport.bulkWrite(operations, { ordered: false });
    } catch (bulkErr) {
      // bulkWrite can throw on catastrophic failures; we still try to gather what might have been saved
      console.error('bulkWrite error:', bulkErr);
      errors.push({ error: 'bulkWrite failed', detail: bulkErr.message || String(bulkErr) });
    }

    // Query DB for the saved/updated documents that match the canonicalTargets
    // Build $or filters (branch + date exact) — these dates are Date objects normalized to UTC-midnight
    const orFilters = canonicalTargets.map(t => ({ branch: t.branch, date: t.date }));

    // If many targets, you might consider chunking this query
    let savedDocs = [];
    if (orFilters.length > 0) {
      try {
        savedDocs = await DailyReport.find({ $or: orFilters }).select('branch date _id').lean();
      } catch (qerr) {
        console.error('Query after bulkWrite failed:', qerr);
        errors.push({ error: 'post-query failed', detail: qerr.message || String(qerr) });
      }
    }

    // Build saved descriptors to return to client
    const saved = savedDocs.map(d => ({
      branch: d.branch,
      date: new Date(d.date).toISOString(), // ensure ISO normalized date
      id: d._id ? d._id.toString() : null
    }));

    // Return diagnostics including raw bulk result summary (if available)
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

/**
 * DELETE /api/reports
 * Body: { branch: string, date: string (ISO) }
 * Deletes the report for the given branch on the given day (day-range match).
 */
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

/**
 * DELETE /api/reports/:id
 * Deletes by Mongo _id
 */
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

module.exports = router;
