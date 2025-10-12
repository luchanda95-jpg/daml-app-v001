// models/MonthlyReport.js
const mongoose = require('mongoose');
const { Schema } = mongoose;

/**
 * Normalize date to UTC month start (YYYY-MM-01T00:00:00Z)
 */
function normalizeToUtcMonthStart(dateInput) {
  const d = new Date(dateInput);
  if (isNaN(d.getTime())) return null;
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1, 0, 0, 0));
}

const MonthlyReportSchema = new Schema({
  branch: { type: String, required: true, trim: true, index: true },
  date: { type: Date, required: true, index: true }, // normalized month start
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

MonthlyReportSchema.pre('validate', function(next) {
  if (this.date) {
    const normalized = normalizeToUtcMonthStart(this.date);
    if (normalized) this.date = normalized;
  }
  this.updatedAt = new Date();
  next();
});

MonthlyReportSchema.pre('findOneAndUpdate', function(next) {
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

MonthlyReportSchema.method('toJSON', function() {
  const obj = this.toObject({ getters: true, virtuals: false });
  if (obj.date) obj.date = new Date(obj.date).toISOString();
  if (obj.updatedAt) obj.updatedAt = new Date(obj.updatedAt).toISOString();
  if (obj.createdAt) obj.createdAt = new Date(obj.createdAt).toISOString();
  return obj;
});

module.exports = mongoose.model('MonthlyReport', MonthlyReportSchema);
