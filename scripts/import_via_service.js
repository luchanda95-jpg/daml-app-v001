// scripts/import_via_service.js
require('dotenv').config();
const mongoose = require('mongoose');
const path = require('path');
const CSVImportService = require('../services/csvImportService');

async function main() {
  try {
    const mongoUri = process.env.MONGO_URI;
    if (!mongoUri) {
      console.error('MONGO_URI not set in .env');
      process.exit(1);
    }

    const fileArg = process.argv[2];
    if (!fileArg) {
      console.error('Usage: node scripts/import_via_service.js <path-to-csv>');
      process.exit(1);
    }
    const filePath = path.resolve(fileArg);
    console.log('Connecting to MongoDB...');
    await mongoose.connect(mongoUri, { autoIndex: true });

    console.log('Connected. Starting import for file:', filePath);
    const svc = new CSVImportService();

    const result = await svc.importFromFile(filePath, {
      batchSize: 200,
      onProgress: (p) => {
        console.log(`Progress: processed=${p.processed} errors=${p.errors}`);
      }
    });

    console.log('Import finished:', result);
    await mongoose.connection.close();
    process.exit(0);
  } catch (err) {
    console.error('Import failed:', err);
    try { await mongoose.connection.close(); } catch (_) {}
    process.exit(1);
  }
}

if (require.main === module) main();
