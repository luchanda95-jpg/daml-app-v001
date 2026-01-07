// server.js
// ============================================================
// DAML Server (Express + MongoDB)
// - Auth (JWT) + Users
// - Admin submissions + notifications
// - Daily/Monthly reports + Zanaco allocations
// - Loans router + Imports router
// - Clients route: fetch client summary for logged-in user
// ============================================================

require("dotenv").config();

const express = require("express");
const mongoose = require("mongoose");
const cors = require("cors");
const helmet = require("helmet");
const compression = require("compression");
const rateLimit = require("express-rate-limit");
const morgan = require("morgan");
const bcrypt = require("bcrypt");

const { authMiddleware, requireRole, generateToken } = require("./middleware/auth");

// ============================================================
// 1) CONFIG
// ============================================================
const app = express();

const mongoUri = process.env.MONGO_URI;
const PORT = process.env.PORT || 5000;

const SALT_ROUNDS = Number(process.env.SALT_ROUNDS || 10);

const OVERALL_ADMIN_EMAIL = (process.env.OVERALL_ADMIN_EMAIL || "directaccessmoney@gmail.com")
  .toLowerCase()
  .trim();

if (!mongoUri) {
  console.error("❌ MongoDB connection URI is required (set MONGO_URI in .env)");
  process.exit(1);
}

// If behind a proxy (Render/Heroku/Nginx), helps rate-limit & IP
app.set("trust proxy", 1);

// ============================================================
// 2) GLOBAL MIDDLEWARES
// ============================================================
app.use(helmet());
app.use(compression());
app.use(express.json({ limit: "10mb" }));
app.use(express.urlencoded({ extended: true }));
app.use(morgan("combined"));

// CORS: permissive in dev, restrict in prod via env var
function parseCorsOrigins(v) {
  if (!v) return [];
  if (Array.isArray(v)) return v;
  const s = String(v).trim();
  if (!s) return [];
  // allow JSON array in env
  if (s.startsWith("[") && s.endsWith("]")) {
    try {
      const arr = JSON.parse(s);
      if (Array.isArray(arr)) return arr;
    } catch (_) {}
  }
  // comma-separated
  return s.split(",").map((x) => x.trim()).filter(Boolean);
}

const corsOptions = {
  origin: process.env.NODE_ENV === "production" ? parseCorsOrigins(process.env.CORS_ORIGIN) : true,
  methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization"],
  credentials: true,
};
app.use(cors(corsOptions));

// Rate limiter (basic)
const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
});
app.use(limiter);

// ============================================================
// 3) SAFE MODEL REGISTRATION HELPERS
// ============================================================
const { Schema } = mongoose;

function getOrCreateModel(name, schema) {
  if (mongoose.models && mongoose.models[name]) return mongoose.models[name];
  return mongoose.model(name, schema);
}

// Canonical User model (from /models/User.js)
// IMPORTANT: server.js should NOT redefine User schema again.
const User = require("./models/User");

// ============================================================
// 4) DATE NORMALIZERS + SANITIZERS (used in reports)
// ============================================================
function normalizeToUtcDay(dateInput) {
  const d = new Date(dateInput);
  if (isNaN(d.getTime())) return null;
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 0, 0, 0));
}

function normalizeToUtcMonthStart(dateInput) {
  const d = new Date(dateInput);
  if (isNaN(d.getTime())) return null;
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1, 0, 0, 0));
}

function sanitizeNumericMap(maybe) {
  if (!maybe || typeof maybe !== "object") return {};
  const out = {};
  for (const [k, v] of Object.entries(maybe)) {
    const num = typeof v === "number" ? v : v === null || v === "" ? 0 : Number(v);
    out[k] = Number.isNaN(num) ? 0 : num;
  }
  return out;
}

function sanitizeIntegerMap(maybe) {
  if (!maybe || typeof maybe !== "object") return {};
  const out = {};
  for (const [k, v] of Object.entries(maybe)) {
    if (typeof v === "number") out[k] = Math.trunc(v);
    else if (typeof v === "string") {
      const asInt = parseInt(v, 10);
      if (!Number.isNaN(asInt)) out[k] = asInt;
      else {
        const asFloat = parseFloat(v);
        out[k] = Number.isNaN(asFloat) ? 0 : Math.trunc(asFloat);
      }
    } else out[k] = 0;
  }
  return out;
}

function toNumber(v) {
  if (v == null) return 0;
  if (typeof v === "number") return v;
  if (typeof v === "string") {
    const n = Number(v);
    return Number.isNaN(n) ? 0 : n;
  }
  return 0;
}

function normalizePhone(p) {
  return String(p || "").replace(/[^\d]/g, "");
}

// ============================================================
// 5) REPORT MODELS (Daily / Monthly / Zanaco) + ADMIN MODELS
// ============================================================

// -------------------- AdminSubmission model ------------------
const AdminSubmissionSchema = new Schema(
  {
    from: { type: String, default: "unknown" },
    ts: { type: Date, default: () => new Date() },
    data: { type: Schema.Types.Mixed, default: {} },
  },
  { timestamps: true }
);
const AdminSubmission = getOrCreateModel("AdminSubmission", AdminSubmissionSchema);

// -------------------- BranchComment model --------------------
const BranchCommentSchema = new Schema({
  branchName: String,
  comments: [
    {
      author: String,
      comment: String,
      timestamp: Date,
    },
  ],
  updatedAt: { type: Date, default: Date.now },
});
const BranchComment = getOrCreateModel("BranchComment", BranchCommentSchema);

// -------------------- DailyReport model ----------------------
const DailyReportSchema = new Schema(
  {
    branch: { type: String, required: true, trim: true },
    date: { type: Date, required: true },
    openingBalances: { type: Map, of: Number, default: {} },
    loanCounts: { type: Map, of: Number, default: {} },
    closingBalances: { type: Map, of: Number, default: {} },
    totalDisbursed: { type: Number, default: 0 },
    totalCollected: { type: Number, default: 0 },
    collectedForOtherBranches: { type: Number, default: 0 },
    pettyCash: { type: Number, default: 0 },
    expenses: { type: Number, default: 0 },
    synced: { type: Boolean, default: false },
    updatedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);
DailyReportSchema.index({ branch: 1, date: 1 }, { unique: true });
const DailyReport = getOrCreateModel("DailyReport", DailyReportSchema);

// -------------------- ZanacoDistribution model ----------------
const ZanacoDistributionSchema = new Schema(
  {
    date: { type: Date, required: true, index: true },
    branch: { type: String, required: true, trim: true, index: true },
    channel: { type: String, required: true, trim: true, lowercase: true, index: true },
    amount: { type: Number, required: true, default: 0 },
    metadata: { type: Schema.Types.Mixed, default: {} },
  },
  { timestamps: true, versionKey: false }
);

ZanacoDistributionSchema.index({ date: 1, branch: 1, channel: 1 }, { unique: true });

ZanacoDistributionSchema.pre("validate", function (next) {
  if (this.date) {
    const n = normalizeToUtcDay(this.date);
    if (n) this.date = n;
  }
  next();
});

const ZanacoDistribution = getOrCreateModel("ZanacoDistribution", ZanacoDistributionSchema);

// -------------------- MonthlyReport model ---------------------
const MonthlyReportSchema = new Schema(
  {
    branch: { type: String, required: true, trim: true, index: true },
    date: { type: Date, required: true, index: true },

    expected: { type: Number, default: 0 },
    inputs: { type: Number, default: 0 },
    collected: { type: Number, default: 0 },
    collectedInput: { type: Number, default: 0 },
    totalUncollected: { type: Number, default: 0 },
    uncollectedInput: { type: Number, default: 0 },
    insufficient: { type: Number, default: 0 },
    insufficientInput: { type: Number, default: 0 },
    unreported: { type: Number, default: 0 },
    unreportedInput: { type: Number, default: 0 },
    lateCollection: { type: Number, default: 0 },
    uncollected: { type: Number, default: 0 },
    permicExpectedNextMonth: { type: Number, default: 0 },
    totalInputs: { type: Number, default: 0 },
    oldInputsAmount: { type: Number, default: 0 },
    oldInputsCount: { type: Number, default: 0 },
    newInputsAmount: { type: Number, default: 0 },
    newInputsCount: { type: Number, default: 0 },
    cashAdvance: { type: Number, default: 0 },
    overallExpected: { type: Number, default: 0 },
    actualExpected: { type: Number, default: 0 },
    collected2: { type: Number, default: 0 },
    principalReloaned: { type: Number, default: 0 },
    defaultAmount: { type: Number, default: 0 },
    clearance: { type: Number, default: 0 },
    totalCollections: { type: Number, default: 0 },
    permicCashAdvance: { type: Number, default: 0 },

    synced: { type: Boolean, default: false, index: true },
    updatedAt: { type: Date, default: () => new Date() },
    createdAt: { type: Date, default: () => new Date() },
  },
  { timestamps: true, strict: true, versionKey: false }
);

MonthlyReportSchema.index({ branch: 1, date: 1 }, { unique: true });

MonthlyReportSchema.pre("save", function (next) {
  if (this.date) {
    const normalized = normalizeToUtcMonthStart(this.date);
    if (normalized) this.date = normalized;
  }
  this.updatedAt = new Date();
  if (!this.createdAt) this.createdAt = new Date();
  next();
});

MonthlyReportSchema.pre("findOneAndUpdate", function (next) {
  const upd = this.getUpdate && this.getUpdate();
  if (upd && upd.$set && upd.$set.date) {
    const normalized = normalizeToUtcMonthStart(upd.$set.date);
    if (normalized) this.getUpdate().$set.date = normalized;
  }
  if (upd) {
    this.getUpdate().$set = this.getUpdate().$set || {};
    this.getUpdate().$set.updatedAt = new Date();
  }
  next();
});

const MonthlyReport = getOrCreateModel("MonthlyReport", MonthlyReportSchema);

// ============================================================
// 6) AGREEMENTS ROUTER (optional)
// ============================================================
try {
  const agreementsFactory = require("./routes/agreements");
  if (typeof agreementsFactory === "function") {
    app.use("/api/agreements", agreementsFactory(authMiddleware));
  } else {
    app.use("/api/agreements", authMiddleware, agreementsFactory);
  }
  console.log("✅ /api/agreements mounted");
} catch (e) {
  console.log("ℹ️ agreements router not mounted:", e.message);
}

// ============================================================
// 7) AUTH ROUTER (REGISTER + LOGIN)
// ============================================================
const authRouter = express.Router();

// POST /api/auth/register
authRouter.post("/register", async (req, res) => {
  try {
    const { name, email, phone, password } = req.body || {};
    if (!email || !password) {
      return res.status(400).json({ success: false, error: "email and password required" });
    }

    const normalizedEmail = String(email).toLowerCase().trim();
    const normalizedPhone = normalizePhone(phone);

    const existing = await User.findOne({ email: normalizedEmail }).lean();
    if (existing) return res.status(409).json({ success: false, error: "Email already registered" });

    const passwordHash = await bcrypt.hash(String(password), SALT_ROUNDS);

    const user = await User.create({
      email: normalizedEmail,
      name: name || "",
      phone: normalizedPhone,
      role: "client",
      passwordHash,
      balances: {},
      notifications: [],
    });

    const token = generateToken({
      email: user.email,
      sub: user.email,
      role: user.role,
      name: user.name || "",
      phone: user.phone || "",
    });

    return res.status(201).json({
      token,
      email: user.email,
      role: user.role,
      name: user.name,
      phone: user.phone,
    });
  } catch (err) {
    console.error("POST /api/auth/register error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

// POST /api/auth/login
authRouter.post("/login", async (req, res) => {
  try {
    const { email, password } = req.body || {};
    if (!email || !password) {
      return res.status(400).json({ success: false, error: "email and password required" });
    }

    const normalizedEmail = String(email).toLowerCase().trim();
    const user = await User.findOne({ email: normalizedEmail }).lean();
    if (!user) return res.status(401).json({ success: false, error: "Invalid credentials" });

    const ok = await bcrypt.compare(String(password), String(user.passwordHash || ""));
    if (!ok) return res.status(401).json({ success: false, error: "Invalid credentials" });

    const token = generateToken({
      email: user.email,
      sub: user.email,
      role: user.role,
      name: user.name || "",
      phone: user.phone || "",
    });

    return res.json({
      token,
      email: user.email,
      role: user.role,
      name: user.name || "",
      phone: user.phone || "",
    });
  } catch (err) {
    console.error("POST /api/auth/login error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

// ============================================================
// 8) USERS ROUTER (list + profile + balances + notifications)
// ============================================================
const usersRouter = express.Router();

// GET /api/users (ovadmin only) - minimal list
usersRouter.get("/", authMiddleware, requireRole("ovadmin"), async (req, res) => {
  try {
    const items = await User.find()
      .select("email name phone role createdAt updatedAt")
      .sort({ createdAt: -1 })
      .lean();
    return res.json(items);
  } catch (err) {
    console.error("GET /api/users error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

// GET /api/users/:email/profile
usersRouter.get("/:email/profile", authMiddleware, async (req, res) => {
  try {
    const target = String(req.params.email || "").toLowerCase().trim();
    if (!target) return res.status(400).json({ success: false, error: "email required" });

    // self or admin
    const isSelf = String(req.user?.email || "").toLowerCase().trim() === target;
    const isAdmin = ["ovadmin", "branch_admin"].includes(req.user?.role);
    if (!isSelf && !isAdmin) return res.status(403).json({ success: false, error: "Forbidden" });

    const u = await User.findOne({ email: target }).lean();
    if (!u) return res.status(404).json({ success: false, error: "User not found" });

    const notificationsCount = Array.isArray(u.notifications) ? u.notifications.length : 0;

    return res.json({
      email: u.email,
      name: u.name || "",
      phone: u.phone || "",
      role: u.role || "client",
      balances: u.balances || {},
      notificationsCount,
    });
  } catch (err) {
    console.error("GET /api/users/:email/profile error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

// PUT /api/users/:email/profile
usersRouter.put("/:email/profile", authMiddleware, async (req, res) => {
  try {
    const target = String(req.params.email || "").toLowerCase().trim();
    if (!target) return res.status(400).json({ success: false, error: "email required" });

    const isSelf = String(req.user?.email || "").toLowerCase().trim() === target;
    const isOvAdmin = req.user?.role === "ovadmin";
    if (!isSelf && !isOvAdmin) return res.status(403).json({ success: false, error: "Forbidden" });

    const body = req.body || {};
    const update = {};

    if (body.name != null) update.name = String(body.name);
    if (body.phone != null) update.phone = normalizePhone(body.phone);

    // role change only by ovadmin
    if (body.role != null) {
      if (!isOvAdmin) return res.status(403).json({ success: false, error: "Forbidden" });
      const r = String(body.role);
      if (!["client", "branch_admin", "ovadmin"].includes(r)) {
        return res.status(400).json({ success: false, error: "Invalid role" });
      }
      update.role = r;
    }

    const u = await User.findOneAndUpdate(
      { email: target },
      { $set: update },
      { new: true }
    ).lean();

    if (!u) return res.status(404).json({ success: false, error: "User not found" });

    return res.json({
      success: true,
      profile: {
        email: u.email,
        name: u.name || "",
        phone: u.phone || "",
        role: u.role || "client",
        balances: u.balances || {},
      },
    });
  } catch (err) {
    console.error("PUT /api/users/:email/profile error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

// GET /api/users/:email/next_payment
usersRouter.get("/:email/next_payment", authMiddleware, async (req, res) => {
  try {
    const target = String(req.params.email || "").toLowerCase().trim();
    if (!target) return res.status(400).json({ success: false, error: "email required" });

    const isSelf = String(req.user?.email || "").toLowerCase().trim() === target;
    const isAdmin = ["ovadmin", "branch_admin"].includes(req.user?.role);
    if (!isSelf && !isAdmin) return res.status(403).json({ success: false, error: "Forbidden" });

    const u = await User.findOne({ email: target }).lean();
    if (!u) return res.status(404).json({ success: false, error: "User not found" });

    const np = u?.balances?.next_payment || null;
    return res.json({ next_payment: np });
  } catch (err) {
    console.error("GET /api/users/:email/next_payment error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

// GET /api/users/:email/balances
usersRouter.get("/:email/balances", authMiddleware, async (req, res) => {
  try {
    const email = String(req.params.email || "").toLowerCase().trim();
    const isSelf = String(req.user?.email || "").toLowerCase().trim() === email;
    const isAdmin = ["ovadmin", "branch_admin"].includes(req.user?.role);
    if (!isSelf && !isAdmin) return res.status(403).json({ success: false, error: "Forbidden" });

    const user = await User.findOne({ email }).lean();
    if (!user) return res.status(404).json({ success: false, error: "User not found" });
    return res.json(Object.assign({}, user.balances || {}));
  } catch (err) {
    console.error("GET /api/users/:email/balances error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

// POST /api/users/:email/balances
usersRouter.post("/:email/balances", authMiddleware, async (req, res) => {
  try {
    const email = String(req.params.email || "").toLowerCase().trim();
    const isSelf = String(req.user?.email || "").toLowerCase().trim() === email;
    const isAdmin = ["ovadmin", "branch_admin"].includes(req.user?.role);
    if (!isSelf && !isAdmin) return res.status(403).json({ success: false, error: "Forbidden" });

    const payload = req.body || {};

    const update = {};
    const setBalances = {};

    const pickNum = (v) => {
      if (v == null) return undefined;
      const n = Number(v);
      return Number.isNaN(n) ? undefined : n;
    };

    const amountBorrowed = pickNum(payload.amountBorrowed ?? payload.amount_borrowed);
    const amountPaid = pickNum(payload.amountPaid ?? payload.amount_paid);
    const actualBalance = pickNum(payload.actualBalance ?? payload.actual_balance);
    const interestRate = pickNum(payload.interestRate ?? payload.interest_rate);

    if (amountBorrowed != null) setBalances["balances.amountBorrowed"] = amountBorrowed;
    if (amountPaid != null) setBalances["balances.amountPaid"] = amountPaid;
    if (actualBalance != null) setBalances["balances.actualBalance"] = actualBalance;
    if (interestRate != null) setBalances["balances.interestRate"] = interestRate;

    if (payload.next_payment && typeof payload.next_payment === "object") {
      const np = {};
      if (payload.next_payment.amount != null) {
        const a = pickNum(payload.next_payment.amount);
        if (a != null) np.amount = a;
      }
      if (payload.next_payment.date) {
        const d = new Date(payload.next_payment.date);
        if (!isNaN(d.getTime())) np.date = d;
      }
      if (Object.keys(np).length) setBalances["balances.next_payment"] = np;
    }

    update.$set = Object.assign({}, setBalances);

    const user = await User.findOneAndUpdate({ email }, update, { new: true }).lean();
    if (!user) return res.status(404).json({ success: false, error: "User not found" });

    return res.json({ success: true, message: "Balances updated", balances: user.balances || {} });
  } catch (err) {
    console.error("POST /api/users/:email/balances error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

// POST /api/users/:email/notifications
usersRouter.post("/:email/notifications", authMiddleware, async (req, res) => {
  try {
    const email = String(req.params.email || "").toLowerCase().trim();
    const isSelf = String(req.user?.email || "").toLowerCase().trim() === email;
    const isAdmin = ["ovadmin", "branch_admin"].includes(req.user?.role);
    if (!isSelf && !isAdmin) return res.status(403).json({ success: false, error: "Forbidden" });

    const { title, message, type } = req.body || {};
    if (!title || !message) return res.status(400).json({ success: false, error: "title and message are required" });

    const n = {
      title: String(title),
      message: String(message),
      type: ["info", "success", "warning", "error"].includes(type) ? type : "info",
      ts: new Date(),
    };

    const user = await User.findOneAndUpdate(
      { email },
      {
        $push: { notifications: { $each: [n], $position: 0 } },
      },
      { new: true }
    ).lean();

    if (!user) return res.status(404).json({ success: false, error: "User not found" });

    // cap notifications (server-side cap)
    if (Array.isArray(user.notifications) && user.notifications.length > 200) {
      await User.updateOne({ email }, { $set: { notifications: user.notifications.slice(0, 200) } });
    }

    return res.status(201).json({ success: true, message: "Notification added", notification: n });
  } catch (err) {
    console.error("POST /api/users/:email/notifications error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

// ============================================================
// 9) ADMIN ROUTER (submissions + notify overall admin)
// ============================================================
const adminRouter = express.Router();

adminRouter.post("/submissions", authMiddleware, async (req, res) => {
  try {
    const body = req.body || {};
    const from = (body.from || req.user?.email || "unknown").toLowerCase();
    const now = new Date();

    const sub = new AdminSubmission({ from, ts: now, data: body });
    await sub.save();

    // notify overall admin (if exists)
    const adminUser = await User.findOne({ email: OVERALL_ADMIN_EMAIL }).lean();
    if (adminUser) {
      const note = {
        title: "New client submission",
        message: `Submission from ${from}`,
        type: "info",
        ts: now,
      };

      await User.updateOne(
        { email: OVERALL_ADMIN_EMAIL },
        { $push: { notifications: { $each: [note], $position: 0 } } }
      );
    }

    return res.status(201).json({ success: true, message: "Submission saved", id: sub._id.toString() });
  } catch (err) {
    console.error("POST /api/admin/submissions error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

adminRouter.get("/submissions", authMiddleware, requireRole("ovadmin", "branch_admin"), async (req, res) => {
  try {
    const items = await AdminSubmission.find().sort({ ts: -1 }).lean();
    return res.json(items);
  } catch (err) {
    console.error("GET /api/admin/submissions error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

adminRouter.delete("/submissions/:id", authMiddleware, requireRole("ovadmin"), async (req, res) => {
  try {
    const id = req.params.id;
    const deleted = await AdminSubmission.findByIdAndDelete(id).lean();
    if (!deleted) return res.status(404).json({ success: false, error: "Not found" });
    return res.json({ success: true, message: "Submission deleted", deletedId: String(deleted._id) });
  } catch (err) {
    console.error("DELETE /api/admin/submissions/:id error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

// ============================================================
// 10) REPORTS ROUTER (Zanaco + Daily + Monthly)
// ============================================================
const reportsRouter = express.Router();

// -------------------- ZANACO endpoints -----------------------
reportsRouter.get("/zanaco/distributions", async (req, res) => {
  try {
    const { date, branch, channel } = req.query;
    if (!date) return res.status(400).json({ success: false, error: "date required" });

    const norm = normalizeToUtcDay(date);
    if (!norm) return res.status(400).json({ success: false, error: "invalid date" });

    const q = { date: norm };
    if (branch) q.branch = String(branch).trim();
    if (channel) q.channel = String(channel).toLowerCase().trim();

    const docs = await ZanacoDistribution.find(q).lean();
    return res.json({ success: true, distributions: docs });
  } catch (err) {
    console.error("GET /api/zanaco/distributions error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

reportsRouter.get("/zanaco", async (req, res) => {
  try {
    const { date, branch, channel } = req.query;
    if (!date) return res.status(400).json({ success: false, error: "date required" });

    const norm = normalizeToUtcDay(date);
    if (!norm) return res.status(400).json({ success: false, error: "invalid date" });

    const q = { date: norm };
    if (branch) q.branch = String(branch).trim();
    if (channel) q.channel = String(channel).toLowerCase().trim();

    const docs = await ZanacoDistribution.find(q).lean();
    if (branch && channel) return res.json({ success: true, amount: docs[0] ? docs[0].amount : 0 });

    return res.json({ success: true, distributions: docs });
  } catch (err) {
    console.error("GET /api/zanaco error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

reportsRouter.post("/zanaco", async (req, res) => {
  try {
    const { date, branch, channel, amount, metadata } = req.body || {};
    if (!date || !branch || !channel) {
      return res.status(400).json({ success: false, error: "date, branch and channel required" });
    }

    const norm = normalizeToUtcDay(date);
    if (!norm) return res.status(400).json({ success: false, error: "invalid date" });

    const filter = { date: norm, branch: String(branch).trim(), channel: String(channel).toLowerCase().trim() };
    const update = {
      $set: {
        date: norm,
        branch: filter.branch,
        channel: filter.channel,
        amount: Number(amount) || 0,
        metadata: metadata || {},
      },
    };

    const doc = await ZanacoDistribution.findOneAndUpdate(filter, update, {
      upsert: true,
      new: true,
      setDefaultsOnInsert: true,
    }).lean();

    return res.json({ success: true, distribution: doc });
  } catch (err) {
    console.error("POST /api/zanaco error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

reportsRouter.post("/zanaco/bulk", async (req, res) => {
  try {
    const { date, fromBranch, allocations } = req.body || {};
    if (!date || !allocations || typeof allocations !== "object") {
      return res.status(400).json({ success: false, error: "date and allocations are required" });
    }

    const norm = normalizeToUtcDay(date);
    if (!norm) return res.status(400).json({ success: false, error: "invalid date" });

    const ops = [];
    for (const [targetBranch, chMap] of Object.entries(allocations)) {
      if (!chMap || typeof chMap !== "object") continue;
      for (const [ch, amtRaw] of Object.entries(chMap)) {
        const channel = String(ch).toLowerCase().trim();
        const amount = Number(amtRaw) || 0;
        const filter = { date: norm, branch: String(targetBranch).trim(), channel };

        const update = {
          $set: {
            date: norm,
            branch: filter.branch,
            channel,
            amount,
            metadata: { fromBranch: fromBranch || null },
          },
          $setOnInsert: { createdAt: new Date() },
        };

        ops.push({ updateOne: { filter, update, upsert: true } });
      }
    }

    if (ops.length === 0) return res.status(400).json({ success: false, error: "no valid allocations provided" });

    let bulkRes;
    try {
      bulkRes = await ZanacoDistribution.bulkWrite(ops, { ordered: false });
    } catch (bulkErr) {
      console.error("zanaco bulkWrite error:", bulkErr);
    }

    return res.json({
      success: true,
      message: "Zanaco allocations processed",
      bulkWriteResult: bulkRes
        ? {
            insertedCount: bulkRes.insertedCount || 0,
            matchedCount: bulkRes.matchedCount || 0,
            modifiedCount: bulkRes.modifiedCount || 0,
            upsertedCount: bulkRes.upsertedCount || 0,
            upsertedIds: bulkRes.upsertedIds || {},
          }
        : undefined,
    });
  } catch (err) {
    console.error("POST /api/zanaco/bulk error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

// -------------------- Daily sync -----------------------------
reportsRouter.post("/sync_reports", async (req, res) => {
  try {
    const { reports } = req.body;
    if (!reports || !Array.isArray(reports)) {
      return res.status(400).json({ success: false, error: "Invalid request: expected { reports: [...] }" });
    }

    const operations = [];
    const skipped = [];
    const errors = [];
    const canonicalTargets = [];

    for (const raw of reports) {
      try {
        if (!raw || typeof raw !== "object") {
          skipped.push({ reason: "invalid item (not object)", item: raw });
          continue;
        }

        const branch = raw.branch ? String(raw.branch).trim() : "";
        if (!branch) {
          skipped.push({ reason: "missing branch", item: raw });
          continue;
        }

        const normalizedDate = normalizeToUtcDay(raw.date);
        if (!normalizedDate) {
          skipped.push({ reason: "invalid date", item: raw });
          continue;
        }

        const openingBalances = sanitizeNumericMap(raw.openingBalances);
        const closingBalances = sanitizeNumericMap(raw.closingBalances);
        const loanCounts = sanitizeIntegerMap(raw.loanCounts);

        const updateData = {
          branch,
          date: normalizedDate,
          openingBalances,
          loanCounts,
          closingBalances,
          totalDisbursed: toNumber(raw.totalDisbursed),
          totalCollected: toNumber(raw.totalCollected),
          collectedForOtherBranches: toNumber(raw.collectedForOtherBranches),
          pettyCash: toNumber(raw.pettyCash),
          expenses: toNumber(raw.expenses),
          synced: true,
          updatedAt: raw.updatedAt ? new Date(raw.updatedAt) : new Date(),
        };

        operations.push({
          updateOne: {
            filter: { branch, date: normalizedDate },
            update: { $set: updateData, $setOnInsert: { createdAt: new Date() } },
            upsert: true,
          },
        });

        canonicalTargets.push({ branch, date: normalizedDate });
      } catch (inner) {
        console.error("prepare op error:", inner);
        errors.push({ item: raw, error: inner.message || String(inner) });
      }
    }

    if (operations.length === 0) {
      return res.json({ success: true, message: "No valid reports to process", saved: [], skipped, errors });
    }

    let bulkResult;
    try {
      bulkResult = await DailyReport.bulkWrite(operations, { ordered: false });
    } catch (bulkErr) {
      console.error("bulkWrite error:", bulkErr);
      errors.push({ error: "bulkWrite failed", detail: bulkErr.message || String(bulkErr) });
    }

    const orFilters = canonicalTargets.map((t) => ({ branch: t.branch, date: t.date }));
    let savedDocs = [];
    if (orFilters.length > 0) {
      try {
        savedDocs = await DailyReport.find({ $or: orFilters }).select("branch date _id").lean();
      } catch (qerr) {
        console.error("Query after bulkWrite failed:", qerr);
        errors.push({ error: "post-query failed", detail: qerr.message || String(qerr) });
      }
    }

    const saved = savedDocs.map((d) => ({
      branch: d.branch,
      date: new Date(d.date).toISOString(),
      id: d._id ? d._id.toString() : null,
    }));

    return res.json({
      success: true,
      message: `${saved.length} reports processed (bulkWrite)`,
      saved,
      skipped,
      errors,
      bulkWriteResult: bulkResult
        ? {
            insertedCount: bulkResult.insertedCount || 0,
            matchedCount: bulkResult.matchedCount || 0,
            modifiedCount: bulkResult.modifiedCount || 0,
            upsertedCount: bulkResult.upsertedCount || 0,
            upsertedIds: bulkResult.upsertedIds || {},
          }
        : undefined,
    });
  } catch (err) {
    console.error("POST /api/sync_reports catastrophic error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

reportsRouter.get("/reports", async (req, res) => {
  try {
    const reports = await DailyReport.find().sort({ date: -1 }).lean();
    return res.json(reports);
  } catch (err) {
    console.error("GET /api/reports error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

reportsRouter.get("/reports/query", async (req, res) => {
  try {
    const { branch, date } = req.query;
    if (!branch || !date) return res.status(400).json({ success: false, error: "branch and date required" });

    const norm = normalizeToUtcDay(date);
    if (!norm) return res.status(400).json({ success: false, error: "invalid date" });

    const doc = await DailyReport.findOne({ branch: String(branch).trim(), date: norm }).lean();
    return res.json({ success: true, report: doc });
  } catch (err) {
    console.error("GET /api/reports/query error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

reportsRouter.post("/report", async (req, res) => {
  try {
    const raw = req.body || {};
    const branch = raw.branch ? String(raw.branch).trim() : "";
    const dateNorm = normalizeToUtcDay(raw.date);

    if (!branch || !dateNorm) return res.status(400).json({ success: false, error: "branch and valid date required" });

    const openingBalances = sanitizeNumericMap(raw.openingBalances);
    const closingBalances = sanitizeNumericMap(raw.closingBalances);
    const loanCounts = sanitizeIntegerMap(raw.loanCounts);

    const updateData = {
      branch,
      date: dateNorm,
      openingBalances,
      loanCounts,
      closingBalances,
      totalDisbursed: toNumber(raw.totalDisbursed),
      totalCollected: toNumber(raw.totalCollected),
      collectedForOtherBranches: toNumber(raw.collectedForOtherBranches),
      pettyCash: toNumber(raw.pettyCash),
      expenses: toNumber(raw.expenses),
      synced: true,
      updatedAt: raw.updatedAt ? new Date(raw.updatedAt) : new Date(),
    };

    const doc = await DailyReport.findOneAndUpdate(
      { branch, date: dateNorm },
      { $set: updateData, $setOnInsert: { createdAt: new Date() } },
      { upsert: true, new: true }
    ).lean();

    return res.json({ success: true, report: doc });
  } catch (err) {
    console.error("POST /api/report error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

reportsRouter.delete("/reports", async (req, res) => {
  try {
    const { branch, date } = req.body;
    if (!branch || !date) return res.status(400).json({ success: false, error: "branch and date are required" });

    const parsed = new Date(date);
    if (isNaN(parsed.getTime())) return res.status(400).json({ success: false, error: "invalid date format" });

    const startOfDay = new Date(Date.UTC(parsed.getUTCFullYear(), parsed.getUTCMonth(), parsed.getUTCDate(), 0, 0, 0));
    const endOfDay = new Date(startOfDay);
    endOfDay.setUTCDate(endOfDay.getUTCDate() + 1);

    const deleted = await DailyReport.findOneAndDelete({ branch, date: { $gte: startOfDay, $lt: endOfDay } }).lean();
    if (!deleted) return res.status(404).json({ success: false, error: "Report not found" });

    return res.json({ success: true, message: "Report deleted", deletedId: String(deleted._id) });
  } catch (err) {
    console.error("DELETE /api/reports error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

reportsRouter.delete("/reports/:id", async (req, res) => {
  try {
    const id = req.params.id;
    const deleted = await DailyReport.findByIdAndDelete(id).lean();
    if (!deleted) return res.status(404).json({ success: false, error: "Not found" });

    return res.json({ success: true, message: "Report deleted", deletedId: String(deleted._id) });
  } catch (err) {
    console.error("DELETE /api/reports/:id error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

// -------------------- Monthly sync ---------------------------
reportsRouter.post("/sync_monthly_reports", async (req, res) => {
  try {
    const { monthlyReports } = req.body;
    if (!monthlyReports || !Array.isArray(monthlyReports)) {
      return res.status(400).json({ success: false, error: "Invalid request: expected { monthlyReports: [...] }" });
    }

    const operations = [];
    const skipped = [];
    const errors = [];
    const canonicalTargets = [];

    for (const raw of monthlyReports) {
      try {
        if (!raw || typeof raw !== "object") {
          skipped.push({ reason: "invalid item (not object)", item: raw });
          continue;
        }

        const branch = raw.branch ? String(raw.branch).trim() : "";
        if (!branch) {
          skipped.push({ reason: "missing branch", item: raw });
          continue;
        }

        const normalizedDate = normalizeToUtcMonthStart(raw.date);
        if (!normalizedDate) {
          skipped.push({ reason: "invalid date", item: raw });
          continue;
        }

        const updateData = {
          branch,
          date: normalizedDate,
          expected: toNumber(raw.expected),
          inputs: Number.isInteger(raw.inputs) ? raw.inputs : raw.inputs ? parseInt(raw.inputs, 10) || 0 : 0,
          collected: toNumber(raw.collected),
          collectedInput: Number.isInteger(raw.collectedInput)
            ? raw.collectedInput
            : raw.collectedInput
            ? parseInt(raw.collectedInput, 10) || 0
            : 0,
          totalUncollected: toNumber(raw.totalUncollected),
          uncollectedInput: Number.isInteger(raw.uncollectedInput)
            ? raw.uncollectedInput
            : raw.uncollectedInput
            ? parseInt(raw.uncollectedInput, 10) || 0
            : 0,
          insufficient: toNumber(raw.insufficient),
          insufficientInput: Number.isInteger(raw.insufficientInput)
            ? raw.insufficientInput
            : raw.insufficientInput
            ? parseInt(raw.insufficientInput, 10) || 0
            : 0,
          unreported: toNumber(raw.unreported),
          unreportedInput: Number.isInteger(raw.unreportedInput)
            ? raw.unreportedInput
            : raw.unreportedInput
            ? parseInt(raw.unreportedInput, 10) || 0
            : 0,
          lateCollection: toNumber(raw.lateCollection),
          uncollected: toNumber(raw.uncollected),
          permicExpectedNextMonth: toNumber(raw.permicExpectedNextMonth),
          totalInputs: Number.isInteger(raw.totalInputs)
            ? raw.totalInputs
            : raw.totalInputs
            ? parseInt(raw.totalInputs, 10) || 0
            : 0,
          oldInputsAmount: toNumber(raw.oldInputsAmount),
          oldInputsCount: Number.isInteger(raw.oldInputsCount)
            ? raw.oldInputsCount
            : raw.oldInputsCount
            ? parseInt(raw.oldInputsCount, 10) || 0
            : 0,
          newInputsAmount: toNumber(raw.newInputsAmount),
          newInputsCount: Number.isInteger(raw.newInputsCount)
            ? raw.newInputsCount
            : raw.newInputsCount
            ? parseInt(raw.newInputsCount, 10) || 0
            : 0,
          cashAdvance: toNumber(raw.cashAdvance),
          overallExpected: toNumber(raw.overallExpected),
          actualExpected: toNumber(raw.actualExpected),
          collected2: toNumber(raw.collected2),
          principalReloaned: toNumber(raw.principalReloaned),
          defaultAmount: toNumber(raw.defaultAmount),
          clearance: toNumber(raw.clearance),
          totalCollections: toNumber(raw.totalCollections),
          permicCashAdvance: toNumber(raw.permicCashAdvance),
          synced: true,
          updatedAt: raw.updatedAt ? new Date(raw.updatedAt) : new Date(),
        };

        operations.push({
          updateOne: {
            filter: { branch, date: normalizedDate },
            update: { $set: updateData, $setOnInsert: { createdAt: new Date() } },
            upsert: true,
          },
        });

        canonicalTargets.push({ branch, date: normalizedDate });
      } catch (inner) {
        console.error("prepare monthly op error:", inner);
        errors.push({ item: raw, error: inner.message || String(inner) });
      }
    }

    if (operations.length === 0) {
      return res.json({ success: true, message: "No valid monthly reports to process", saved: [], skipped, errors });
    }

    let bulkResult;
    try {
      bulkResult = await MonthlyReport.bulkWrite(operations, { ordered: false });
    } catch (bulkErr) {
      console.error("monthly bulkWrite error:", bulkErr);
      errors.push({ error: "bulkWrite failed", detail: bulkErr.message || String(bulkErr) });
    }

    const orFilters = canonicalTargets.map((t) => ({ branch: t.branch, date: t.date }));
    let savedDocs = [];
    if (orFilters.length > 0) {
      try {
        savedDocs = await MonthlyReport.find({ $or: orFilters }).select("branch date _id").lean();
      } catch (qerr) {
        console.error("Query after monthly bulkWrite failed:", qerr);
        errors.push({ error: "post-query failed", detail: qerr.message || String(qerr) });
      }
    }

    const saved = savedDocs.map((d) => ({
      branch: d.branch,
      date: new Date(d.date).toISOString(),
      id: d._id ? d._id.toString() : null,
    }));

    return res.json({
      success: true,
      message: `${saved.length} monthly reports processed (bulkWrite)`,
      saved,
      skipped,
      errors,
      bulkWriteResult: bulkResult
        ? {
            insertedCount: bulkResult.insertedCount || 0,
            matchedCount: bulkResult.matchedCount || 0,
            modifiedCount: bulkResult.modifiedCount || 0,
            upsertedCount: bulkResult.upsertedCount || 0,
            upsertedIds: bulkResult.upsertedIds || {},
          }
        : undefined,
    });
  } catch (err) {
    console.error("POST /api/sync_monthly_reports catastrophic error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

reportsRouter.get("/monthly_reports", async (req, res) => {
  try {
    const reports = await MonthlyReport.find().sort({ date: -1 }).lean();
    return res.json(reports);
  } catch (err) {
    console.error("GET /api/monthly_reports error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

reportsRouter.delete("/monthly_reports", async (req, res) => {
  try {
    const { branch, date } = req.body;
    if (!branch || !date) return res.status(400).json({ success: false, error: "branch and date are required" });

    const parsed = new Date(date);
    if (isNaN(parsed.getTime())) return res.status(400).json({ success: false, error: "invalid date format" });

    const startOfMonth = new Date(Date.UTC(parsed.getUTCFullYear(), parsed.getUTCMonth(), 1, 0, 0, 0));
    const startOfNextMonth = new Date(Date.UTC(parsed.getUTCFullYear(), parsed.getUTCMonth() + 1, 1, 0, 0, 0));

    const deleted = await MonthlyReport.findOneAndDelete({
      branch,
      date: { $gte: startOfMonth, $lt: startOfNextMonth },
    }).lean();

    if (!deleted) return res.status(404).json({ success: false, error: "Monthly report not found" });
    return res.json({ success: true, message: "Monthly report deleted", deletedId: String(deleted._id) });
  } catch (err) {
    console.error("DELETE /api/monthly_reports error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

reportsRouter.delete("/monthly_reports/:id", async (req, res) => {
  try {
    const id = req.params.id;
    const deleted = await MonthlyReport.findByIdAndDelete(id).lean();
    if (!deleted) return res.status(404).json({ success: false, error: "Not found" });
    return res.json({ success: true, message: "Monthly report deleted", deletedId: String(deleted._id) });
  } catch (err) {
    console.error("DELETE /api/monthly_reports/:id error:", err);
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
});

// ============================================================
// 11) CLIENTS ROUTER (MUST be mounted, show errors if it fails)
// ============================================================
try {
  const clientsRouter = require("./routes/clients");
  app.use("/api/clients", authMiddleware, clientsRouter);
  console.log("✅ /api/clients mounted");
} catch (e) {
  console.log("❌ clients router failed to mount:", e.message);
}

// ============================================================
// 12) MOUNT ROUTERS
// ============================================================
app.use("/api/auth", authRouter);
app.use("/api/users", usersRouter);
app.use("/api/admin", adminRouter);
app.use("/api", reportsRouter);

// Loans router
try {
  const loansRouter = require("./routes/loans");
  app.use("/api/loans", loansRouter);
  console.log("✅ /api/loans mounted");
} catch (e) {
  console.log("ℹ️ loans router not mounted:", e.message);
}

// Imports router
try {
  const importsRouter = require("./routes/imports");
  app.use("/api/imports", importsRouter);
  console.log("✅ /api/imports mounted");
} catch (e) {
  console.log("ℹ️ imports router not mounted:", e.message);
}

// ============================================================
// 13) HEALTH + ROOT
// ============================================================
app.get("/health", (req, res) => {
  res.status(200).json({
    status: "OK",
    message: "DAML Server is running",
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || "development",
  });
});

app.get("/", (req, res) => {
  res.json({
    message: "DAML Server API",
    version: "1.0.0",
    endpoints: {
      health: "/health",
      sync: "/api/sync_reports",
      reports: "/api/reports",
      zanaco: "/api/zanaco",
      monthly: "/api/monthly_reports",
      clientsMe: "/api/clients/me",
    },
  });
});

// ============================================================
// 14) ERROR HANDLER + 404
// ============================================================
app.use((err, req, res, next) => {
  console.error("Server error:", err);
  res.status(500).json({
    success: false,
    error: "Internal server error",
    message: process.env.NODE_ENV === "production" ? "Something went wrong" : err.message,
  });
});

app.use((req, res) => {
  res.status(404).json({ success: false, error: "Endpoint not found", path: req.path });
});

// ============================================================
// 15) CONNECT DB + START SERVER
// ============================================================
mongoose
  .connect(mongoUri, { autoIndex: true })
  .then(() => console.log("✅ MongoDB connected successfully"))
  .catch((err) => {
    console.error("❌ MongoDB connection error:", err.message);
    process.exit(1);
  });

// Bind to 0.0.0.0 so phones on LAN can access via PC IP
const server = app.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 DAML Server running on port ${PORT}`);
  console.log(`🌐 Environment: ${process.env.NODE_ENV || "development"}`);
});

// ============================================================
// 16) GRACEFUL SHUTDOWN
// ============================================================
const shutdown = async (signal) => {
  console.log(`\nReceived ${signal}. Closing server...`);
  server.close(async () => {
    try {
      await mongoose.disconnect();
      console.log("MongoDB disconnected. Exiting.");
      process.exit(0);
    } catch (err) {
      console.error("Error during shutdown", err);
      process.exit(1);
    }
  });
};

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));

// ============================================================
// 17) SEED DEV ADMINS (optional) -> node server.js --seed
// ============================================================
async function seedAdmins() {
  try {
    console.log("Seeding dev admin accounts...");

    const branchEmails = [
      "monze@directaccess.com",
      "mazabuka@directaccess.com",
      "lusaka@directaccess.com",
      "solwezi@directaccess.com",
      "lumezi@directaccess.com",
      "nakonde@directaccess.com",
    ];

    const overall = OVERALL_ADMIN_EMAIL;

    const ov = await User.findOne({ email: overall }).lean();
    if (!ov) {
      const passwordHash = await bcrypt.hash("ovadmin", SALT_ROUNDS);
      await User.create({ email: overall, name: "Overall Admin", role: "ovadmin", passwordHash });
      console.log(`Created overall admin ${overall} / ovadmin`);
    } else {
      console.log(`Overall admin ${overall} already exists`);
    }

    for (const e of branchEmails) {
      const normalized = e.toLowerCase().trim();
      const u2 = await User.findOne({ email: normalized }).lean();
      if (!u2) {
        const passwordHash = await bcrypt.hash("admin", SALT_ROUNDS);
        await User.create({ email: normalized, name: "Branch Admin", role: "branch_admin", passwordHash });
        console.log(`Created branch admin ${normalized} / admin`);
      } else {
        console.log(`Branch admin ${normalized} already exists`);
      }
    }

    console.log("Seeding finished.");
  } catch (err) {
    console.error("Seed failed", err);
  }
}

if (process.argv.includes("--seed")) {
  mongoose.connection.once("open", () => {
    seedAdmins()
      .then(() => {
        console.log("Seed complete. Exiting.");
        process.exit(0);
      })
      .catch((err) => {
        console.error("Seed error", err);
        process.exit(1);
      });
  });
}
