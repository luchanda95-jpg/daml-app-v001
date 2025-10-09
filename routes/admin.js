// routes/admin.js
const express = require('express');
const AdminSubmission = require('../models/AdminSubmission');
const { authMiddleware, requireRole } = require('../middleware/auth');

const router = express.Router();

// Only ovadmin and branch_admin may use admin endpoints
router.use(authMiddleware);
router.use(requireRole('ovadmin', 'branch_admin'));

router.get('/submissions', async (req, res) => {
  try {
    const list = await AdminSubmission.find().sort({ createdAt: -1 }).limit(200);
    return res.json(list);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: 'Server error' });
  }
});

router.post('/submissions', async (req, res) => {
  try {
    const submission = new AdminSubmission({
      data: req.body,
      createdBy: req.user.email
    });
    await submission.save();
    return res.status(201).json(submission);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: 'Server error' });
  }
});

router.delete('/submissions/:id', async (req, res) => {
  try {
    const id = req.params.id;
    await AdminSubmission.findByIdAndDelete(id);
    return res.json({ message: 'deleted' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;
