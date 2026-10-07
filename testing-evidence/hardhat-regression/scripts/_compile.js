// Compiles a contract from the Plan's contracts/ folder with the project's compiler settings (solc 0.8.24, optimizer 200, no viaIR),
// so the tests always run against the current source files instead of a stored artifact.
const fs = require("fs"), path = require("path"), solc = require("solc");
const CONTRACTS = path.resolve(__dirname, "../../../contracts");
const read = p => ({ contents: fs.readFileSync(path.join(CONTRACTS, p.replace("./", "")), "utf8") });
module.exports.compile = function (file, name) {
  const input = { language: "Solidity", sources: { [file]: { content: read(file).contents } }, settings: { optimizer: { enabled: true, runs: 200 }, outputSelection: { "*": { "*": ["abi", "evm.bytecode.object", "storageLayout"] } } } };
  const out = JSON.parse(solc.compile(JSON.stringify(input), { import: p => { try { return read(p); } catch (e) { return { error: "not found: " + p }; } } }));
  const errs = (out.errors || []).filter(e => e.severity === "error");
  if (errs.length) throw new Error(errs[0].formattedMessage);
  const c = out.contracts[file][name];
  return { abi: c.abi, bytecode: "0x" + c.evm.bytecode.object, layout: c.storageLayout };
};
