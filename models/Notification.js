const mongoose = require("mongoose");

const NotificationSchema = new mongoose.Schema(
  {
    toEmail: { type: String, required: true, lowercase: true, trim: true },
    title: { type: String, required: true, trim: true },
    message: { type: String, required: true, trim: true },
    type: { type: String, default: "info" }, // info | success | warning | error
    data: { type: Object, default: {} },     // optional extra payload
    read: { type: Boolean, default: false },
    readAt: { type: Date, default: null },
  },
  { timestamps: true }
);

module.exports = mongoose.model("Notification", NotificationSchema);
