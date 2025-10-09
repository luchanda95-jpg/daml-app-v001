// routes/users.js
const express = require('express');
const User = require('../models/User');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();

// GET balances for user
router.get('/:email/balances', authMiddleware, async (req, res) => {
  try {
    const email = (req.params.email || '').toLowerCase().trim();
    // allow if requester is same user OR is admin
    if (req.user.email !== email && !['ovadmin','branch_admin'].includes(req.user.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    const user = await User.findOne({ email });
    if (!user) return res.status(404).json({ message: 'User not found' });
    return res.json(user.balances || {});
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: 'Server error' });
  }
});

// POST / set balances for user
router.post('/:email/balances', authMiddleware, async (req, res) => {
  try {
    const email = (req.params.email || '').toLowerCase().trim();
    // allow if requester is same user OR is admin
    if (req.user.email !== email && !['ovadmin','branch_admin'].includes(req.user.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    const payload = req.body;
    const user = await User.findOne({ email });
    if (!user) {
      // optionally create user stub
      return res.status(404).json({ message: 'User not found' });
    }
    // update balances fields explicitly
    user.balances.amountBorrowed = payload.amountBorrowed ?? payload.amount_borrowed ?? user.balances.amountBorrowed;
    user.balances.amountPaid = payload.amountPaid ?? payload.amount_paid ?? user.balances.amountPaid;
    user.balances.actualBalance = payload.actualBalance ?? payload.actual_balance ?? user.balances.actualBalance;
    user.balances.interestRate = payload.interestRate ?? payload.interest_rate ?? user.balances.interestRate;

    const np = payload.next_payment ?? payload.nextPayment;
    if (np && typeof np === 'object') {
      user.balances.next_payment = {
        amount: np.amount ?? np.amount_due ?? user.balances.next_payment?.amount ?? 0,
        date: np.date ? new Date(np.date) : user.balances.next_payment?.date ?? null
      };
    }

    await user.save();
    return res.status(200).json(user.balances);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: 'Server error' });
  }
});

// GET notifications
router.get('/:email/notifications', authMiddleware, async (req, res) => {
  try {
    const email = (req.params.email || '').toLowerCase().trim();
    if (req.user.email !== email && !['ovadmin','branch_admin'].includes(req.user.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    const user = await User.findOne({ email });
    if (!user) return res.status(404).json({ message: 'User not found' });
    return res.json(user.notifications || []);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: 'Server error' });
  }
});

// POST add notification
router.post('/:email/notifications', authMiddleware, async (req, res) => {
  try {
    const email = (req.params.email || '').toLowerCase().trim();
    // allow only admins OR the server itself to add (we allow owner as well)
    if (req.user.email !== email && !['ovadmin','branch_admin'].includes(req.user.role)) {
      // depending on business rules, you may allow other roles or server-to-server writes with an API key
      return res.status(403).json({ message: 'Forbidden' });
    }
    const { title, message, type } = req.body;
    const user = await User.findOne({ email });
    if (!user) return res.status(404).json({ message: 'User not found' });
    const n = { title, message, type: type || 'info', ts: new Date() };
    user.notifications.unshift(n);
    // keep notifications list trimmed if desired
    if (user.notifications.length > 100) user.notifications = user.notifications.slice(0, 100);
    await user.save();
    return res.status(201).json(n);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;
