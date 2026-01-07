// routes/clients.js
const express = require("express");
const Client = require("../models/Client");
const User = require("../models/User"); // safe import here

function normalizePhone(p) {
  if (!p) return "";
  return String(p).replace(/[^\d]/g, "");
}

function phoneVariants(phone) {
  const p = normalizePhone(phone);
  if (!p) return [];
  const set = new Set([p]);

  // add with/without leading 0
  if (p.startsWith("0")) set.add(p.slice(1));
  else set.add("0" + p);

  // add with/without country code 260
  if (p.startsWith("260")) {
    const local = p.slice(3);
    set.add(local);
    if (!local.startsWith("0")) set.add("0" + local);
  } else {
    // if local 9/10 digits, add 260 variant
    if (p.length <= 10) set.add("260" + (p.startsWith("0") ? p.slice(1) : p));
  }

  return Array.from(set);
}

const router = express.Router();

// ✅ GET /api/clients/me
router.get("/me", async (req, res) => {
  try {
    // req.user set by authMiddleware
    const email = (req.user?.email || "").toLowerCase().trim();
    if (!email) return res.status(401).json({ message: "Unauthorized" });

    // Get full user so we can read phone + name
    const user = await User.findOne({ email }).lean();
    const userPhone = user?.phone || "";
    const userEmail = user?.email || email;

    const ors = [];
    if (userEmail) ors.push({ email: userEmail.toLowerCase().trim() });

    const variants = phoneVariants(userPhone);
    if (variants.length) ors.push({ phone: { $in: variants } });

    if (ors.length === 0) {
      return res.status(400).json({
        success: false,
        message: "Your account has no email/phone to match client records.",
      });
    }

    const client = await Client.findOne({ $or: ors })
      .sort({ statementDate: -1, updatedAt: -1 })
      .lean();

    if (!client) {
      return res.status(404).json({
        success: false,
        message: "Client not found. Ensure your account phone/email matches imported client data.",
        debug: { email: userEmail, phone: normalizePhone(userPhone) }, // remove in production if you want
      });
    }

    return res.json({ success: true, data: client });
  } catch (err) {
    console.error("GET /api/clients/me error:", err);
    return res.status(500).json({ success: false, message: "Server error", error: err.message });
  }
});

module.exports = router;
