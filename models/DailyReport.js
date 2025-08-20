const mongoose = require('mongoose');

const DailyReportSchema = new mongoose.Schema({
  branch: { 
    type: String, 
    required: true,
    trim: true
  },
  date: { 
    type: Date, 
    required: true 
  },
  openingBalances: { 
    type: Map, 
    of: Number,
    default: {}
  },
  loanCounts: { 
    type: Map, 
    of: Number,
    default: {}
  },
  closingBalances: { 
    type: Map, 
    of: Number,
    default: {}
  },
  totalDisbursed: { 
    type: Number, 
    default: 0 
  },
  totalCollected: { 
    type: Number, 
    default: 0 
  },
  collectedForOtherBranches: { 
    type: Number, 
    default: 0 
  },
  pettyCash: { 
    type: Number, 
    default: 0 
  },
  expenses: { 
    type: Number, 
    default: 0 
  },
  synced: { 
    type: Boolean, 
    default: false 
  },
  updatedAt: { 
    type: Date, 
    default: Date.now 
  },
}, {
  timestamps: true // Adds createdAt and updatedAt automatically
});

// Compound index to ensure uniqueness of branch+date combination
DailyReportSchema.index({ branch: 1, date: 1 }, { unique: true });

module.exports = mongoose.model('DailyReport', DailyReportSchema);