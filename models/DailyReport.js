// models/DailyReport.js
const mongoose = require('mongoose');
const { Schema } = mongoose;

/**
 * Normalize a date to UTC midnight for storage/unique indexing.
 * Accepts Date or date-string.
 */
function normalizeToUtcDay(dateInput) {
  const d = new Date(dateInput);
  if (isNaN(d.getTime())) return null;
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 0, 0, 0));
}

const DailyReportSchema = new Schema({
  branch: { type: String, required: true, trim: true, index: true },
  date: { type: Date, required: true, index: true }, // normalized to UTC midnight
  openingBalances: { type: Map, of: Number, default: {} },
  loanCounts: { type: Map, of: Number, default: {} },
  closingBalances: { type: Map, of: Number, default: {} },
  totalDisbursed: { type: Number, default: 0 },
  totalCollected: { type: Number, default: 0 },
  collectedForOtherBranches: { type: Number, default: 0 },
  pettyCash: { type: Number, default: 0 },
  expenses: { type: Number, default: 0 },

  // per-channel sentinel for Zanaco application, e.g. { 'airtel': true, 'mtn': true }
  zanacoApplied: { type: Map, of: Boolean, default: {} },

  synced: { type: Boolean, default: false },
  updatedAt: { type: Date, default: () => new Date() }
}, {
  timestamps: true,
  versionKey: false
});

// Unique index to ensure only one report per branch+day
DailyReportSchema.index({ branch: 1, date: 1 }, { unique: true });

DailyReportSchema.pre('validate', function(next) {
  if (this.date) {
    const normalized = normalizeToUtcDay(this.date);
    if (normalized) this.date = normalized;
  }
  this.updatedAt = new Date();
  next();
});

// Normalize date when findOneAndUpdate is used with $set.date
DailyReportSchema.pre('findOneAndUpdate', function(next) {
  const upd = this.getUpdate && this.getUpdate();
  if (upd && upd.$set && upd.$set.date) {
    const normalized = normalizeToUtcDay(upd.$set.date);
    if (normalized) this.getUpdate().$set.date = normalized;
  }
  if (upd) {
    this.getUpdate().$set = this.getUpdate().$set || {};
    this.getUpdate().$set.updatedAt = new Date();
  }
  next();
});

// Convert Map -> plain object for JSON output
DailyReportSchema.method('toJSON', function() {
  const obj = this.toObject({ getters: true, virtuals: false });
  function mapToObj(m) {
    if (!m) return {};
    if (m.constructor && m.constructor.name === 'Map') {
      return Object.fromEntries(m.entries());
    }
    return m;
  }
  obj.openingBalances = mapToObj(obj.openingBalances);
  obj.closingBalances = mapToObj(obj.closingBalances);
  obj.loanCounts = mapToObj(obj.loanCounts);
  obj.zanacoApplied = mapToObj(obj.zanacoApplied);
  if (obj.date) obj.date = new Date(obj.date).toISOString();
  if (obj.updatedAt) obj.updatedAt = new Date(obj.updatedAt).toISOString();
  if (obj.createdAt) obj.createdAt = new Date(obj.createdAt).toISOString();
  return obj;
});

// ---------- Statics ----------
DailyReportSchema.statics.findByBranchAndDate = async function(branch, dateInput) {
  const d = normalizeToUtcDay(dateInput);
  if (!d) return null;
  return this.findOne({ branch: String(branch).trim(), date: d }).lean();
};

DailyReportSchema.statics.upsertReport = async function(data) {
  if (!data || !data.branch || !data.date) throw new Error('branch and date required');
  const branch = String(data.branch).trim();
  const date = normalizeToUtcDay(data.date);
  const update = Object.assign({}, data, { branch, date, synced: true, updatedAt: new Date() });
  // Ensure map fields are objects, not Map for Mongo update
  if (!update.openingBalances) update.openingBalances = {};
  if (!update.closingBalances) update.closingBalances = {};
  if (!update.loanCounts) update.loanCounts = {};
  if (!update.zanacoApplied) update.zanacoApplied = {};
  return this.findOneAndUpdate(
    { branch, date },
    { $set: update, $setOnInsert: { createdAt: new Date() } },
    { upsert: true, new: true }
  );
};

module.exports = mongoose.model('DailyReport', DailyReportSchema);
