// server.js
require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const rateLimit = require('express-rate-limit');
const morgan = require('morgan');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');


const app = express();
const SALT_ROUNDS = 10;

// --- Config
const mongoUri = process.env.MONGO_URI;
const PORT = process.env.PORT || 5000;
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret';
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '7d';
const OVERALL_ADMIN_EMAIL = (process.env.OVERALL_ADMIN_EMAIL || 'directaccessmoney@gmail.com').toLowerCase().trim();

if (!mongoUri) {
  console.error('❌ MongoDB connection URI is required (set MONGO_URI in .env)');
  process.exit(1);
}

// --- Middlewares
app.use(helmet());
app.use(compression());
app.use(express.json({ limit: '10mb' }));
app.use(morgan('combined'));

// CORS: permissive in dev, restrict in prod via env var
const corsOptions = {
  origin: process.env.NODE_ENV === 'production' ? (process.env.CORS_ORIGIN || []) : true,
  methods: ['GET','POST','PUT','DELETE','OPTIONS']
};
app.use(cors(corsOptions));

// Rate limiter (basic)
const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false
});
app.use(limiter);

// --- Mongoose models (kept here for back-compat; you may split into models/*.js)
const { Schema } = mongoose;

// -- User
const NotificationSchema = new Schema({
  id: { type: String, required: true },
  title: String,
  message: String,
  type: { type: String, enum: ['info','success','warning','error'], default: 'info' },
  ts: { type: Date, default: () => new Date() }
}, { _id: false });

const NextPaymentSchema = new Schema({
  amount: { type: Number },
  date: { type: Date }
}, { _id: false });

const BalancesSchema = new Schema({
  amountBorrowed: { type: Number, default: 0 },
  amountPaid: { type: Number, default: 0 },
  actualBalance: { type: Number, default: 0 },
  interestRate: { type: Number, default: 0 },
  next_payment: { type: NextPaymentSchema, default: null }
}, { _id: false });

const UserSchema = new Schema({
  email: { type: String, required: true, unique: true, lowercase: true, trim: true, index: true },
  passwordHash: { type: String, required: true },
  name: { type: String, default: '' },
  phone: { type: String, default: '' },
  role: { type: String, enum: ['client','branch_admin','ovadmin'], default: 'client', index: true },
  balances: { type: BalancesSchema, default: () => ({}) },
  notifications: { type: [NotificationSchema], default: [] },
  createdAt: { type: Date, default: () => new Date() },
  updatedAt: { type: Date, default: () => new Date() }
}, {
  timestamps: true
});

UserSchema.pre('save', function(next) {
  this.email = (this.email || '').toLowerCase().trim();
  this.updatedAt = new Date();
  next();
});

UserSchema.methods.setPassword = async function (plain) {
  this.passwordHash = await bcrypt.hash(plain, SALT_ROUNDS);
  return this;
};
UserSchema.methods.verifyPassword = async function (plain) {
  if (!this.passwordHash) return false;
  return bcrypt.compare(plain, this.passwordHash);
};

const User = mongoose.model('User', UserSchema);

// ---------- AdminSubmission model ----------
const AdminSubmissionSchema = new Schema({
  from: { type: String, default: 'unknown' },
  ts: { type: Date, default: () => new Date() },
  data: { type: Schema.Types.Mixed, default: {} }
}, { timestamps: true });

const AdminSubmission = mongoose.model('AdminSubmission', AdminSubmissionSchema);

// ---------- BranchComment model ----------
const BranchCommentSchema = new Schema({
  branchName: String,
  comments: [
    {
      author: String,
      comment: String,
      timestamp: Date
    }
  ],
  updatedAt: { type: Date, default: Date.now }
});
const BranchComment = mongoose.model('BranchComment', BranchCommentSchema);

// ---------- DailyReport model ----------
const DailyReportSchema = new Schema({
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
  updatedAt: { type: Date, default: Date.now }
}, {
  timestamps: true
});
DailyReportSchema.index({ branch: 1, date: 1 }, { unique: true });
const DailyReport = mongoose.model('DailyReport', DailyReportSchema);

// ---------- ZanacoDistribution model ----------
function normalizeToUtcDay(dateInput) {
  const d = new Date(dateInput);
  if (isNaN(d.getTime())) return null;
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 0, 0, 0));
}

const ZanacoDistributionSchema = new Schema({
  date: { type: Date, required: true, index: true },
  branch: { type: String, required: true, trim: true, index: true },
  channel: { type: String, required: true, trim: true, lowercase: true, index: true },
  amount: { type: Number, required: true, default: 0 },
  metadata: { type: Schema.Types.Mixed, default: {} }
}, {
  timestamps: true,
  versionKey: false
});
ZanacoDistributionSchema.index({ date: 1, branch: 1, channel: 1 }, { unique: true });

ZanacoDistributionSchema.pre('validate', function(next) {
  if (this.date) {
    const n = normalizeToUtcDay(this.date);
    if (n) this.date = n;
  }
  next();
});

ZanacoDistributionSchema.method('toJSON', function () {
  const obj = this.toObject({ getters: true, virtuals: false });
  if (obj.date) obj.date = new Date(obj.date).toISOString();
  return obj;
});

const ZanacoDistribution = mongoose.model('ZanacoDistribution', ZanacoDistributionSchema);

// ---------- MonthlyReport model ----------
function normalizeToUtcMonthStart(dateInput) {
  const d = new Date(dateInput);
  if (isNaN(d.getTime())) return null;
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1, 0, 0, 0));
}
const MonthlyReportSchema = new Schema({
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
  createdAt: { type: Date, default: () => new Date() }
}, {
  timestamps: true,
  strict: true,
  versionKey: false
});
MonthlyReportSchema.index({ branch: 1, date: 1 }, { unique: true });

MonthlyReportSchema.pre('save', function (next) {
  if (this.date) {
    const normalized = normalizeToUtcMonthStart(this.date);
    if (normalized) this.date = normalized;
  }
  this.updatedAt = this.updatedAt ? new Date(this.updatedAt) : new Date();
  if (!this.createdAt) this.createdAt = new Date();
  next();
});
MonthlyReportSchema.pre('findOneAndUpdate', function (next) {
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
MonthlyReportSchema.method('toJSON', function () {
  const obj = this.toObject({ getters: true, virtuals: false });
  if (obj.date) obj.date = new Date(obj.date).toISOString();
  if (obj.updatedAt) obj.updatedAt = new Date(obj.updatedAt).toISOString();
  if (obj.createdAt) obj.createdAt = new Date(obj.createdAt).toISOString();
  return obj;
});
const MonthlyReport = mongoose.model('MonthlyReport', MonthlyReportSchema);

// ---------- Helper functions used in many routes ----------
function sanitizeNumericMap(maybe) {
  if (!maybe || typeof maybe !== 'object') return {};
  const out = {};
  for (const [k, v] of Object.entries(maybe)) {
    const num = (typeof v === 'number') ? v : (v === null || v === '' ? 0 : Number(v));
    out[k] = Number.isNaN(num) ? 0 : num;
  }
  return out;
}
function sanitizeIntegerMap(maybe) {
  if (!maybe || typeof maybe !== 'object') return {};
  const out = {};
  for (const [k, v] of Object.entries(maybe)) {
    if (typeof v === 'number') out[k] = Math.trunc(v);
    else if (typeof v === 'string') {
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
  if (typeof v === 'number') return v;
  if (typeof v === 'string') {
    const n = Number(v);
    return Number.isNaN(n) ? 0 : n;
  }
  return 0;
}

// --- Auth middleware (simple version, kept in server for routes here)
// NOTE: you also have middleware/auth.js — you can unify by moving this out.
async function authMiddleware(req, res, next) {
  const auth = req.headers['authorization'];
  if (!auth || !auth.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, error: 'Missing Authorization header' });
  }
  const token = auth.slice(7);
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    req.user = payload;
    try {
      const user = await User.findOne({ email: payload.email.toLowerCase().trim() });
      if (user) req.currentUser = user;
    } catch (_) {}
    next();
  } catch (err) {
    return res.status(401).json({ success: false, error: 'Invalid token' });
  }
}

// --- ROUTERS
const authRouter = express.Router();
function makeTokenFor(user) {
  const payload = { email: user.email, role: user.role };
  return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
}
authRouter.post('/register', async (req, res) => {
  try {
    const { name, email, phone, password } = req.body || {};
    if (!email || !password) return res.status(400).json({ success: false, error: 'email and password required' });

    const normalized = String(email).toLowerCase().trim();
    const existing = await User.findOne({ email: normalized });
    if (existing) return res.status(409).json({ success: false, error: 'Email already registered' });

    const user = new User({ email: normalized, name: name || '', phone: phone || '', role: 'client' });
    await user.setPassword(password);
    await user.save();

    const token = makeTokenFor(user);
    return res.status(201).json({ token, role: user.role, name: user.name, phone: user.phone });
  } catch (err) {
    console.error('POST /auth/register error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});
authRouter.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body || {};
    if (!email || !password) return res.status(400).json({ success: false, error: 'email and password required' });

    const normalized = String(email).toLowerCase().trim();
    const user = await User.findOne({ email: normalized });
    if (!user) return res.status(401).json({ success: false, error: 'Invalid credentials' });

    const ok = await user.verifyPassword(password);
    if (!ok) return res.status(401).json({ success: false, error: 'Invalid credentials' });

    const token = makeTokenFor(user);
    return res.json({ token, role: user.role, name: user.name, phone: user.phone });
  } catch (err) {
    console.error('POST /auth/login error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

// Users router
const usersRouter = express.Router();
usersRouter.get('/:email/balances', authMiddleware, async (req, res) => {
  try {
    const email = req.params.email.toLowerCase().trim();
    const user = await User.findOne({ email });
    if (!user) return res.status(404).json({ success: false, error: 'User not found' });
    return res.json(Object.assign({}, user.balances ? user.balances.toObject() : {}));
  } catch (err) {
    console.error('GET /users/:email/balances error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});
usersRouter.post('/:email/balances', authMiddleware, async (req, res) => {
  try {
    const email = req.params.email.toLowerCase().trim();
    const payload = req.body || {};
    const user = await User.findOne({ email });
    if (!user) return res.status(404).json({ success: false, error: 'User not found' });

    function toNum(v) {
      if (v == null) return 0;
      if (typeof v === 'number') return v;
      const n = Number(v);
      return Number.isNaN(n) ? 0 : n;
    }

    user.balances = user.balances || {};
    user.balances.amountBorrowed = toNum(payload.amountBorrowed ?? payload.amount_borrowed ?? user.balances.amountBorrowed);
    user.balances.amountPaid = toNum(payload.amountPaid ?? payload.amount_paid ?? user.balances.amountPaid);
    user.balances.actualBalance = toNum(payload.actualBalance ?? payload.actual_balance ?? user.balances.actualBalance);
    user.balances.interestRate = toNum(payload.interestRate ?? payload.interest_rate ?? user.balances.interestRate);

    if (payload.next_payment && typeof payload.next_payment === 'object') {
      const np = {};
      if (payload.next_payment.amount != null) np.amount = toNum(payload.next_payment.amount);
      if (payload.next_payment.date) {
        const d = new Date(payload.next_payment.date);
        if (!isNaN(d.getTime())) np.date = d;
      }
      user.balances.next_payment = Object.keys(np).length ? np : user.balances.next_payment;
    }

    await user.save();
    return res.json({ success: true, message: 'Balances updated' });
  } catch (err) {
    console.error('POST /users/:email/balances error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});
usersRouter.post('/:email/notifications', authMiddleware, async (req, res) => {
  try {
    const email = req.params.email.toLowerCase().trim();
    const { title, message, type } = req.body || {};
    if (!title || !message) return res.status(400).json({ success: false, error: 'title and message are required' });

    const user = await User.findOne({ email });
    if (!user) return res.status(404).json({ success: false, error: 'User not found' });

    const n = {
      id: String(Date.now()),
      title,
      message,
      type: ['info','success','warning','error'].includes(type) ? type : 'info',
      ts: new Date()
    };

    user.notifications = user.notifications || [];
    user.notifications.unshift(n);
    if (user.notifications.length > 200) user.notifications = user.notifications.slice(0, 200);
    await user.save();

    return res.status(201).json({ success: true, message: 'Notification added', notification: n });
  } catch (err) {
    console.error('POST /users/:email/notifications error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

// Admin router
const adminRouter = express.Router();
adminRouter.post('/submissions', authMiddleware, async (req, res) => {
  try {
    const body = req.body || {};
    const from = (body.from || req.user?.email || 'unknown').toLowerCase();
    const now = new Date();

    const sub = new AdminSubmission({ from, ts: now, data: body });
    await sub.save();

    const adminUser = await User.findOne({ email: OVERALL_ADMIN_EMAIL });
    if (adminUser) {
      adminUser.notifications = adminUser.notifications || [];
      adminUser.notifications.unshift({
        id: String(Date.now()),
        title: 'New client submission',
        message: `Submission from ${from}`,
        type: 'info',
        ts: now
      });
      await adminUser.save();
    }

    return res.status(201).json({ success: true, message: 'Submission saved', id: sub._id.toString() });
  } catch (err) {
    console.error('POST /admin/submissions error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});
adminRouter.get('/submissions', authMiddleware, async (req, res) => {
  try {
    const items = await AdminSubmission.find().sort({ ts: -1 });
    return res.json(items);
  } catch (err) {
    console.error('GET /admin/submissions error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});
adminRouter.delete('/submissions/:id', authMiddleware, async (req, res) => {
  try {
    const id = req.params.id;
    const deleted = await AdminSubmission.findByIdAndDelete(id);
    if (!deleted) return res.status(404).json({ success: false, error: 'Not found' });
    return res.json({ success: true, message: 'Submission deleted', deletedId: deleted._id.toString() });
  } catch (err) {
    console.error('DELETE /admin/submissions/:id error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

// Reports router (create before defining handlers)
const reportsRouter = express.Router();

// === REPORTS ROUTES ===
// ZANACO endpoints
reportsRouter.get('/zanaco/distributions', async (req, res) => {
  try {
    const { date, branch, channel } = req.query;
    if (!date) return res.status(400).json({ success: false, error: 'date required' });

    const norm = normalizeToUtcDay(date);
    if (!norm) return res.status(400).json({ success: false, error: 'invalid date' });

    const q = { date: norm };
    if (branch) q.branch = String(branch).trim();
    if (channel) q.channel = String(channel).toLowerCase().trim();

    const docs = await ZanacoDistribution.find(q).lean();
    return res.json({ success: true, distributions: docs });
  } catch (err) {
    console.error('GET /zanaco/distributions error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

reportsRouter.get('/zanaco', async (req, res) => {
  try {
    const { date, branch, channel } = req.query;
    if (!date) return res.status(400).json({ success: false, error: 'date required' });
    const norm = normalizeToUtcDay(date);
    if (!norm) return res.status(400).json({ success: false, error: 'invalid date' });

    const q = { date: norm };
    if (branch) q.branch = String(branch).trim();
    if (channel) q.channel = String(channel).toLowerCase().trim();

    const docs = await ZanacoDistribution.find(q).lean();
    if (branch && channel) {
      return res.json({ success: true, amount: (docs[0] ? docs[0].amount : 0) });
    }
    return res.json({ success: true, distributions: docs });
  } catch (err) {
    console.error('GET /zanaco error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

reportsRouter.post('/zanaco', async (req, res) => {
  try {
    const { date, branch, channel, amount, metadata } = req.body || {};
    if (!date || !branch || !channel) return res.status(400).json({ success: false, error: 'date, branch and channel required' });
    const norm = normalizeToUtcDay(date);
    if (!norm) return res.status(400).json({ success: false, error: 'invalid date' });

    const filter = { date: norm, branch: String(branch).trim(), channel: String(channel).toLowerCase().trim() };
    const update = { $set: { date: norm, branch: filter.branch, channel: filter.channel, amount: Number(amount) || 0, metadata: metadata || {} } };
    const doc = await ZanacoDistribution.findOneAndUpdate(filter, update, { upsert: true, new: true, setDefaultsOnInsert: true });
    return res.json({ success: true, distribution: doc });
  } catch (err) {
    console.error('POST /zanaco error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

reportsRouter.post('/zanaco/bulk', async (req, res) => {
  try {
    const { date, fromBranch, allocations } = req.body || {};
    if (!date || !allocations || typeof allocations !== 'object') {
      return res.status(400).json({ success: false, error: 'date and allocations are required' });
    }
    const norm = normalizeToUtcDay(date);
    if (!norm) return res.status(400).json({ success: false, error: 'invalid date' });

    const ops = [];
    for (const [targetBranch, chMap] of Object.entries(allocations)) {
      if (!chMap || typeof chMap !== 'object') continue;
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
            metadata: { fromBranch: fromBranch || null }
          },
          $setOnInsert: { createdAt: new Date() }
        };
        ops.push({ updateOne: { filter, update, upsert: true } });
      }
    }

    if (ops.length === 0) return res.status(400).json({ success: false, error: 'no valid allocations provided' });

    let bulkRes;
    try {
      bulkRes = await ZanacoDistribution.bulkWrite(ops, { ordered: false });
    } catch (bulkErr) {
      console.error('zanaco bulkWrite error:', bulkErr);
    }

    return res.json({
      success: true,
      message: 'Zanaco allocations processed',
      bulkWriteResult: bulkRes ? {
        insertedCount: bulkRes.insertedCount || 0,
        matchedCount: bulkRes.matchedCount || 0,
        modifiedCount: bulkRes.modifiedCount || 0,
        upsertedCount: bulkRes.upsertedCount || 0,
        upsertedIds: bulkRes.upsertedIds || {}
      } : undefined
    });
  } catch (err) {
    console.error('POST /zanaco/bulk error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

// Daily/Monthly report endpoints (keeping your original logic)
reportsRouter.post('/sync_reports', async (req, res) => {
  try {
    const { reports } = req.body;
    if (!reports || !Array.isArray(reports)) {
      return res.status(400).json({ success: false, error: 'Invalid request: expected { reports: [...] }' });
    }

    const operations = [];
    const skipped = [];
    const errors = [];
    const canonicalTargets = [];

    for (const raw of reports) {
      try {
        if (!raw || typeof raw !== 'object') {
          skipped.push({ reason: 'invalid item (not object)', item: raw });
          continue;
        }

        const branch = raw.branch ? String(raw.branch).trim() : '';
        if (!branch) {
          skipped.push({ reason: 'missing branch', item: raw });
          continue;
        }

        const normalizedDate = normalizeToUtcDay(raw.date);
        if (!normalizedDate) {
          skipped.push({ reason: 'invalid date', item: raw });
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
          updatedAt: raw.updatedAt ? new Date(raw.updatedAt) : new Date()
        };

        operations.push({
          updateOne: {
            filter: { branch: branch, date: normalizedDate },
            update: { $set: updateData, $setOnInsert: { createdAt: new Date() } },
            upsert: true
          }
        });

        canonicalTargets.push({ branch, date: normalizedDate });
      } catch (inner) {
        console.error('prepare op error:', inner);
        errors.push({ item: raw, error: inner.message || String(inner) });
      }
    }

    if (operations.length === 0) {
      return res.json({ success: true, message: 'No valid reports to process', saved: [], skipped, errors });
    }

    let bulkResult;
    try {
      bulkResult = await DailyReport.bulkWrite(operations, { ordered: false });
    } catch (bulkErr) {
      console.error('bulkWrite error:', bulkErr);
      errors.push({ error: 'bulkWrite failed', detail: bulkErr.message || String(bulkErr) });
    }

    const orFilters = canonicalTargets.map(t => ({ branch: t.branch, date: t.date }));
    let savedDocs = [];
    if (orFilters.length > 0) {
      try {
        savedDocs = await DailyReport.find({ $or: orFilters }).select('branch date _id').lean();
      } catch (qerr) {
        console.error('Query after bulkWrite failed:', qerr);
        errors.push({ error: 'post-query failed', detail: qerr.message || String(qerr) });
      }
    }

    const saved = savedDocs.map(d => ({ branch: d.branch, date: new Date(d.date).toISOString(), id: d._id ? d._id.toString() : null }));

    return res.json({
      success: true,
      message: `${saved.length} reports processed (bulkWrite)`,
      saved,
      skipped,
      errors,
      bulkWriteResult: bulkResult ? {
        insertedCount: bulkResult.insertedCount || 0,
        matchedCount: bulkResult.matchedCount || 0,
        modifiedCount: bulkResult.modifiedCount || 0,
        upsertedCount: bulkResult.upsertedCount || 0,
        upsertedIds: bulkResult.upsertedIds || {}
      } : undefined
    });

  } catch (err) {
    console.error('POST /sync_reports catastrophic error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

reportsRouter.get('/reports', async (req, res) => {
  try {
    const reports = await DailyReport.find().sort({ date: -1 });
    return res.json(reports);
  } catch (err) {
    console.error('GET /reports error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});
reportsRouter.get('/reports/query', async (req, res) => {
  try {
    const { branch, date } = req.query;
    if (!branch || !date) return res.status(400).json({ success: false, error: 'branch and date required' });
    const norm = normalizeToUtcDay(date);
    if (!norm) return res.status(400).json({ success: false, error: 'invalid date' });
    const doc = await DailyReport.findOne({ branch: String(branch).trim(), date: norm }).lean();
    return res.json({ success: true, report: doc });
  } catch (err) {
    console.error('GET /reports/query error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});
reportsRouter.post('/report', async (req, res) => {
  try {
    const raw = req.body || {};
    const branch = raw.branch ? String(raw.branch).trim() : '';
    const dateNorm = normalizeToUtcDay(raw.date);
    if (!branch || !dateNorm) return res.status(400).json({ success: false, error: 'branch and valid date required' });

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
      updatedAt: raw.updatedAt ? new Date(raw.updatedAt) : new Date()
    };

    const doc = await DailyReport.findOneAndUpdate(
      { branch, date: dateNorm },
      { $set: updateData, $setOnInsert: { createdAt: new Date() } },
      { upsert: true, new: true }
    );

    return res.json({ success: true, report: doc });
  } catch (err) {
    console.error('POST /report error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});
reportsRouter.delete('/reports', async (req, res) => {
  try {
    const { branch, date } = req.body;
    if (!branch || !date) return res.status(400).json({ success: false, error: 'branch and date are required' });

    const parsed = new Date(date);
    if (isNaN(parsed.getTime())) return res.status(400).json({ success: false, error: 'invalid date format' });

    const startOfDay = new Date(Date.UTC(parsed.getUTCFullYear(), parsed.getUTCMonth(), parsed.getUTCDate(), 0, 0, 0));
    const endOfDay = new Date(startOfDay);
    endOfDay.setUTCDate(endOfDay.getUTCDate() + 1);

    const deleted = await DailyReport.findOneAndDelete({ branch: branch, date: { $gte: startOfDay, $lt: endOfDay } });
    if (!deleted) return res.status(404).json({ success: false, error: 'Report not found' });
    return res.json({ success: true, message: 'Report deleted', deletedId: deleted._id.toString() });
  } catch (err) {
    console.error('DELETE /reports error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});
reportsRouter.delete('/reports/:id', async (req, res) => {
  try {
    const id = req.params.id;
    const deleted = await DailyReport.findByIdAndDelete(id);
    if (!deleted) return res.status(404).json({ success: false, error: 'Not found' });
    return res.json({ success: true, message: 'Report deleted', deletedId: deleted._id.toString() });
  } catch (err) {
    console.error('DELETE /reports/:id error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

// Monthly report endpoints
reportsRouter.post('/sync_monthly_reports', async (req, res) => {
  try {
    const { monthlyReports } = req.body;
    if (!monthlyReports || !Array.isArray(monthlyReports)) {
      return res.status(400).json({ success: false, error: 'Invalid request: expected { monthlyReports: [...] }' });
    }

    const operations = [];
    const skipped = [];
    const errors = [];
    const canonicalTargets = [];

    for (const raw of monthlyReports) {
      try {
        if (!raw || typeof raw !== 'object') {
          skipped.push({ reason: 'invalid item (not object)', item: raw });
          continue;
        }

        const branch = raw.branch ? String(raw.branch).trim() : '';
        if (!branch) {
          skipped.push({ reason: 'missing branch', item: raw });
          continue;
        }

        const normalizedDate = normalizeToUtcMonthStart(raw.date);
        if (!normalizedDate) {
          skipped.push({ reason: 'invalid date', item: raw });
          continue;
        }

        const updateData = {
          branch,
          date: normalizedDate,
          expected: toNumber(raw.expected),
          inputs: Number.isInteger(raw.inputs) ? raw.inputs : (raw.inputs ? parseInt(raw.inputs, 10) || 0 : 0),
          collected: toNumber(raw.collected),
          collectedInput: Number.isInteger(raw.collectedInput) ? raw.collectedInput : (raw.collectedInput ? parseInt(raw.collectedInput, 10) || 0 : 0),
          totalUncollected: toNumber(raw.totalUncollected),
          uncollectedInput: Number.isInteger(raw.uncollectedInput) ? raw.uncollectedInput : (raw.uncollectedInput ? parseInt(raw.uncollectedInput, 10) || 0 : 0),
          insufficient: toNumber(raw.insufficient),
          insufficientInput: Number.isInteger(raw.insufficientInput) ? raw.insufficientInput : (raw.insufficientInput ? parseInt(raw.insufficientInput, 10) || 0 : 0),
          unreported: toNumber(raw.unreported),
          unreportedInput: Number.isInteger(raw.unreportedInput) ? raw.unreportedInput : (raw.unreportedInput ? parseInt(raw.unreportedInput, 10) || 0 : 0),
          lateCollection: toNumber(raw.lateCollection),
          uncollected: toNumber(raw.uncollected),
          permicExpectedNextMonth: toNumber(raw.permicExpectedNextMonth),
          totalInputs: Number.isInteger(raw.totalInputs) ? raw.totalInputs : (raw.totalInputs ? parseInt(raw.totalInputs, 10) || 0 : 0),
          oldInputsAmount: toNumber(raw.oldInputsAmount),
          oldInputsCount: Number.isInteger(raw.oldInputsCount) ? raw.oldInputsCount : (raw.oldInputsCount ? parseInt(raw.oldInputsCount, 10) || 0 : 0),
          newInputsAmount: toNumber(raw.newInputsAmount),
          newInputsCount: Number.isInteger(raw.newInputsCount) ? raw.newInputsCount : (raw.newInputsCount ? parseInt(raw.newInputsCount, 10) || 0 : 0),
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
          updatedAt: raw.updatedAt ? new Date(raw.updatedAt) : new Date()
        };

        operations.push({
          updateOne: {
            filter: { branch: branch, date: normalizedDate },
            update: { $set: updateData, $setOnInsert: { createdAt: new Date() } },
            upsert: true
          }
        });

        canonicalTargets.push({ branch, date: normalizedDate });
      } catch (inner) {
        console.error('prepare monthly op error:', inner);
        errors.push({ item: raw, error: inner.message || String(inner) });
      }
    }

    if (operations.length === 0) {
      return res.json({ success: true, message: 'No valid monthly reports to process', saved: [], skipped, errors });
    }

    let bulkResult;
    try {
      bulkResult = await MonthlyReport.bulkWrite(operations, { ordered: false });
    } catch (bulkErr) {
      console.error('monthly bulkWrite error:', bulkErr);
      errors.push({ error: 'bulkWrite failed', detail: bulkErr.message || String(bulkErr) });
    }

    const orFilters = canonicalTargets.map(t => ({ branch: t.branch, date: t.date }));
    let savedDocs = [];
    if (orFilters.length > 0) {
      try {
        savedDocs = await MonthlyReport.find({ $or: orFilters }).select('branch date _id').lean();
      } catch (qerr) {
        console.error('Query after monthly bulkWrite failed:', qerr);
        errors.push({ error: 'post-query failed', detail: qerr.message || String(qerr) });
      }
    }

    const saved = savedDocs.map(d => ({ branch: d.branch, date: new Date(d.date).toISOString(), id: d._id ? d._id.toString() : null }));

    return res.json({
      success: true,
      message: `${saved.length} monthly reports processed (bulkWrite)`,
      saved,
      skipped,
      errors,
      bulkWriteResult: bulkResult ? {
        insertedCount: bulkResult.insertedCount || 0,
        matchedCount: bulkResult.matchedCount || 0,
        modifiedCount: bulkResult.modifiedCount || 0,
        upsertedCount: bulkResult.upsertedCount || 0,
        upsertedIds: bulkResult.upsertedIds || {}
      } : undefined
    });

  } catch (err) {
    console.error('POST /sync_monthly_reports catastrophic error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});
reportsRouter.get('/monthly_reports', async (req, res) => {
  try {
    const reports = await MonthlyReport.find().sort({ date: -1 });
    return res.json(reports);
  } catch (err) {
    console.error('GET /monthly_reports error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});
reportsRouter.delete('/monthly_reports', async (req, res) => {
  try {
    const { branch, date } = req.body;
    if (!branch || !date) return res.status(400).json({ success: false, error: 'branch and date are required' });

    const parsed = new Date(date);
    if (isNaN(parsed.getTime())) return res.status(400).json({ success: false, error: 'invalid date format' });

    const startOfMonth = new Date(Date.UTC(parsed.getUTCFullYear(), parsed.getUTCMonth(), 1, 0, 0, 0));
    const startOfNextMonth = new Date(Date.UTC(parsed.getUTCFullYear(), parsed.getUTCMonth() + 1, 1, 0, 0, 0));

    const deleted = await MonthlyReport.findOneAndDelete({ branch: branch, date: { $gte: startOfMonth, $lt: startOfNextMonth } });
    if (!deleted) return res.status(404).json({ success: false, error: 'Monthly report not found' });
    return res.json({ success: true, message: 'Monthly report deleted', deletedId: deleted._id.toString() });
  } catch (err) {
    console.error('DELETE /monthly_reports error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});
reportsRouter.delete('/monthly_reports/:id', async (req, res) => {
  try {
    const id = req.params.id;
    const deleted = await MonthlyReport.findByIdAndDelete(id);
    if (!deleted) return res.status(404).json({ success: false, error: 'Not found' });
    return res.json({ success: true, message: 'Monthly report deleted', deletedId: deleted._id.toString() });
  } catch (err) {
    console.error('DELETE /monthly_reports/:id error:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error' });
  }
});

// --- Mount routers
app.use('/api/auth', authRouter);
app.use('/api/users', usersRouter);
app.use('/api/admin', adminRouter);
app.use('/api', reportsRouter); // provides /api/sync_reports, /api/reports, /api/zanaco, /api/sync_monthly_reports, /api/monthly_reports

// --- Loans router (added) ---
// Make sure you created models/Loan.js and routes/loans.js as discussed.
// This mounts the loans router at /api/loans  (routes/loans.js should export a router with path '/' handlers)
const loansRouter = require('./routes/loans');
app.use('/api/loans', loansRouter);

// Mount imports router AFTER models & other routers (avoids circular require)
const importsRouter = require('./routes/imports');
app.use('/api/imports', importsRouter);

// Health and root
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'OK',
    message: 'DAML Server is running',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development'
  });
});
app.get('/', (req, res) => {
  res.json({
    message: 'DAML Server API',
    version: '1.0.0',
    endpoints: { health: '/health', sync: '/api/sync_reports', reports: '/api/reports', zanaco: '/api/zanaco' }
  });
});

// Error handler
app.use((err, req, res, next) => {
  console.error('Server error:', err);
  res.status(500).json({
    success: false,
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'production' ? 'Something went wrong' : err.message
  });
});

// 404
app.use((req, res) => {
  res.status(404).json({ success: false, error: 'Endpoint not found', path: req.path });
});

// --- Connect to Mongo and start
mongoose.connect(mongoUri, { autoIndex: true })
  .then(() => console.log('✅ MongoDB connected successfully'))
  .catch(err => {
    console.error('❌ MongoDB connection error:', err.message);
    process.exit(1);
  });

const server = app.listen(PORT, () => {
  console.log(`🚀 DAML Server running on port ${PORT}`);
  console.log(`🌐 Environment: ${process.env.NODE_ENV || 'development'}`);
});

// Graceful shutdown
const shutdown = async (signal) => {
  console.log(`\nReceived ${signal}. Closing server...`);
  server.close(async () => {
    try {
      await mongoose.disconnect();
      console.log('MongoDB disconnected. Exiting.');
      process.exit(0);
    } catch (err) {
      console.error('Error during shutdown', err);
      process.exit(1);
    }
  });
};
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

// --- Seed dev admins if requested (safe dev convenience)
async function seedAdmins() {
  try {
    console.log('Seeding dev admin accounts...');
    const branchEmails = [
      'monze@directaccess.com',
      'mazabuka@directaccess.com',
      'lusaka@directaccess.com',
      'solwezi@directaccess.com',
      'lumezi@directaccess.com',
      'nakonde@directaccess.com',
    ];
    const overall = OVERALL_ADMIN_EMAIL;

    const ov = await User.findOne({ email: overall });
    if (!ov) {
      const u = new User({ email: overall, name: 'Overall Admin', role: 'ovadmin' });
      await u.setPassword('ovadmin');
      await u.save();
      console.log(`Created overall admin ${overall} / ovadmin`);
    } else {
      console.log(`Overall admin ${overall} already exists`);
    }

    for (const e of branchEmails) {
      const normalized = e.toLowerCase().trim();
      const u2 = await User.findOne({ email: normalized });
      if (!u2) {
        const b = new User({ email: normalized, name: 'Branch Admin', role: 'branch_admin' });
        await b.setPassword('admin');
        await b.save();
        console.log(`Created branch admin ${normalized} / admin`);
      } else {
        console.log(`Branch admin ${normalized} already exists`);
      }
    }

    console.log('Seeding finished.');
  } catch (err) {
    console.error('Seed failed', err);
  }
}

// Run seed if CLI arg present
if (process.argv.includes('--seed')) {
  // Delay until connected
  mongoose.connection.once('open', () => {
    seedAdmins().then(() => {
      console.log('Seed complete. Exiting.');
      process.exit(0);
    }).catch(err => {
      console.error('Seed error', err);
      process.exit(1);
    });
  });
}
