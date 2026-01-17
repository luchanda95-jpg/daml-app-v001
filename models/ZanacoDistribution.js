// models/ZanacoDistribution.js
const mongoose = require('mongoose');
const { Schema } = mongoose;

/**
 * Zanaco distribution row:
 * - fromBranch: sender branch
 * - branch: receiving branch (kept name for compatibility)
 * - channel: airtel/mtn
 *
 * Unique on date + fromBranch + branch + channel (so different senders won't overwrite)
 */
const ZanacoDistributionSchema = new Schema(
  {
    date: { type: Date, required: true, index: true }, // normalized UTC midnight
    fromBranch: { type: String, required: true, trim: true, lowercase: true, index: true },
    branch: { type: String, required: true, trim: true, lowercase: true, index: true }, // receiver
    channel: { type: String, required: true, trim: true, lowercase: true, index: true },
    amount: { type: Number, required: true, default: 0 },
    metadata: { type: Schema.Types.Mixed, default: {} },
  },
  { timestamps: true, versionKey: false }
);

ZanacoDistributionSchema.index(
  { date: 1, fromBranch: 1, branch: 1, channel: 1 },
  { unique: true }
);

// Normalize date input to UTC midnight
function normalizeToUtcDay(dateInput) {
  const d = new Date(dateInput);
  if (isNaN(d.getTime())) return null;
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 0, 0, 0));
}

ZanacoDistributionSchema.pre('validate', function (next) {
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

module.exports = mongoose.model('ZanacoDistribution', ZanacoDistributionSchema);
