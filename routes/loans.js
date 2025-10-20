// routes/loans.js (or controllers/loans.js)
const express = require('express');
const router = express.Router();
const Loan = require('../models/Loan'); // adjust path

function escapeRegex(s = '') {
  return s.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&');
}

router.get('/loans', async (req, res) => {
  try {
    const { email, phone, name, limit } = req.query;
    const qLimit = Math.min(parseInt(limit || '50', 10), 200); // safe cap
    const or = [];

    if (phone && phone.trim()) {
      // normalize digits for flexible matching
      const p = phone.trim();
      // match exact or contains; you can tighten to ^p$ if you want exact
      or.push({ borrowerMobile: { $regex: escapeRegex(p), $options: 'i' } });
      // also try matching only digits (strip spaces/plus)
      const digits = p.replace(/\D/g, '');
      if (digits) or.push({ borrowerMobile: { $regex: digits, $options: 'i' } });
    }

    if (email && email.trim()) {
      const e = email.trim().toLowerCase();
      // case-insensitive exact or contains
      or.push({ borrowerEmail: { $regex: `^${escapeRegex(e)}$`, $options: 'i' } });
      or.push({ borrowerEmail: { $regex: escapeRegex(e), $options: 'i' } });
    }

    if (name && name.trim()) {
      const n = name.trim();
      // search fullName with words in any order (simple approach)
      or.push({ fullName: { $regex: escapeRegex(n), $options: 'i' } });
      // break into tokens and search any token
      const tokens = n.split(/\s+/).filter(Boolean);
      if (tokens.length) {
        or.push({ fullName: { $regex: tokens.join('|'), $options: 'i' } });
      }
    }

    const filter = or.length ? { $or: or } : {};

    const loans = await Loan.find(filter).limit(qLimit).lean().exec();

    return res.json(loans);
  } catch (err) {
    console.error('GET /loans error', err);
    return res.status(500).json({ error: 'Internal Server Error' });
  }
});

module.exports = router;
