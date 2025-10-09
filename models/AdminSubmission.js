// models/AdminSubmission.js
const mongoose = require('mongoose');

const AdminSubmissionSchema = new mongoose.Schema({
  data: { type: mongoose.Schema.Types.Mixed, default: {} },
  createdBy: { type: String, default: '' }, // email
  createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('AdminSubmission', AdminSubmissionSchema);
