const csv = require('csv-parser');
const fs = require('fs');
const Loan = require('../models/Loan');
const DataCleaner = require('../utils/dataCleaner');

class CSVImportService {
  constructor() {
    this.processedCount = 0;
    this.errorCount = 0;
    this.batchSize = 100; // default
    this.stream = null;
  }

  async importFromFile(filePath, options = {}) {
    const { batchSize = 100, onProgress } = options;
    this.batchSize = batchSize;
    this.processedCount = 0;
    this.errorCount = 0;

    return new Promise((resolve, reject) => {
      const batch = [];
      const stream = fs.createReadStream(filePath).pipe(csv());
      this.stream = stream;

      stream.on('data', async (data) => {
        try {
          // Pause before processing heavy work
          stream.pause();

          const cleanedData = DataCleaner.cleanRow(data);
          const loanData = DataCleaner.mapToSchema(cleanedData);
          batch.push(loanData);

          // When reaching batch size, process
          if (batch.length >= this.batchSize) {
            const toProcess = batch.splice(0, batch.length);
            await this.processBatch(toProcess);
            if (onProgress) {
              onProgress({
                processed: this.processedCount,
                errors: this.errorCount
              });
            }
          }

          // Resume streaming
          stream.resume();
        } catch (error) {
          this.errorCount++;
          console.error('Error processing row:', error);
          // attempt to resume after error
          try { stream.resume(); } catch (_) {}
        }
      });

      stream.on('end', async () => {
        try {
          // Process any remaining records
          if (batch.length > 0) {
            const toProcess = batch.splice(0, batch.length);
            await this.processBatch(toProcess);
          }

          const result = {
            totalProcessed: this.processedCount,
            totalErrors: this.errorCount,
            success: this.errorCount === 0
          };

          console.log('CSV import completed:', result);
          resolve(result);
        } catch (err) {
          console.error('Error finishing import:', err);
          reject(err);
        }
      });

      stream.on('error', (error) => {
        console.error('CSV stream error:', error);
        reject(error);
      });
    });
  }

  async processBatch(batch) {
    if (!batch || batch.length === 0) return;
    try {
      // Use ordered:false to allow partial successes
      const result = await Loan.insertMany(batch, { ordered: false });
      const insertedCount = Array.isArray(result) ? result.length : 0;
      this.processedCount += insertedCount;
      console.log(`Processed batch of ${insertedCount} records. Total: ${this.processedCount}`);
    } catch (error) {
      // Handle partial failures
      const writeErrors = (error && (error.writeErrors || error.result?.writeErrors || [])) || [];
      const nInserted = (error && (error.result?.nInserted || 0)) || 0;

      this.errorCount += writeErrors.length;
      this.processedCount += nInserted;

      if (!writeErrors.length && !nInserted) {
        // Unexpected error: count whole batch as failed
        console.error('Batch insertion failed (entire batch):', error);
        this.errorCount += batch.length;
      } else {
        console.warn(`Partial batch insertion: ${nInserted} inserted, ${writeErrors.length} failed`);
      }
    }
  }

  async getImportStats() {
    const totalLoans = await Loan.countDocuments();
    const statusCounts = await Loan.aggregate([
      {
        $group: {
          _id: '$loanStatus',
          count: { $sum: 1 }
        }
      }
    ]);

    return {
      totalLoans,
      statusCounts
    };
  }
}

module.exports = CSVImportService;
