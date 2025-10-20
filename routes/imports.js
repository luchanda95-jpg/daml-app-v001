const express = require('express');
const router = express.Router();
const CSVImportService = require('../services/csvImportService');
const { authMiddleware, requireRole } = require('../middleware/auth'); // use actual middleware functions

// Initialize service
const importService = new CSVImportService();

// @route   POST /api/imports/loans
// @desc    Import loans from CSV file
// @access  Private (Admin)
router.post('/loans', authMiddleware, requireRole('ovadmin', 'branch_admin'), async (req, res) => {
  try {
    // In a real implementation, you'd handle file upload
    // For now, we'll assume the file path is provided
    const { filePath } = req.body;

    if (!filePath) {
      return res.status(400).json({
        success: false,
        message: 'File path is required'
      });
    }

    const result = await importService.importFromFile(filePath, {
      batchSize: 100,
      onProgress: (progress) => {
        // Could use WebSockets for real-time progress updates
        console.log('Import progress:', progress);
      }
    });

    res.json({
      success: true,
      message: 'Import completed successfully',
      data: result
    });

  } catch (error) {
    console.error('Import error:', error);
    res.status(500).json({
      success: false,
      message: 'Import failed',
      error: error.message
    });
  }
});

// @route   GET /api/imports/stats
// @desc    Get import statistics
// @access  Private
router.get('/stats', authMiddleware, async (req, res) => {
  try {
    const stats = await importService.getImportStats();
    res.json({
      success: true,
      data: stats
    });
  } catch (error) {
    console.error('Stats error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get import statistics',
      error: error.message
    });
  }
});
console.log('[debug] loading middleware/auth.js');

module.exports = router;
