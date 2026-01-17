// routes/zanaco.js
const express = require('express');
const router = express.Router();
const ZanacoDistribution = require('../models/ZanacoDistribution');

/** normalize date to UTC midnight */
function normalizeToUtcDay(dateInput) {
  const d = new Date(dateInput);
  if (isNaN(d.getTime())) return null;
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 0, 0, 0));
}

function norm(v) {
  return (v || '').toString().trim().toLowerCase();
}

/**
 * GET /zanaco
 * Query:
 *  - date (optional)
 *  - branch (receiver optional)
 *  - fromBranch (sender optional)
 *  - channel (optional)
 *  - aggregate=true -> totals per channel
 */
router.get('/zanaco', async (req, res) => {
  try {
    const { branch, fromBranch, channel, date, aggregate } = req.query;

    const q = {};
    if (branch) q.branch = norm(branch);
    if (fromBranch) q.fromBranch = norm(fromBranch);
    if (channel) q.channel = norm(channel);

    if (date) {
      const nd = normalizeToUtcDay(date);
      if (nd) q.date = nd;
    }

    if (aggregate === 'true' || aggregate === '1') {
      const agg = await ZanacoDistribution.aggregate([
        { $match: q },
        { $group: { _id: '$channel', total: { $sum: '$amount' } } },
      ]);
      const out = {};
      agg.forEach((i) => (out[i._id] = i.total));
      return res.json(out);
    }

    const docs = await ZanacoDistribution.find(q).sort({ date: -1 }).lean();
    return res.json(docs);
  } catch (err) {
    console.error('GET /zanaco error', err);
    return res.status(500).json({ success: false, error: 'Failed to fetch zanaco distributions', details: err.message });
  }
});

/**
 * GET /zanaco/distributions
 * Returns { distributions: [...] }
 * Query supports receiver branch/date, and optionally fromBranch/channel
 */
router.get('/zanaco/distributions', async (req, res) => {
  try {
    const { branch, fromBranch, channel, date } = req.query;

    const q = {};
    if (branch) q.branch = norm(branch);
    if (fromBranch) q.fromBranch = norm(fromBranch);
    if (channel) q.channel = norm(channel);

    if (date) {
      const nd = normalizeToUtcDay(date);
      if (nd) q.date = nd;
    }

    const docs = await ZanacoDistribution.find(q).sort({ date: -1 }).lean();
    return res.json({ distributions: docs });
  } catch (err) {
    console.error('GET /zanaco/distributions error', err);
    return res.status(500).json({ success: false, error: 'Failed to fetch distributions', details: err.message });
  }
});

/**
 * ✅ NEW: GET /zanaco/summary?branch=...&date=...
 * Returns:
 *  - received totals (where branch == receiver)
 *  - sent totals (where fromBranch == sender)
 */
router.get('/zanaco/summary', async (req, res) => {
  try {
    const b = norm(req.query.branch);
    const nd = normalizeToUtcDay(req.query.date);

    if (!b || !nd) {
      return res.status(400).json({ success: false, error: 'branch and valid date are required' });
    }

    const receivedAgg = await ZanacoDistribution.aggregate([
      { $match: { date: nd, branch: b } },
      { $group: { _id: '$channel', total: { $sum: '$amount' } } },
    ]);

    const sentAgg = await ZanacoDistribution.aggregate([
      { $match: { date: nd, fromBranch: b } },
      { $group: { _id: '$channel', total: { $sum: '$amount' } } },
    ]);

    const received = { airtel: 0, mtn: 0, total: 0 };
    const sent = { airtel: 0, mtn: 0, total: 0 };

    for (const r of receivedAgg) {
      const ch = (r._id || '').toString().toLowerCase();
      if (ch.includes('airtel')) received.airtel += r.total;
      else if (ch.includes('mtn')) received.mtn += r.total;
      else received.total += r.total;
    }

    for (const s of sentAgg) {
      const ch = (s._id || '').toString().toLowerCase();
      if (ch.includes('airtel')) sent.airtel += s.total;
      else if (ch.includes('mtn')) sent.mtn += s.total;
      else sent.total += s.total;
    }

    received.total = received.airtel + received.mtn + (received.total || 0);
    sent.total = sent.airtel + sent.mtn + (sent.total || 0);

    return res.json({
      success: true,
      branch: b,
      date: nd.toISOString(),
      received,
      sent,
      net: received.total - sent.total,
    });
  } catch (err) {
    console.error('GET /zanaco/summary error', err);
    return res.status(500).json({ success: false, error: 'Failed to fetch summary', details: err.message });
  }
});

/**
 * POST /zanaco
 * Body: { date, fromBranch, branch, channel, amount, metadata }
 */
router.post('/zanaco', async (req, res) => {
  try {
    const { date, fromBranch, branch, channel, amount, metadata } = req.body;

    if (!date || !fromBranch || !branch || !channel || amount === undefined || amount === null) {
      return res.status(400).json({ success: false, error: 'date, fromBranch, branch, channel and amount are required' });
    }

    const nd = normalizeToUtcDay(date);
    if (!nd) return res.status(400).json({ success: false, error: 'Invalid date' });

    const filter = {
      date: nd,
      fromBranch: norm(fromBranch),
      branch: norm(branch),
      channel: norm(channel),
    };

    const update = { $set: { amount: Number(amount), metadata: metadata || {} } };
    const opts = { upsert: true, new: true, setDefaultsOnInsert: true };

    const doc = await ZanacoDistribution.findOneAndUpdate(filter, update, opts).lean();
    return res.json({ success: true, distribution: doc });
  } catch (err) {
    console.error('POST /zanaco error', err);
    return res.status(500).json({ success: false, error: 'Failed to save distribution', details: err.message });
  }
});

/**
 * POST /zanaco/bulk
 * Body: { date, fromBranch, allocations: { toBranch: { airtel: x, mtn: y } } }
 */
router.post('/zanaco/bulk', async (req, res) => {
  try {
    const { date, fromBranch, allocations } = req.body;

    const nd = date ? normalizeToUtcDay(date) : null;
    const sender = norm(fromBranch);

    if (!nd) return res.status(400).json({ success: false, error: 'Valid date is required' });
    if (!sender) return res.status(400).json({ success: false, error: 'fromBranch is required' });

    if (!allocations || typeof allocations !== 'object') {
      return res.status(400).json({ success: false, error: 'allocations object is required' });
    }

    const ops = [];

    for (const toBranch of Object.keys(allocations)) {
      const channelsMap = allocations[toBranch];
      if (!channelsMap || typeof channelsMap !== 'object') continue;

      for (const ch of Object.keys(channelsMap)) {
        const amt = Number(channelsMap[ch] || 0);
        if (!amt) continue;

        ops.push({
          updateOne: {
            filter: {
              date: nd,
              fromBranch: sender,
              branch: norm(toBranch),
              channel: norm(ch),
            },
            update: {
              $set: { amount: amt, metadata: {} },
            },
            upsert: true,
          },
        });
      }
    }

    if (ops.length === 0) return res.status(400).json({ success: false, error: 'No operations to perform' });

    const bulkRes = await ZanacoDistribution.bulkWrite(ops, { ordered: false });

    return res.json({
      success: true,
      message: `Saved ${ops.length} distributions`,
      result: bulkRes,
    });
  } catch (err) {
    console.error('POST /zanaco/bulk error', err);
    return res.status(500).json({ success: false, error: 'Failed to process bulk', details: err.message });
  }
});

module.exports = router;
