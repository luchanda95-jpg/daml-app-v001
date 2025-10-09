// routes/auth.js
const express = require('express');
const bcrypt = require('bcrypt');
const User = require('../models/User');
const { generateToken } = require('../middleware/auth');

const router = express.Router();

// register
router.post('/register', async (req, res) => {
  try {
    const { name, email, phone, password } = req.body;
    if (!email || !password) return res.status(400).json({ message: 'email and password required' });

    const normalized = email.toLowerCase().trim();
    const existed = await User.findOne({ email: normalized });
    if (existed) return res.status(409).json({ message: 'Email already registered' });

    // Reserved admin emails protection
    const reserved = ['directaccessmoney@gmail.com', 'monze@directaccess.com', 'mazabuka@directaccess.com', 'lusaka@directaccess.com', 'solwezi@directaccess.com', 'lumezi@directaccess.com', 'nakonde@directaccess.com'];
    if (reserved.includes(normalized)) return res.status(403).json({ message: 'Reserved email' });

    const passwordHash = await bcrypt.hash(password, 12);
    const user = new User({ email: normalized, name: name || '', phone: phone || '', passwordHash, role: 'client' });
    await user.save();

    const token = generateToken({ email: user.email, role: user.role, name: user.name });
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

    // handle reserved admin shortcuts if you want dev-only passwords
    const overallAdminEmail = 'directaccessmoney@gmail.com';
    const branchAdmins = ['monze@directaccess.com','mazabuka@directaccess.com','lusaka@directaccess.com','solwezi@directaccess.com','lumezi@directaccess.com','nakonde@directaccess.com'];
    if (!user && normalized === overallAdminEmail) {
      // dev-only fallback
      if (password === 'ovadmin') {
        const token = generateToken({ email: normalized, role: 'ovadmin' });
        return res.json({ token, email: normalized, name: 'Overall Admin', phone: '', role: 'ovadmin' });
      }
    }
    if (!user && branchAdmins.includes(normalized)) {
      if (password === 'admin') {
        const token = generateToken({ email: normalized, role: 'branch_admin' });
        return res.json({ token, email: normalized, name: 'Branch Admin', phone: '', role: 'branch_admin' });
      }
    }

    if (!user) return res.status(401).json({ message: 'Invalid credentials' });

    const ok = await bcrypt.compare(password, user.passwordHash);
    if (!ok) return res.status(401).json({ message: 'Invalid credentials' });

    const token = generateToken({ email: user.email, role: user.role, name: user.name });
    return res.json({ token, email: user.email, name: user.name, phone: user.phone, role: user.role });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;
