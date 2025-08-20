// models/BranchComment.js
const mongoose = require('mongoose');

const BranchCommentSchema = new mongoose.Schema({
  branchName: String,
  comments: [
    {
      author: String,
      comment: String,
      timestamp: Date
    }
  ],
  updatedAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('BranchComment', BranchCommentSchema);
