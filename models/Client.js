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

module.exports = mongoose.model("Client", ClientSchema);
