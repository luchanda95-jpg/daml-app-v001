const csv = require("csv-parser");
const fs = require("fs");
const Client = require("../models/Client");
const DataCleaner = require("../utils/dataCleaner");

class CSVImportService {
  constructor() {
    this.processedCount = 0;
    this.errorCount = 0;
    this.batchSize = 100;
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

      stream.on("data", async (data) => {
        try {
          stream.pause();

          const cleaned = DataCleaner.cleanRow(data);
          const clientData = DataCleaner.mapToClientSchema(cleaned);
          batch.push(clientData);

          if (batch.length >= this.batchSize) {
            const toProcess = batch.splice(0, batch.length);
            await this.processBatch(toProcess);

            onProgress?.({
              processed: this.processedCount,
              errors: this.errorCount,
            });
          }

          stream.resume();
        } catch (error) {
          this.errorCount++;
          console.error("Error processing row:", error);
          try { stream.resume(); } catch (_) {}
        }
      });

      stream.on("end", async () => {
        try {
          if (batch.length > 0) {
            const toProcess = batch.splice(0, batch.length);
            await this.processBatch(toProcess);
          }

          resolve({
            totalProcessed: this.processedCount,
            totalErrors: this.errorCount,
            success: this.errorCount === 0,
          });
        } catch (err) {
          reject(err);
        }
      });

      stream.on("error", reject);
    });
  }

  dedupeByClientKey(records) {
    // Keep the “best/latest” record per clientKey within this batch
    const map = new Map();

    for (const r of records) {
      if (!r?.clientKey) continue;

      const current = map.get(r.clientKey);
      const rDate = r.statementDate ? new Date(r.statementDate).getTime() : 0;
      const cDate = current?.statementDate ? new Date(current.statementDate).getTime() : 0;

      // latest statementDate wins; if equal, higher balance wins
      if (!current || rDate > cDate || (rDate === cDate && (r.balance || 0) > (current.balance || 0))) {
        map.set(r.clientKey, r);
      }
    }

    return Array.from(map.values());
  }

  buildUpsertOp(incoming) {
    const incomingDate = incoming.statementDate ? new Date(incoming.statementDate) : new Date(0);
    const importedAt = new Date();

    // Pipeline update lets us compare to existing statementDate
    return {
      updateOne: {
        filter: { clientKey: incoming.clientKey },
        upsert: true,
        update: [
          { $set: { _incoming: incoming, _incomingDate: incomingDate, _importedAt: importedAt } },
          { $set: { _prevDate: { $ifNull: ["$statementDate", new Date(0)] } } },
          { $set: { _needsUpdate: { $gt: ["$_incomingDate", "$_prevDate"] } } },

          {
            $set: {
              clientKey: "$_incoming.clientKey",

              // Only overwrite fields if the incoming row is newer;
              // otherwise keep existing (but still fill nulls).
              fullName: {
                $cond: ["$_needsUpdate", "$_incoming.fullName", { $ifNull: ["$fullName", "$_incoming.fullName"] }],
              },
              phone: {
                $cond: ["$_needsUpdate", "$_incoming.phone", { $ifNull: ["$phone", "$_incoming.phone"] }],
              },
              email: {
                $cond: ["$_needsUpdate", "$_incoming.email", { $ifNull: ["$email", "$_incoming.email"] }],
              },
              address: {
                $cond: ["$_needsUpdate", "$_incoming.address", { $ifNull: ["$address", "$_incoming.address"] }],
              },
              dateOfBirth: {
                $cond: ["$_needsUpdate", "$_incoming.dateOfBirth", { $ifNull: ["$dateOfBirth", "$_incoming.dateOfBirth"] }],
              },

              loanStatus: { $cond: ["$_needsUpdate", "$_incoming.loanStatus", "$loanStatus"] },
              statusBucket: { $cond: ["$_needsUpdate", "$_incoming.statusBucket", "$statusBucket"] },
              isExtended: { $cond: ["$_needsUpdate", "$_incoming.isExtended", "$isExtended"] },
              balance: { $cond: ["$_needsUpdate", "$_incoming.balance", "$balance"] },

              statementDate: { $cond: ["$_needsUpdate", "$_incomingDate", "$_prevDate"] },

              // Always bump lastImportedAt even if row was older
              lastImportedAt: "$_importedAt",
            },
          },

          { $unset: ["_incoming", "_incomingDate", "_prevDate", "_needsUpdate", "_importedAt"] },
        ],
      },
    };
  }

  async processBatch(batch) {
    if (!batch?.length) return;

    const deduped = this.dedupeByClientKey(batch);
    const ops = deduped.map((r) => this.buildUpsertOp(r));

    try {
      const res = await Client.bulkWrite(ops, { ordered: false });
      // bulkWrite counts vary by Mongo version; use best approximation
      const changed =
        (res.upsertedCount || 0) +
        (res.modifiedCount || 0) +
        (res.matchedCount || 0);

      this.processedCount += changed;
      console.log(`Processed batch ops=${ops.length}, affected≈${changed}`);
    } catch (error) {
      this.errorCount += ops.length;
      console.error("Bulk upsert failed:", error);
    }
  }

  async getImportStats() {
    const totalClients = await Client.countDocuments();
    const bucketCounts = await Client.aggregate([
      { $group: { _id: "$statusBucket", count: { $sum: 1 } } },
    ]);

    return { totalClients, bucketCounts };
  }
}

module.exports = CSVImportService;
