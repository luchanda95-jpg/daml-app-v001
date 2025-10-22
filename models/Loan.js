// models/Loan.js
const mongoose = require('mongoose');

const loanSchema = new mongoose.Schema({
  fullName: {
    type: String,
    required: true,
    trim: true,
    index: true
  },

  borrowerLandline: {
    type: String,
    default: ''
  },

  borrowerMobile: {
    type: String,
    default: '',
    index: true
  },

  borrowerEmail: {
    type: String,
    default: '',
    lowercase: true,
    trim: true,
    index: true
  },

  borrowerAddress: {
    type: String,
    default: ''
  },

  borrowerDateOfBirth: {
    type: Date,
    default: null
  },

  loanStatus: {
    type: String,
    required: true,
    enum: ['Fully Paid', 'Restructured', 'Defaulted', 'Past Maturity', 'Missed Repayment', 'Write-Off'],
    index: true
  },

  principalAmount: {
    type: Number,
    required: true,
    min: 0,
    default: 0
  },

  totalInterestBalance: {
    type: Number,
    default: 0
  },

  amortizationDue: {
    type: Number,
    default: 0
  },

  nextInstallmentAmount: {
    type: Number,
    default: 0
  },

  nextDueDate: {
    type: Date,
    default: null,
    index: true
  },

  penaltyAmount: {
    type: Number,
    default: 0
  },

  branchId: {
    type: String,
    default: '5235364',
    index: true
  },

  importedAt: {
    type: Date,
    default: Date.now
  }

}, {
  timestamps: true,
  toJSON: {
    virtuals: true,
    transform(doc, ret) {
      if (ret._id) {
        try { ret._id = String(ret._id); } catch (e) {}
        ret.id = ret.id || ret._id;
      }
      const dateFields = ['importedAt', 'borrowerDateOfBirth', 'nextDueDate', 'createdAt', 'updatedAt'];
      for (const f of dateFields) {
        if (ret[f] instanceof Date && !Number.isNaN(ret[f].getTime())) {
          ret[f] = ret[f].toISOString();
        } else if (ret[f] == null) {
          ret[f] = null;
        }
      }
      delete ret.__v;
      return ret;
    }
  }
});

// small pre-save normalization
loanSchema.pre('save', function(next) {
  if (this.fullName && typeof this.fullName === 'string') {
    this.fullName = this.fullName.trim();
  }
  if (this.borrowerEmail && typeof this.borrowerEmail === 'string') {
    this.borrowerEmail = this.borrowerEmail.toLowerCase().trim();
  }
  next();
});

module.exports = mongoose.model('Loan', loanSchema);
