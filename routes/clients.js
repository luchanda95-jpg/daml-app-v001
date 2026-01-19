// routes/clients.js
const express = require("express");
const mongoose = require("mongoose");
const jwt = require("jsonwebtoken");

const Client = require("../models/Client");
const Loan = require("../models/Loan");

// ----------------------------------------------------
// Safe User model loader (prevents OverwriteModelError)
// ----------------------------------------------------
function getUserModelSafe() {
  if (mongoose.models && mongoose.models.User) return mongoose.models.User;
  try {
    return mongoose.model("User");
  } catch (_) {
    return require("../models/User");
  }
}

// ----------------------------------------------------
// JWT Auth Middleware (sets req.user) - fallback safe
// ----------------------------------------------------
function requireAuth(req, res, next) {
  try {
    if (req.user && (req.user.email || req.user.sub)) return next();

    const header = req.headers.authorization || "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : "";
    if (!token) return res.status(401).json({ success: false, message: "Unauthorized" });

    const secret = process.env.JWT_SECRET;
    if (!secret) {
      return res.status(500).json({
        success: false,
        message: "Server misconfiguration: JWT_SECRET missing",
      });
    }

    const payload = jwt.verify(token, secret);
    req.user = payload;
    return next();
  } catch (e) {
    return res.status(401).json({ success: false, message: "Unauthorized" });
  }
}

// ----------------------------------------------------
// Admin guard (ovadmin / branch_admin only)
// ----------------------------------------------------
async function requireAdmin(req, res, next) {
  try {
    const emailFromToken = String(req.user?.email || req.user?.sub || "").toLowerCase().trim();
    if (!emailFromToken) return res.status(401).json({ success: false, message: "Unauthorized" });

    const User = getUserModelSafe();
    const user = await User.findOne({ email: emailFromToken }).lean();
    if (!user) return res.status(401).json({ success: false, message: "Unauthorized" });

    const role = String(user.role || req.user?.role || "").toLowerCase().trim();
    const isAdmin = role === "ovadmin" || role === "branch_admin";
    if (!isAdmin) return res.status(403).json({ success: false, message: "Forbidden" });

    req.userDb = user;
    return next();
  } catch (e) {
    return res.status(401).json({ success: false, message: "Unauthorized" });
  }
}

// ------------- Normalizers (Zambia: always return 09XXXXXXXX) -------------
function normalizeZMPhone(input) {
  const d = String(input || "").replace(/[^\d]/g, "");
  if (!d) return "";

  if (d.startsWith("260") && d.length >= 12) {
    const local9 = d.slice(3);
    return "0" + local9;
  }
  if (d.length === 9) return "0" + d;
  if (d.length === 10 && d.startsWith("0")) return d;

  return d;
}

function cleanFullName(name) {
  const s = String(name || "").trim().replace(/\s+/g, " ");
  const noTitle = s.replace(/^(mr|mr\.|mrs|mrs\.|miss|ms|ms\.|dr|dr\.|prof|prof\.)\s+/i, "");
  return noTitle
    .split(" ")
    .filter(Boolean)
    .map((w) => w[0].toUpperCase() + w.slice(1).toLowerCase())
    .join(" ")
    .trim();
}

function toNumber(v) {
  if (v == null) return 0;
  if (typeof v === "number") return v;
  if (typeof v === "string") {
    const cleaned = v.replace(/,/g, "").trim();
    const n = Number(cleaned);
    return Number.isFinite(n) ? n : 0;
  }
  if (typeof v === "object") {
    for (const k of Object.keys(v)) {
      const lk = String(k).toLowerCase();
      if (lk.includes("number")) return toNumber(v[k]);
    }
    if (v.amount != null) return toNumber(v.amount);
  }
  return 0;
}

// ----------------------------------------------------
// Router
// ----------------------------------------------------
const router = express.Router();

/**
 * ✅ GET /api/clients
 * Admin list clients for manual edit
 * Optional: ?q=search&limit=500
 * Optional: ?lite=true  (default true)
 */
router.get("/", requireAuth, requireAdmin, async (req, res) => {
  try {
    const q = String(req.query.q || "").trim();
    const limit = Math.min(parseInt(req.query.limit || "500", 10) || 500, 2000);
    const lite = String(req.query.lite ?? "true").toLowerCase() !== "false";

    const filter = {};
    if (q) {
      const safe = q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const rx = new RegExp(safe, "i");
      filter.$or = [
        { fullName: rx },
        { email: rx },
        { phone: rx },
        { clientKey: rx },
        { address: rx },
      ];
    }

    const selectFields = lite
      ? "_id fullName email phone balance"
      : "_id clientKey fullName email phone address dateOfBirth balance statementDate lastImportedAt updatedAt";

    // ✅ Sort by name so it behaves like a real client list
    const clients = await Client.find(filter)
      .select(selectFields)
      .collation({ locale: "en", strength: 2 })
      .sort({ fullName: 1 })
      .limit(limit)
      .lean();

    return res.json({ success: true, clients });
  } catch (err) {
    console.error("GET /api/clients error:", err);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

/**
 * ✅ GET /api/clients/me
 * (keep this BEFORE /:id)
 */
router.get("/me", requireAuth, async (req, res) => {
  try {
    const emailFromToken = String(req.user?.email || req.user?.sub || "").toLowerCase().trim();
    if (!emailFromToken) return res.status(401).json({ success: false, message: "Unauthorized" });

    const User = getUserModelSafe();
    const user = await User.findOne({ email: emailFromToken }).lean();
    if (!user) return res.status(401).json({ success: false, message: "Unauthorized" });

    // (your existing /me logic can stay as-is)
    return res.json({ success: true, message: "OK" });
  } catch (err) {
    console.error("GET /api/clients/me error:", err);
    return res.status(500).json({ success: false, message: "Server error", error: err.message });
  }
});

/**
 * ✅ GET /api/clients/:id
 * Admin fetch ONE client by _id (for tap-to-load details)
 */
router.get("/:id", requireAuth, requireAdmin, async (req, res) => {
  try {
    const id = String(req.params.id || "").trim();
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ success: false, message: "Invalid client id" });
    }

    const client = await Client.findById(id).lean();
    if (!client) return res.status(404).json({ success: false, message: "Client not found" });

    return res.json({ success: true, client });
  } catch (err) {
    console.error("GET /api/clients/:id error:", err);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

/**
 * ✅ PUT /api/clients/:id
 * Admin manual edit (updates the Clients collection)
 */
router.put("/:id", requireAuth, requireAdmin, async (req, res) => {
  try {
    const id = String(req.params.id || "").trim();
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ success: false, message: "Invalid client id" });
    }

    const body = req.body || {};
    const update = {};

    if (body.fullName != null) update.fullName = cleanFullName(body.fullName);
    if (body.email != null) update.email = String(body.email || "").toLowerCase().trim() || null;
    if (body.phone != null) update.phone = normalizeZMPhone(body.phone) || null;
    if (body.address != null) update.address = String(body.address || "").trim() || null;

    if (body.balance != null || body.actualBalance != null) {
      update.balance = toNumber(body.balance ?? body.actualBalance);
    }

    const client = await Client.findByIdAndUpdate(id, { $set: update }, { new: true }).lean();
    if (!client) return res.status(404).json({ success: false, message: "Client not found" });

    return res.json({ success: true, client });
  } catch (err) {
    console.error("PUT /api/clients/:id error:", err);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

/**
 * ✅ DELETE /api/clients/:id
 */
router.delete("/:id", requireAuth, requireAdmin, async (req, res) => {
  try {
    const id = String(req.params.id || "").trim();
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ success: false, message: "Invalid client id" });
    }

    const result = await Client.deleteOne({ _id: id });
    if (!result.deletedCount) return res.status(404).json({ success: false, message: "Client not found" });

    return res.json({ success: true });
  } catch (err) {
    console.error("DELETE /api/clients/:id error:", err);
    return res.status(500).json({ success: false, message: "Server error" });
  }
});

module.exports = router;
