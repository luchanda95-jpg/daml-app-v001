require('dotenv').config();
const mongoose = require('mongoose');
const CSVImportService = require('../services/csvImportService');

async function importLoans() {
    try {
        // Connect to MongoDB using your existing config
        const db = require('../config/db');
        
        // Wait for connection
        await new Promise((resolve, reject) => {
            mongoose.connection.on('connected', resolve);
            mongoose.connection.on('error', reject);
        });
        
        console.log('Connected to MongoDB');
        
        const importService = new CSVImportService();
        const filePath = process.argv[2] || './data/loans_branch-5235364-13048837.csv';
        
        console.log('Starting CSV import from:', filePath);
        
        const result = await importService.importFromFile(filePath, {
            batchSize: 100,
            onProgress: (progress) => {
                console.log(`Progress: ${progress.processed} processed, ${progress.errors} errors`);
            }
        });
        
        console.log('Import completed:', result);
        
        // Get final statistics
        const stats = await importService.getImportStats();
        console.log('Final statistics:', stats);
        
    } catch (error) {
        console.error('Import failed:', error);
        process.exit(1);
    } finally {
        await mongoose.connection.close();
        console.log('MongoDB connection closed');
        process.exit(0);
    }
}

// Handle command line execution
if (require.main === module) {
    importLoans();
}

module.exports = importLoans;