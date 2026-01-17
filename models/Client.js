// models/Client.js
const mongoose = require("mongoose");

const ClientSchema = new mongoose.Schema(
  {
    clientKey: { type: String, required: true, unique: true, index: true },

    fullName: { type: String, default: "" },
    phone: { type: String, default: null },
    email: { type: String, default: null },
    address: { type: String, default: null },
    dateOfBirth: { type: Date, default: null },

    loanStatus: { type: String, default: "Unknown" },
    statusBucket: { type: String, enum: ["balance", "cleared", "extended"], default: "balance" },
    isExtended: { type: Boolean, default: false },

    // the only thing you really care about for login display
    balance: { type: Number, default: 0 },

    // used to decide “latest row wins”
    statementDate: { type: Date, default: null },

    lastImportedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

// Helpful indexes
ClientSchema.index({ email: 1 });
ClientSchema.index({ phone: 1 });
ClientSchema.index({ updatedAt: -1 });
ClientSchema.index({ statementDate: -1 });
ClientSchema.index({ lastImportedAt: -1 });

module.exports = mongoose.model("Client", ClientSchema);
