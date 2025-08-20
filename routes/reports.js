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

module.exports = router;