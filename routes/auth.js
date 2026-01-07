// routes/auth.js
const express = require('express');
const bcrypt = require('bcrypt');
const User = require('../models/User');
const { generateToken } = require('../middleware/auth');

const router = express.Router();

function normalizePhone(p) {
  if (!p) return '';
  return String(p).replace(/[^\d]/g, ''); // digits only
}

// register
router.post('/register', async (req, res) => {
  try {
    const { name, email, phone, password } = req.body;
    if (!email || !password) return res.status(400).json({ message: 'email and password required' });

    const normalized = email.toLowerCase().trim();
    const existed = await User.findOne({ email: normalized });
    if (existed) return res.status(409).json({ message: 'Email already registered' });

    const reserved = [
      'directaccessmoney@gmail.com',
      'monze@directaccess.com',
      'mazabuka@directaccess.com',
      'lusaka@directaccess.com',
      'solwezi@directaccess.com',
      'lumezi@directaccess.com',
      'nakonde@directaccess.com'
    ];
    if (reserved.includes(normalized)) return res.status(403).json({ message: 'Reserved email' });

    const passwordHash = await bcrypt.hash(password, 12);

    // ✅ normalize phone here
    const cleanPhone = normalizePhone(phone);

    const user = new User({
      email: normalized,
      name: name || '',
      phone: cleanPhone,
      passwordHash,
      role: 'client'
    });

    await user.save();

    // Optional: include phone in token payload if you want
    const token = generateToken({ email: user.email, role: user.role, name: user.name, phone: user.phone });

    return res.status(201).json({ token, email: user.email, name: user.name, phone: user.phone, role: user.role });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: 'Server error' });
  }
});

// login
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    const normalized = (email || '').toLowerCase().trim();
    const user = await User.findOne({ email: normalized });

    const overallAdminEmail = 'directaccessmoney@gmail.com';
    const branchAdmins = ['monze@directaccess.com','mazabuka@directaccess.com','lusaka@directaccess.com','solwezi@directaccess.com','lumezi@directaccess.com','nakonde@directaccess.com'];

    if (!user && normalized === overallAdminEmail) {
      if (password === 'ovadmin') {
        const token = generateToken({ email: normalized, role: 'ovadmin', phone: '' });
        return res.json({ token, email: normalized, name: 'Overall Admin', phone: '', role: 'ovadmin' });
      }
    }
    if (!user && branchAdmins.includes(normalized)) {
      if (password === 'admin') {
        const token = generateToken({ email: normalized, role: 'branch_admin', phone: '' });
        return res.json({ token, email: normalized, name: 'Branch Admin', phone: '', role: 'branch_admin' });
      }
    }

    if (!user) return res.status(401).json({ message: 'Invalid credentials' });

    const ok = await bcrypt.compare(password, user.passwordHash);
    if (!ok) return res.status(401).json({ message: 'Invalid credentials' });

    // Optional: if you want to enforce normalization for existing users too:
    // if (user.phone) { user.phone = normalizePhone(user.phone); await user.save(); }

    const token = generateToken({ email: user.email, role: user.role, name: user.name, phone: user.phone });

    return res.json({ token, email: user.email, name: user.name, phone: user.phone, role: user.role });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;
  