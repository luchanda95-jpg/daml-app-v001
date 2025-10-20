// middleware/auth.js
const jwt = require('jsonwebtoken');
const JWT_SECRET = process.env.JWT_SECRET || 'changeme';
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '7d';

function generateToken(payload) {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
}

async function authMiddleware(req, res, next) {
  const auth = req.get('Authorization') || '';
  if (!auth || !auth.startsWith('Bearer ')) return res.status(401).json({ message: 'Missing token' });
  const token = auth.split(' ')[1];
  try {
    const decoded = jwt.verify(token, JWT_SECRET);

    // Lazy require to reduce chance of circular require problems
    const User = require('../models/User');

    const user = await User.findOne({ email: (decoded.email || decoded.sub)?.toLowerCase() });
    req.user = user ? { email: user.email, role: user.role } : decoded;
    return next();
  } catch (err) {
    return res.status(401).json({ message: 'Invalid token' });
  }
}

function requireRole(...roles) {
  return function (req, res, next) {
    const role = req.user?.role;
    if (!role || !roles.includes(role)) return res.status(403).json({ message: 'Forbidden' });
    return next();
  };
}
console.log('[debug] loading middleware/auth.js');
module.exports = { authMiddleware, requireRole, generateToken };
