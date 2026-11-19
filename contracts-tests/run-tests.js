// Runs every test file in its own Hardhat process. Several tests put real contracts at the fixed genesis addresses
// (0x1111..., 0x3333..., 0x6666...) and other tests put mocks at the same addresses; a fresh in-process network per file
// keeps leftover storage of one file from leaking into the next.
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const dir = path.join(__dirname, "test");
const files = fs.readdirSync(dir).filter((f) => f.endsWith(".test.js")).sort();
let failed = 0;
for (const f of files) {
  console.log("\n=== " + f + " ===");
  const r = spawnSync(process.platform === "win32" ? "npx.cmd" : "npx", ["hardhat", "test", path.join("test", f)], {
    cwd: __dirname,
    stdio: "inherit",
    shell: process.platform === "win32",
  });
  if (r.status !== 0) failed++;
}
console.log(failed ? "\n" + failed + " test file(s) FAILED" : "\nAll test files passed");
process.exit(failed ? 1 : 0);
