const express = require('express');
const router = express.Router();
const DailyReport = require('../models/DailyReport');

// Sync reports from Flutter
router.post('/sync_reports', async (req, res) => {
  try {
    const { reports } = req.body;
    
    if (!reports || !Array.isArray(reports)) {
      return res.status(400).json({ 
        success: false, 
        error: 'Invalid request format. Expected an array of reports.' 
      });
    }

    const results = [];
    
    for (let r of reports) {
      // Validate required fields
      if (!r.branch || !r.date) continue;

      const filter = { 
        branch: r.branch, 
        date: new Date(r.date) 
      };
      
      const update = {
        ...r,
        date: new Date(r.date),
        updatedAt: r.updatedAt ? new Date(r.updatedAt) : new Date()
      };
      
      const options = { 
        upsert: true, 
        new: true 
      };
      
      const result = await DailyReport.findOneAndUpdate(filter, update, options);
      results.push(result);
    }
    
    res.json({ 
      success: true, 
      message: `${results.length} reports synced successfully`,
      syncedCount: results.length
    });
  } catch (err) {
    console.error("Sync error:", err);
    res.status(500).json({ 
      success: false, 
      error: err.message 
    });
  }
});

// Get all reports
router.get('/reports', async (req, res) => {
  try {
    const reports = await DailyReport.find().sort({ date: -1 });
    res.json(reports);
  } catch (err) {
    res.status(500).json({ 
      success: false, 
      error: err.message 
    });
  }
});

/**
 * DELETE /api/reports
 * Body: { branch: string, date: string (ISO) }
 * Deletes the report for the given branch on the given day (day-range match).
 */
router.delete('/reports', async (req, res) => {
  try {
    const { branch, date } = req.body;
    if (!branch || !date) {
      return res.status(400).json({ success: false, error: 'branch and date are required' });
    }

    const parsed = new Date(date);
    if (isNaN(parsed.getTime())) {
      return res.status(400).json({ success: false, error: 'invalid date format' });
    }

    // Use day-range to match report regardless of stored time-of-day
    const startOfDay = new Date(Date.UTC(parsed.getUTCFullYear(), parsed.getUTCMonth(), parsed.getUTCDate(), 0, 0, 0));
    const endOfDay = new Date(startOfDay);
    endOfDay.setUTCDate(endOfDay.getUTCDate() + 1);

    const deleted = await DailyReport.findOneAndDelete({
      branch: branch,
      date: { $gte: startOfDay, $lt: endOfDay }
    });

    if (!deleted) {
      return res.status(404).json({ success: false, error: 'Report not found' });
    }

    return res.json({ success: true, message: 'Report deleted', deletedId: deleted._id });
  } catch (err) {
    console.error('DELETE /reports error:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * DELETE /api/reports/:id
 * Deletes by Mongo _id
 */
router.delete('/reports/:id', async (req, res) => {
  try {
    const id = req.params.id;
    const deleted = await DailyReport.findByIdAndDelete(id);
    if (!deleted) return res.status(404).json({ success: false, error: 'Not found' });
    return res.json({ success: true, message: 'Report deleted', deletedId: deleted._id });
  } catch (err) {
    console.error('DELETE /reports/:id error:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
