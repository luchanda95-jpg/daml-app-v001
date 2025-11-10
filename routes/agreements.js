// routes/agreements.js
const express = require('express');
const multer = require('multer');
const mongoose = require('mongoose');
const { GridFSBucket, ObjectId } = require('mongodb');

const storage = multer.memoryStorage();
const upload = multer({
  storage,
  limits: { fileSize: 100 * 1024 * 1024 }, // 100 MB - adjust as needed
  fileFilter: (req, file, cb) => {
    // allow only pdfs by extension/mimetype
    const isPdf = file.mimetype === 'application/pdf' || /\.pdf$/i.test(file.originalname);
    if (!isPdf) return cb(new Error('Only PDF files are allowed'));
    cb(null, true);
  }
});

// Agreement metadata model (simple)
const AgreementSchema = new mongoose.Schema({
  fileId: { type: mongoose.Schema.Types.ObjectId, required: true, index: true },
  filename: String,
  originalName: String,
  borrowerName: String,
  loanId: String,            // optional loan record id
  uploadedBy: String,        // user email or id from token
  contentType: String,
  metadata: { type: mongoose.Schema.Types.Mixed, default: {} }
}, { timestamps: true });

let Agreement;
try {
  Agreement = mongoose.model('Agreement');
} catch (e) {
  Agreement = mongoose.model('Agreement', AgreementSchema);
}

module.exports = function(authMiddleware) {
  const router = express.Router();

  // Lazy GridFS bucket init (uses same mongoose connection)
  let bucket;
  function getBucket() {
    if (!bucket) {
      if (!mongoose.connection.db) throw new Error('Mongo connection not ready');
      bucket = new GridFSBucket(mongoose.connection.db, { bucketName: 'agreements' });
    }
    return bucket;
  }

  // POST /upload  -> upload multipart form field 'file'
  // optional fields: borrowerName, loanId
  router.post('/upload', authMiddleware, upload.single('file'), async (req, res) => {
    try {
      if (!req.file) return res.status(400).json({ success: false, error: 'No file uploaded' });

      // Extra safety: check PDF header signature (%PDF)
      const buf = req.file.buffer;
      if (buf.length < 4 || buf.slice(0, 4).toString() !== '%PDF') {
        return res.status(400).json({ success: false, error: 'Uploaded file is not a valid PDF' });
      }

      // ensure GridFS is available
      if (!mongoose.connection.db) return res.status(503).json({ success: false, error: 'DB not ready' });
      const grid = getBucket();

      const originalName = req.file.originalname || `agreement_${Date.now()}.pdf`;
      const metadata = {
        uploadedBy: req.user?.email || req.user?.id || 'unknown',
        borrowerName: req.body.borrowerName || null,
        loanId: req.body.loanId || null,
        originalName,
        uploadedAt: new Date()
      };

      // write to GridFS as a single operation
      const uploadStream = grid.openUploadStream(originalName, {
        contentType: req.file.mimetype || 'application/pdf',
        metadata
      });

      // wrap in Promise to await finish or error
      const fileDoc = await new Promise((resolve, reject) => {
        uploadStream.on('finish', resolve);
        uploadStream.on('error', reject);
        uploadStream.end(req.file.buffer);
      });

      // save metadata document
      const ag = new Agreement({
        fileId: fileDoc._id,
        filename: fileDoc.filename,
        originalName,
        borrowerName: metadata.borrowerName,
        loanId: metadata.loanId,
        uploadedBy: metadata.uploadedBy,
        contentType: fileDoc.contentType,
        metadata
      });

      await ag.save();

      // If you want: if loanId provided, attach agreement id into Loan model here (optional)
      // const Loan = require('../models/Loan'); // uncomment if you have a Loan model
      // if (metadata.loanId) await Loan.findByIdAndUpdate(metadata.loanId, { $push: { agreements: ag._id } });

      return res.status(201).json({
        success: true,
        message: 'File uploaded to GridFS',
        fileId: fileDoc._id.toString(),
        agreementId: ag._id.toString(),
        filename: fileDoc.filename,
        metadata: ag.metadata
      });
    } catch (err) {
      console.error('POST /agreements/upload error:', err);
      return res.status(500).json({ success: false, error: err.message || 'Upload failed' });
    }
  });

  // GET /file/:fileId  -> stream raw file by GridFS file id
  router.get('/file/:fileId', authMiddleware, async (req, res) => {
    try {
      const { fileId } = req.params;
      if (!ObjectId.isValid(fileId)) return res.status(400).json({ success: false, error: 'Invalid file id' });
      const _id = new ObjectId(fileId);

      if (!mongoose.connection.db) return res.status(503).json({ success: false, error: 'DB not ready' });
      const filesColl = mongoose.connection.db.collection('agreements.files');
      const fileDoc = await filesColl.findOne({ _id });
      if (!fileDoc) return res.status(404).json({ success: false, error: 'File not found' });

      res.setHeader('Content-Type', fileDoc.contentType || 'application/pdf');
      res.setHeader('Content-Disposition', `attachment; filename="${fileDoc.filename}"`);
      const grid = getBucket();
      const downloadStream = grid.openDownloadStream(_id);
      downloadStream.on('error', (e) => {
        console.error('GridFS download error', e);
        return res.status(500).end();
      });
      downloadStream.pipe(res);
    } catch (err) {
      console.error('GET /agreements/file error:', err);
      return res.status(500).json({ success: false, error: err.message || 'Download failed' });
    }
  });

  // GET /agreement/:id -> returns agreement metadata (not file contents)
  router.get('/agreement/:id', authMiddleware, async (req, res) => {
    try {
      const id = req.params.id;
      if (!ObjectId.isValid(id)) return res.status(400).json({ success: false, error: 'Invalid id' });
      const ag = await Agreement.findById(id).lean();
      if (!ag) return res.status(404).json({ success: false, error: 'Agreement not found' });
      return res.json({ success: true, agreement: ag });
    } catch (err) {
      console.error('GET /agreements/agreement/:id error:', err);
      return res.status(500).json({ success: false, error: err.message || 'Server error' });
    }
  });

  // GET /by-loan/:loanId -> list agreements for a loan id
  router.get('/by-loan/:loanId', authMiddleware, async (req, res) => {
    try {
      const { loanId } = req.params;
      const docs = await Agreement.find({ loanId }).sort({ createdAt: -1 }).lean();
      return res.json({ success: true, agreements: docs });
    } catch (err) {
      console.error('GET /agreements/by-loan error:', err);
      return res.status(500).json({ success: false, error: err.message || 'Server error' });
    }
  });

  // optional: DELETE /:id to remove both metadata and gridfs file
  router.delete('/:id', authMiddleware, async (req, res) => {
    try {
      const id = req.params.id;
      if (!ObjectId.isValid(id)) return res.status(400).json({ success: false, error: 'Invalid id' });
      const ag = await Agreement.findById(id);
      if (!ag) return res.status(404).json({ success: false, error: 'Agreement not found' });

      // remove GridFS file
      const grid = getBucket();
      await grid.delete(ag.fileId);

      // remove metadata doc
      await ag.remove();
      return res.json({ success: true, message: 'Agreement deleted' });
    } catch (err) {
      console.error('DELETE /agreements/:id error:', err);
      return res.status(500).json({ success: false, error: err.message || 'Delete failed' });
    }
  });

  return router;
};
