const express = require("express");
const Notification = require("../models/Notification");

const router = express.Router();

// GET unread notifications for user
router.get("/", async (req, res) => {
  try {
    const to = (req.query.to || "").toString().toLowerCase().trim();
    if (!to) return res.status(400).json({ success: false, message: "Missing ?to=email" });

    const items = await Notification.find({ toEmail: to, read: false })
      .sort({ createdAt: -1 })
      .limit(50)
      .lean();

    res.json({ success: true, data: items });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// POST create notification
router.post("/", async (req, res) => {
  try {
    const { toEmail, title, message, type, data } = req.body || {};
    if (!toEmail || !title || !message) {
      return res.status(400).json({ success: false, message: "toEmail, title, message required" });
    }

    const doc = await Notification.create({
      toEmail: toEmail.toLowerCase().trim(),
      title: String(title),
      message: String(message),
      type: (type || "info").toString(),
      data: data || {},
    });

    res.json({ success: true, data: doc });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// POST mark all as read
router.post("/mark-all-read", async (req, res) => {
  try {
    const { toEmail } = req.body || {};
    const to = (toEmail || "").toString().toLowerCase().trim();
    if (!to) return res.status(400).json({ success: false, message: "toEmail required" });

    await Notification.updateMany(
      { toEmail: to, read: false },
      { $set: { read: true, readAt: new Date() } }
    );

    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

module.exports = router;
