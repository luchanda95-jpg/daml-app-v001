// models/User.js
const mongoose = require('mongoose');

const NextPaymentSchema = new mongoose.Schema({
  amount: { type: Number, default: 0 },
  date: { type: Date, default: null },
}, { _id: false });

const BalanceSchema = new mongoose.Schema({
  amountBorrowed: { type: Number, default: 0 },
  amountPaid: { type: Number, default: 0 },
  actualBalance: { type: Number, default: 0 },
  interestRate: { type: Number, default: 0 },
  next_payment: { type: NextPaymentSchema, default: null },
}, { _id: false });

const NotificationSchema = new mongoose.Schema({
  title: String,
  message: String,
  type: { type: String, default: 'info' },
  ts: { type: Date, default: Date.now }
}, { timestamps: false });

const UserSchema = new mongoose.Schema({
  email: { type: String, required: true, unique: true, lowercase: true, trim: true },
  name: { type: String, default: '' },
  phone: { type: String, default: '' },
  role: { type: String, enum: ['client','branch_admin','ovadmin'], default: 'client' },
  passwordHash: { type: String, required: true },
  balances: { type: BalanceSchema, default: () => ({}) },
  notifications: { type: [NotificationSchema], default: [] }
}, { timestamps: true });

module.exports = mongoose.model('User', UserSchema);
