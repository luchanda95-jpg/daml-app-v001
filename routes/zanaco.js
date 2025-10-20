// routes/zanaco.js
const express = require('express');
const router = express.Router();
const ZanacoDistribution = require('../models/ZanacoDistribution'); // update path as needed
const mongoose = require('mongoose');

/**
 * normalizeToUtcDay - same logic as model's helper
 * accepts Date or ISO string.
 */
function normalizeToUtcDay(dateInput) {
  const d = new Date(dateInput);
  if (isNaN(d.getTime())) return null;
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 0, 0, 0));
}

/**
 * GET /zanaco
 * Query params:
 *  - branch (optional)
 *  - date (optional)   // expects YYYY-MM-DD or any parseable date
 *  - channel (optional)
 *  - aggregate (optional, boolean) -> if true returns { airtel: X, mtn: Y, ... }
 *
 * Returns list of matching distributions by default.
 */
router.get('/zanaco', async (req, res) => {
  try {
    const { branch, channel, date, aggregate } = req.query;

    const q = {};
    if (branch) q.branch = branch.toString().trim().toLowerCase();
    if (channel) q.channel = channel.toString().trim().toLowerCase();
    if (date) {
      const nd = normalizeToUtcDay(date);
      if (nd) q.date = nd;
    }

    if (aggregate === 'true' || aggregate === '1') {
      // aggregate totals per channel for the query
      const pipeline = [{ $match: q }, {
        $group: {
          _id: '$channel',
          total: { $sum: '$amount' }
        }
      }];
      const agg = await ZanacoDistribution.aggregate(pipeline);
      const out = {};
      agg.forEach(item => { out[item._id] = item.total; });
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
 * Backwards-compatible shape: returns { distributions: [ ... ] }
 * Accepts same query params as /zanaco
 */
router.get('/zanaco/distributions', async (req, res) => {
  try {
    const { branch, channel, date } = req.query;
    const q = {};
    if (branch) q.branch = branch.toString().trim().toLowerCase();
    if (channel) q.channel = channel.toString().trim().toLowerCase();
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
 * POST /zanaco
 * Body: { date: '2025-10-16', branch: 'monze', channel: 'airtel', amount: 10000, metadata: {} }
 * Performs upsert by date+branch+channel.
 */
router.post('/zanaco', async (req, res) => {
  try {
    const { date, branch, channel, amount, metadata } = req.body;
    if (!date || !branch || !channel || (amount === undefined || amount === null)) {
      return res.status(400).json({ success: false, error: 'date, branch, channel and amount are required' });
    }

    const nd = normalizeToUtcDay(date);
    if (!nd) return res.status(400).json({ success: false, error: 'Invalid date' });

    const filter = { date: nd, branch: branch.toString().trim().toLowerCase(), channel: channel.toString().trim().toLowerCase() };
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
 * Body: { date: '2025-10-16', allocations: { 'fromBranch':..., 'allocations': { 'toBranch': { 'airtel': 100, 'mtn': 50 } } } or distributions: [ {branch, channel, amount, date } ] }
 * Accepts either an array of distribution docs in `distributions` or `allocations` map.
 */
router.post('/zanaco/bulk', async (req, res) => {
  try {
    const { date, distributions, allocations } = req.body;
    const nd = date ? normalizeToUtcDay(date) : null;

    const ops = [];

    if (Array.isArray(distributions) && distributions.length > 0) {
      for (const d of distributions) {
        const dDate = normalizeToUtcDay(d.date || nd) || nd;
        if (!dDate) continue;
        const branch = (d.branch || '').toString().trim().toLowerCase();
        const channel = (d.channel || '').toString().trim().toLowerCase();
        const amount = Number(d.amount || 0);
        if (!branch || !channel) continue;
        ops.push({
          updateOne: {
            filter: { date: dDate, branch, channel },
            update: { $set: { amount, metadata: d.metadata || {} } },
            upsert: true,
          }
        });
      }
    } else if (allocations && typeof allocations === 'object') {
      // example: allocations = { toBranch: { airtel: 10000, mtn: 5000 } } or allocations = { 'monze': {'airtel':10000, 'mtn':5000}, ...}
      for (const toBranch of Object.keys(allocations)) {
        const channelsMap = allocations[toBranch];
        if (typeof channelsMap !== 'object') continue;
        for (const ch of Object.keys(channelsMap)) {
          const amt = Number(channelsMap[ch] || 0);
          if (!amt) continue;
          const branch = toBranch.toString().trim().toLowerCase();
          const channel = ch.toString().trim().toLowerCase();
          const dDate = nd || normalizeToUtcDay(new Date());
          ops.push({
            updateOne: {
              filter: { date: dDate, branch, channel },
              update: { $set: { amount: amt, metadata: {} } },
              upsert: true,
            }
          });
        }
      }
    } else {
      return res.status(400).json({ success: false, error: 'No valid distributions or allocations provided' });
    }

    if (ops.length === 0) return res.status(400).json({ success: false, error: 'No operations to perform' });

    const bulkRes = await ZanacoDistribution.bulkWrite(ops, { ordered: false });
    return res.json({ success: true, result: bulkRes });
  } catch (err) {
    console.error('POST /zanaco/bulk error', err);
    return res.status(500).json({ success: false, error: 'Failed to process bulk', details: err.message });
  }
});

module.exports = router;
