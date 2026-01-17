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
    // If some middleware already set req.user, accept it
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

  // +260XXXXXXXXX / 260XXXXXXXXX -> 0XXXXXXXXX
  if (d.startsWith("260") && d.length >= 12) {
    const local9 = d.slice(3);
    return "0" + local9;
  }

  // 9 digits (97xxxxxxx) -> 097xxxxxxx
  if (d.length === 9) return "0" + d;

  // already 10 digits starting with 0
  if (d.length === 10 && d.startsWith("0")) return d;

  return d;
}

function phoneVariants(phone) {
  const p09 = normalizeZMPhone(phone);
  if (!p09) return [];

  const local9 = p09.startsWith("0") ? p09.slice(1) : p09;
  const variants = new Set();

  variants.add(p09); // 09XXXXXXXX
  variants.add(local9); // 9XXXXXXXX
  variants.add("260" + local9); // 2609XXXXXXXX

  return Array.from(variants);
}

// Your DB example uses clientKey: "phone:0978559684"
function clientKeyVariants(phone) {
  const p09 = normalizeZMPhone(phone);
  if (!p09) return [];

  const local9 = p09.startsWith("0") ? p09.slice(1) : p09;

  const variants = new Set();
  variants.add(`phone:${p09}`); // phone:097xxxxxxx (matches your DB)
  variants.add(`phone:${local9}`); // phone:97xxxxxxx (just in case)
  variants.add(`phone:260${local9}`); // phone:26097... (just in case)

  return Array.from(variants);
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

// robust number reader (handles strings + mongo numeric wrappers)
function toNumber(v) {
  if (v == null) return 0;
  if (typeof v === "number") return v;

  if (typeof v === "string") {
    const cleaned = v.replace(/,/g, "").trim();
    const n = Number(cleaned);
    return Number.isFinite(n) ? n : 0;
  }

  // Mongo export shapes: { $numberInt: "100" }, { $numberDecimal: "100.50" }
  if (typeof v === "object") {
    for (const k of Object.keys(v)) {
      const lk = String(k).toLowerCase();
      if (lk.includes("number")) return toNumber(v[k]);
    }
    if (v.amount != null) return toNumber(v.amount);
  }

  return 0;
}

// ---------- “Actual balance” rule (one figure) ----------
function loanActualBalance(loan) {
  const status = String(loan.loanStatus || "").toLowerCase().trim();
  if (status === "fully paid" || status === "write-off") return 0;

  const a = toNumber(loan.amortizationDue);
  const i = toNumber(loan.totalInterestBalance);
  const p = toNumber(loan.penaltyAmount);

  const total = a + i + p;
  return total > 0 ? total : 0;
}

function pickNearestNextDueDate(loans) {
  const now = new Date();
  const startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());

  const dates = loans
    .map((l) => (l.nextDueDate ? new Date(l.nextDueDate) : null))
    .filter((d) => d && !isNaN(d.getTime()))
    .filter((d) => d >= startToday)
    .sort((a, b) => a - b);

  return dates.length ? dates[0] : null;
}

function sameDay(a, b) {
  return (
    a &&
    b &&
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

// ----------------------------------------------------
// Router
// ----------------------------------------------------
const router = express.Router();

/**
 * ✅ GET /api/clients
 * Admin list clients (manual edit screen)
 * Optional query: ?q=search&limit=500
 */
router.get("/", requireAuth, requireAdmin, async (req, res) => {
  try {
    const q = String(req.query.q || "").trim();
    const limit = Math.min(parseInt(req.query.limit || "500", 10) || 500, 2000);

    const filter = {};
    if (q) {
      const safe = q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const rx = new RegExp(safe, "i");
      filter.$or = [{ fullName: rx }, { email: rx }, { phone: rx }, { clientKey: rx }];
    }

    const clients = await Client.find(filter)
      .select("_id clientKey fullName email phone balance statementDate updatedAt lastImportedAt loanStatus statusBucket isExtended")
      .sort({ updatedAt: -1, statementDate: -1, lastImportedAt: -1 })
      .limit(limit)
      .lean();

    return res.json({ success: true, clients });
  } catch (err) {
    console.error("GET /api/clients error:", err);
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

    // "Actual balance" stored as `balance`
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
 * Admin delete client (Clients collection)
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

/**
 * GET /api/clients/me
 * Optional query: ?includeLoans=true
 *
 * Returns:
 *  - client: {... balance, nextDueDate ...}
 *  - loansSummary: totals (borrowed, due, nextDueAmount, loanCount)
 *  - loans: optional list
 */
router.get("/me", requireAuth, async (req, res) => {
  try {
    const emailFromToken = String(req.user?.email || req.user?.sub || "").toLowerCase().trim();
    if (!emailFromToken) return res.status(401).json({ success: false, message: "Unauthorized" });

    // confirm user exists in Users collection (optional but good)
    const User = getUserModelSafe();
    const user = await User.findOne({ email: emailFromToken }).lean();
    if (!user) return res.status(401).json({ success: false, message: "Unauthorized" });

    const userEmail = String(user.email || emailFromToken).toLowerCase().trim();
    const userPhone09 = normalizeZMPhone(user.phone || "");
    const variants = phoneVariants(userPhone09);
    const keyVariants = clientKeyVariants(userPhone09);

    // -------------------------
    // 1) Find Client (email/phone/clientKey)
    // -------------------------
    const ors = [];
    if (userEmail) ors.push({ email: userEmail });
    if (variants.length) ors.push({ phone: { $in: variants } });
    if (keyVariants.length) ors.push({ clientKey: { $in: keyVariants } });

    let client = null;
    if (ors.length) {
      client = await Client.findOne({ $or: ors })
        .sort({ statementDate: -1, updatedAt: -1, lastImportedAt: -1 })
        .lean();
    }

    // -------------------------
    // 2) Loans source:
    //    - If client has embedded loans array -> use it
    //    - Else -> fetch from Loan collection
    // -------------------------
    const embeddedLoans = Array.isArray(client?.loans) ? client.loans : null;

    let loans = [];
    if (embeddedLoans && embeddedLoans.length) {
      loans = embeddedLoans;
    } else {
      const loanOrs = [];
      if (userEmail) loanOrs.push({ borrowerEmail: userEmail });
      if (variants.length) loanOrs.push({ borrowerMobile: { $in: variants } });

      loans = loanOrs.length
        ? await Loan.find({ $or: loanOrs })
            .select(
              "fullName borrowerMobile borrowerEmail borrowerAddress branchId " +
                "loanStatus principalAmount amortizationDue totalInterestBalance penaltyAmount " +
                "nextDueDate importedAt"
            )
            .lean()
        : [];
    }

    // If nothing found at all
    if (!client && loans.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Client not found. Ensure your account phone/email matches imported client data.",
        debug: { email: userEmail, phone: userPhone09, clientKeysTried: keyVariants },
      });
    }

    // -------------------------
    // 3) Compute totals from loans (single source of truth)
    // -------------------------
    const totalBorrowed = loans.reduce((s, l) => s + toNumber(l.principalAmount), 0);

    const unpaidLoans = loans.filter((l) => loanActualBalance(l) > 0);
    const totalBalance = unpaidLoans.reduce((s, l) => s + loanActualBalance(l), 0);

    const nextDueDate = pickNearestNextDueDate(unpaidLoans);

    let nextDueAmount = 0;
    if (nextDueDate) {
      for (const l of unpaidLoans) {
        const d = l.nextDueDate ? new Date(l.nextDueDate) : null;
        if (d && sameDay(d, nextDueDate)) {
          nextDueAmount += toNumber(l.amortizationDue);
        }
      }
    }

    // -------------------------
    // 4) If client missing but loans exist: optional upsert summary Client
    // -------------------------
    if (!client && loans.length) {
      const nameGuess = cleanFullName(loans[0].fullName || user.name || "Client");
      const phoneGuess = userPhone09 || normalizeZMPhone(loans[0].borrowerMobile || "");
      const emailGuess = userEmail || (loans[0].borrowerEmail || "").toLowerCase();

      // match your DB pattern: phone:097xxxxxxx
      const clientKey = phoneGuess ? `phone:${phoneGuess}` : `email:${emailGuess}`;

      const now = new Date();
      client = await Client.findOneAndUpdate(
        { clientKey },
        {
          $set: {
            clientKey,
            fullName: nameGuess,
            phone: phoneGuess || null,
            email: emailGuess || null,
            address: loans[0].borrowerAddress || user.address || null,
            loanStatus: totalBalance > 0 ? "Unknown" : "Fully Paid",
            statusBucket: totalBalance > 0 ? "balance" : "cleared",
            isExtended: false,
            balance: totalBalance,
            statementDate: now,
            lastImportedAt: now,
          },
        },
        { new: true, upsert: true, setDefaultsOnInsert: true }
      ).lean();
    }

    // -------------------------
    // 5) Build response payload
    // -------------------------
    const payload = {
      ...(client || {}),
      fullName: cleanFullName((client?.fullName || user.name || "").trim()),
      phone: userPhone09 || client?.phone || null,
      email: userEmail || client?.email || null,

      // important fields
      balance: totalBalance,
      nextDueDate: nextDueDate ? nextDueDate.toISOString() : null,
    };

    const includeLoans = String(req.query.includeLoans || "").toLowerCase() === "true";

    const response = {
      success: true,
      client: payload,
      loansSummary: {
        loanCount: loans.length,
        totalBorrowed,
        totalBalance,
        nextDueDate: nextDueDate ? nextDueDate.toISOString() : null,
        nextDueAmount,
      },
    };

    if (includeLoans) response.loans = loans;

    return res.json(response);
  } catch (err) {
    console.error("GET /api/clients/me error:", err);
    return res.status(500).json({ success: false, message: "Server error", error: err.message });
  }
});

module.exports = router;
