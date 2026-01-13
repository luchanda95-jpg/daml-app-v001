// routes/clients.js
const express = require("express");
const mongoose = require("mongoose");
const Client = require("../models/Client");
const Loan = require("../models/Loan");

function getUserModelSafe() {
  if (mongoose.models && mongoose.models.User) return mongoose.models.User;
  try {
    return mongoose.model("User");
  } catch (_) {
    return require("../models/User");
  }
}

// ------------- Normalizers (Zambia: always return 09XXXXXXXX) -------------
function normalizeZMPhone(input) {
  const d = String(input || "").replace(/[^\d]/g, "");
  if (!d) return "";

  // +260XXXXXXXXX / 260XXXXXXXXX -> 0XXXXXXXXX
  if (d.startsWith("260") && d.length >= 12) {
    const local9 = d.slice(3); // 9 digits
    return "0" + local9;
  }

  // 9 digits (97xxxxxxx) -> 097xxxxxxx
  if (d.length === 9) return "0" + d;

  // already 10 digits starting with 0
  if (d.length === 10 && d.startsWith("0")) return d;

  return d; // fallback
}

function phoneVariants(phone) {
  const p09 = normalizeZMPhone(phone);
  if (!p09) return [];

  const local9 = p09.startsWith("0") ? p09.slice(1) : p09;
  const variants = new Set();

  variants.add(p09);           // 09XXXXXXXX
  variants.add(local9);        // 9XXXXXXXX
  variants.add("260" + local9); // 2609XXXXXXXX

  return Array.from(variants);
}

function cleanFullName(name) {
  const s = String(name || "").trim().replace(/\s+/g, " ");
  const noTitle = s.replace(/^(mr|mr\.|mrs|mrs\.|miss|ms|ms\.|dr|dr\.|prof|prof\.)\s+/i, "");
  return noTitle
    .split(" ")
    .filter(Boolean)
    .map(w => w[0].toUpperCase() + w.slice(1).toLowerCase())
    .join(" ")
    .trim();
}

// ---------- “Actual balance” rule (one figure) ----------
function loanActualBalance(loan) {
  const status = String(loan.loanStatus || "").toLowerCase().trim();
  if (status === "fully paid" || status === "write-off") return 0;

  const a = Number(loan.amortizationDue || 0);
  const i = Number(loan.totalInterestBalance || 0);
  const p = Number(loan.penaltyAmount || 0);

  const total = a + i + p;
  return total > 0 ? total : 0;
}

function pickNearestNextDueDate(loans) {
  const now = new Date();
  const dates = loans
    .map(l => (l.nextDueDate ? new Date(l.nextDueDate) : null))
    .filter(d => d && !isNaN(d.getTime()))
    // only future or today (optional)
    .filter(d => d >= new Date(now.getFullYear(), now.getMonth(), now.getDate()))
    .sort((a, b) => a - b);

  return dates.length ? dates[0] : null;
}

const router = express.Router();

// GET /api/clients/me
router.get("/me", async (req, res) => {
  try {
    const emailFromToken = (req.user?.email || "").toLowerCase().trim();
    if (!emailFromToken) return res.status(401).json({ success: false, message: "Unauthorized" });

    const User = getUserModelSafe();
    const user = await User.findOne({ email: emailFromToken }).lean();
    if (!user) return res.status(401).json({ success: false, message: "Unauthorized" });

    const userEmail = String(user.email || emailFromToken).toLowerCase().trim();
    const userPhone09 = normalizeZMPhone(user.phone || "");
    const variants = phoneVariants(userPhone09);

    // 1) Try find Client by email/phone
    const ors = [];
    if (userEmail) ors.push({ email: userEmail });
    if (variants.length) ors.push({ phone: { $in: variants } });

    let client = null;
    if (ors.length) {
      client = await Client.findOne({ $or: ors })
        .sort({ statementDate: -1, updatedAt: -1 })
        .lean();
    }

    // 2) Always compute “Actual Balance + Next Due” from loans (single source of truth)
    const loanOrs = [];
    if (userEmail) loanOrs.push({ borrowerEmail: userEmail });
    if (variants.length) loanOrs.push({ borrowerMobile: { $in: variants } });

    const loans = loanOrs.length
      ? await Loan.find({ $or: loanOrs })
          .select("fullName borrowerMobile borrowerEmail loanStatus amortizationDue totalInterestBalance penaltyAmount nextDueDate")
          .lean()
      : [];

    if (!client && loans.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Client not found. Ensure your account phone/email matches imported client data.",
        debug: { email: userEmail, phone: userPhone09 },
      });
    }

    // compute totals (your “one figure” rule)
    const balances = loans.map(loanActualBalance);
    const totalBalance = balances.reduce((s, x) => s + x, 0);
    const unpaidLoans = loans.filter(l => loanActualBalance(l) > 0);
    const nextDueDate = pickNearestNextDueDate(unpaidLoans);

    // if client missing but loans exist, create an auto-summary client (optional but helpful)
    if (!client && loans.length) {
      const nameGuess = cleanFullName(loans[0].fullName || user.name || "Client");
      const phoneGuess = userPhone09 || normalizeZMPhone(loans[0].borrowerMobile || "");
      const local9 = phoneGuess.startsWith("0") ? phoneGuess.slice(1) : phoneGuess;
      const clientKey = local9 ? `phone:${local9}` : `email:${userEmail}`;

      const now = new Date();
      const upsert = await Client.findOneAndUpdate(
        { clientKey },
        {
          $set: {
            clientKey,
            fullName: nameGuess,
            phone: phoneGuess || null,
            email: userEmail || null,
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

      client = upsert;
    }

    // attach computed fields (don’t care about restructured etc)
    const payload = {
      ...(client || {}),
      fullName: cleanFullName((client?.fullName || user.name || "").trim()),
      phone: userPhone09 || client?.phone || null,
      email: userEmail || client?.email || null,

      // ⭐ The ONLY two things your UI should show
      balance: totalBalance,           // “actual balance”
      nextDueDate: nextDueDate ? nextDueDate.toISOString() : null,
    };

    return res.json({
      success: true,
      client: payload,
      loanCount: loans.length,
    });
  } catch (err) {
    console.error("GET /api/clients/me error:", err);
    return res.status(500).json({ success: false, message: "Server error", error: err.message });
  }
});

module.exports = router;
