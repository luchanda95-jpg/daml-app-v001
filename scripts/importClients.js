require("dotenv").config();
const mongoose = require("mongoose");
const path = require("path");
const CSVImportService = require("../services/csvImportService");

async function importClients() {
  try {
    const mongoUri = process.env.MONGO_URI;
    if (!mongoUri) {
      console.error("❌ MONGO_URI not found in .env");
      process.exit(1);
    }

    const fileArg = process.argv[2] || "./data/loans.csv";
    const filePath = path.resolve(fileArg);

    console.log("📂 CSV file path:", filePath);
    console.log("🔗 Connecting to MongoDB...");

    await mongoose.connect(mongoUri);
    console.log("✅ Connected to MongoDB");

    const importService = new CSVImportService();

    console.log("🚀 Starting CLIENT import (dedupe + balance only)...");
    const result = await importService.importFromFile(filePath, {
      batchSize: 300,
      onProgress: (p) => console.log(`Progress: processed=${p.processed}, errors=${p.errors}`),
    });

    console.log("✅ Import completed:", result);

    const stats = await importService.getImportStats();
    console.log("📊 Final stats:", stats);
  } catch (error) {
    console.error("❌ Import failed:", error);
  } finally {
    await mongoose.disconnect();
    console.log("🔒 MongoDB connection closed");
  }
}

if (require.main === module) {
  importClients();
}

module.exports = importClients;
