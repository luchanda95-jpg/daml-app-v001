// middleware/auth.js
const jwt = require('jsonwebtoken');
const User = require('../models/User');
const JWT_SECRET = process.env.JWT_SECRET;

function generateToken(payload) {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: process.env.JWT_EXPIRES_IN || '7d' });
}

async function authMiddleware(req, res, next) {
  const auth = req.get('Authorization') || '';
  if (!auth || !auth.startsWith('Bearer ')) return res.status(401).json({ message: 'Missing token' });
  const token = auth.split(' ')[1];
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    // optionally load user to get latest role
    const user = await User.findOne({ email: (decoded.email || decoded.sub)?.toLowerCase() });
    req.user = user ? { email: user.email, role: user.role } : decoded;
    next();
  } catch (err) {
    return res.status(401).json({ message: 'Invalid token' });
  }
}

function requireRole(...roles) {
  return function (req, res, next) {
    const role = req.user?.role;
    if (!role || !roles.includes(role)) return res.status(403).json({ message: 'Forbidden' });
    next();
  };
}

module.exports = { authMiddleware, requireRole, generateToken };
