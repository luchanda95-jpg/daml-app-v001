require("dotenv").config();
const importClients = require("./importClients");

(async () => {
  const files = [
    "data/loans_branch-5235364-13048837.csv",
    "data/loans_branch-5729779-13768000.csv",
    "data/loans_branch-5734839-13795300.csv",
  ];

  for (const f of files) {
    console.log("\n==============================");
    console.log("IMPORTING:", f);
    console.log("==============================\n");
    process.argv[2] = f; // reuse same script argument style
    await importClients();
  }
})();
