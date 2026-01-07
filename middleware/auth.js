// middleware/auth.js
const jwt = require("jsonwebtoken");
const mongoose = require("mongoose");

const JWT_SECRET = process.env.JWT_SECRET || "changeme";
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || "7d";

function generateToken(payload) {
  // Always sign a consistent payload
  return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
}

function getUserModelSafe() {
  // ✅ Avoid OverwriteModelError by using already-compiled model if available
  if (mongoose.models && mongoose.models.User) return mongoose.models.User;

  try {
    return mongoose.model("User");
  } catch (_) {
    // fallback: load model file if not registered yet
    return require("../models/User");
  }
}

async function authMiddleware(req, res, next) {
  const auth = req.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) {
    return res.status(401).json({ message: "Missing token" });
  }

  const token = auth.slice(7).trim();
  if (!token) return res.status(401).json({ message: "Missing token" });

  try {
    const decoded = jwt.verify(token, JWT_SECRET);

    // Support both { email } and { sub }
    const rawEmail = (decoded.email || decoded.sub || "").toString().toLowerCase().trim();

    // If token is valid but doesn't include an email, still allow downstream checks
    if (!rawEmail) {
      req.user = decoded;
      return next();
    }

    // ✅ Safe User model retrieval (prevents overwrite errors)
    const User = getUserModelSafe();

    // Load user from DB (optional, but best)
    const user = await User.findOne({ email: rawEmail }).lean();

    // ✅ Merge decoded + db data (don't discard token fields)
    req.user = user
      ? {
          ...decoded,
          email: user.email,
          role: user.role,
          name: user.name || decoded.name || "",
          phone: user.phone || decoded.phone || "",
          id: user._id?.toString(),
        }
      : {
          ...decoded,
          email: rawEmail,
        };

    return next();
  } catch (err) {
    return res.status(401).json({ message: "Invalid token" });
  }
}

function requireRole(...roles) {
  return function (req, res, next) {
    const role = req.user?.role;
    if (!role || !roles.includes(role)) {
      return res.status(403).json({ message: "Forbidden" });
    }
    return next();
  };
}

module.exports = { authMiddleware, requireRole, generateToken };
