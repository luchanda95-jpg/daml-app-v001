const mongoose = require('mongoose');

const loanSchema = new mongoose.Schema({
    fullName: {
        type: String,
        required: true
    },
    borrowerLandline: String,
    borrowerMobile: String,
    loanStatus: {
        type: String,
        required: true,
        enum: ['Fully Paid', 'Restructured', 'Defaulted', 'Past Maturity', 'Missed Repayment', 'Write-Off']
    },
    principalAmount: {
        type: Number,
        required: true,
        min: 0
    },
    totalInterestBalance: {
        type: Number,
        default: 0
    },
    amortizationDue: {
        type: Number,
        default: 0
    },
    borrowerEmail: String,
    borrowerAddress: String,
    borrowerDateOfBirth: Date,
    nextInstallmentAmount: {
        type: Number,
        default: 0
    },
    nextDueDate: Date,
    penaltyAmount: {
        type: Number,
        default: 0
    },
    branchId: {
        type: String,
        default: '5235364' // From your CSV filename
    },
    importedAt: {
        type: Date,
        default: Date.now
    }
}, {
    timestamps: true
});

// Indexes for better query performance
loanSchema.index({ fullName: 1 });
loanSchema.index({ loanStatus: 1 });
loanSchema.index({ nextDueDate: 1 });
loanSchema.index({ branchId: 1 });

module.exports = mongoose.model('Loan', loanSchema);