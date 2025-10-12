// models/Comment.js
const mongoose = require('mongoose');

const CommentSchema = new mongoose.Schema({
  branch: { type: String, required: true, trim: true },
  text: { type: String, required: true },
  author: { type: String, default: 'user' },
  meta: { type: mongoose.Schema.Types.Mixed }
}, { timestamps: true });

module.exports = mongoose.model('Comment', CommentSchema);
