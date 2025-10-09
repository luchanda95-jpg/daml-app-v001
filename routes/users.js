// routes/users.js
const express = require('express');
const User = require('../models/User');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();

// Helper: check owner or admin
function _isOwnerOrAdmin(req, targetEmail) {
  const requester = (req.user && req.user.email) ? String(req.user.email).toLowerCase().trim() : '';
  const role = (req.user && req.user.role) ? String(req.user.role) : '';
  const target = String(targetEmail || '').toLowerCase().trim();
  if (!requester) return false;
  if (requester === target) return true;
  return ['ovadmin','branch_admin'].includes(role);
}

// -----------------------------
// List all users (admin only)
// GET /api/users
// -----------------------------
router.get('/', authMiddleware, async (req, res) => {
  try {
    if (!['ovadmin','branch_admin'].includes(req.user.role)) return res.status(403).json({ message: 'Forbidden' });
    const users = await User.find({}, { passwordHash: 0 }).sort({ name: 1, email: 1 }).lean();
    return res.json(users);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: 'Server error' });
  }
});

// -----------------------------
// Profile endpoints
// GET /api/users/:email/profile
// PUT /api/users/:email/profile
// -----------------------------
router.get('/:email/profile', authMiddleware, async (req, res) => {
  try {
    const email = (req.params.email || '').toLowerCase().trim();
    if (!_isOwnerOrAdmin(req, email)) return res.status(403).json({ message: 'Forbidden' });
    const user = await User.findOne({ email }, { passwordHash: 0 }).lean();
    if (!user) return res.status(404).json({ message: 'User not found' });
    return res.json({
      email: user.email,
      name: user.name || '',
      phone: user.phone || '',
      role: user.role || 'client',
      balances: user.balances || {},
      notificationsCount: user.notifications?.length || 0
    });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: 'Server error' });
  }
});

router.put('/:email/profile', authMiddleware, async (req, res) => {
  try {
    const email = (req.params.email || '').toLowerCase().trim();
    if (!_isOwnerOrAdmin(req, email)) return res.status(403).json({ message: 'Forbidden' });
    const { name, phone, role } = req.body;
    const updates = {};
    if (name) updates.name = name;
    if (phone) updates.phone = phone;
    // Only ovadmin can change roles
    if (role && req.user.role === 'ovadmin') updates.role = role;

    const updated = await User.findOneAndUpdate({ email }, { $set: updates, updatedAt: new Date() }, { new: true, fields: { passwordHash: 0 } });
    if (!updated) return res.status(404).json({ message: 'User not found' });
    return res.json({ message: 'Profile updated', profile: updated });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: 'Server error' });
  }
});

// -----------------------------
// Balances endpoints
// GET /api/users/:email/balances
// POST /api/users/:email/balances
// -----------------------------
router.get('/:email/balances', authMiddleware, async (req, res) => {
  try {
    const email = (req.params.email || '').toLowerCase().trim();
    if (!_isOwnerOrAdmin(req, email)) return res.status(403).json({ message: 'Forbidden' });
    const user = await User.findOne({ email });
    if (!user) return res.status(404).json({ message: 'User not found' });
    return res.json(user.balances || {});
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: 'Server error' });
  }
});

router.post('/:email/balances', authMiddleware, async (req, res) => {
  try {
    const email = (req.params.email || '').toLowerCase().trim();
    if (!_isOwnerOrAdmin(req, email)) return res.status(403).json({ message: 'Forbidden' });
    const payload = req.body;
    const user = await User.findOne({ email });
    if (!user) return res.status(404).json({ message: 'User not found' });

    user.balances = user.balances || {};
    user.balances.amountBorrowed = payload.amountBorrowed ?? payload.amount_borrowed ?? user.balances.amountBorrowed ?? 0;
    user.balances.amountPaid = payload.amountPaid ?? payload.amount_paid ?? user.balances.amountPaid ?? 0;
    user.balances.actualBalance = payload.actualBalance ?? payload.actual_balance ?? user.balances.actualBalance ?? 0;
    user.balances.interestRate = payload.interestRate ?? payload.interest_rate ?? user.balances.interestRate ?? 0;

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

// -----------------------------
// Notifications endpoints
// GET /api/users/:email/notifications
// POST /api/users/:email/notifications
// -----------------------------
router.get('/:email/notifications', authMiddleware, async (req, res) => {
  try {
    const email = (req.params.email || '').toLowerCase().trim();
    if (!_isOwnerOrAdmin(req, email)) return res.status(403).json({ message: 'Forbidden' });
    const user = await User.findOne({ email });
    if (!user) return res.status(404).json({ message: 'User not found' });
    return res.json(user.notifications || []);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: 'Server error' });
  }
});

router.post('/:email/notifications', authMiddleware, async (req, res) => {
  try {
    const email = (req.params.email || '').toLowerCase().trim();
    if (!_isOwnerOrAdmin(req, email)) return res.status(403).json({ message: 'Forbidden' });
    const { title, message, type } = req.body;
    const user = await User.findOne({ email });
    if (!user) return res.status(404).json({ message: 'User not found' });

    const n = { title, message, type: type || 'info', ts: new Date() };
    user.notifications = user.notifications || [];
    user.notifications.unshift(n);
    if (user.notifications.length > 100) user.notifications = user.notifications.slice(0, 100);
    await user.save();
    return res.status(201).json(n);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;
