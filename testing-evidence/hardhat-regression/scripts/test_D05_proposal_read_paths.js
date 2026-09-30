// D05 (audit 2026-09-30) — proposal read paths, tested on the REAL contracts (Hardhat, not Besu).
// State is produced by the project's own genesis seed helpers (addresses substituted with test signers; layout untouched),
// then the helper's code is replaced with the real runtime, so the real contract runs on real seeded storage.
// Usage: CONTRACTS_DIR=<contracts or contracts-fa> npx hardhat run scripts/test_D05_proposal_read_paths.js
//   FoundationDAO: getProposal() must be unchanged; getProposalMeta() must return description, the quorum snapshotted
//                  at creation, createdAt and expiresAt — and the snapshot must NOT follow later membership changes.
//   ValidatorsRegistry: the auto-generated paramProposals(id) getter must expose requiredVotes/createdAt/expiresAt.
const hre = require("hardhat"); const fs = require("fs"); const path = require("path"); const solc = require(process.env.SOLC_PATH || "solc");
const DIR = process.env.CONTRACTS_DIR || "../../contracts";
let results = [];
function ok(n, c, x = "") { results.push(c === true); console.log((c === true ? "✅ " : "❌ ") + n + (c === true ? "" : " → " + c) + (x ? "  " + x : "")); }
function compile(files) {
  const sources = {}; for (const [k, v] of Object.entries(files)) sources[k] = { content: v };
  const out = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources, settings: { optimizer: { enabled: true, runs: 200 }, outputSelection: { "*": { "*": ["abi", "evm.bytecode.object", "evm.deployedBytecode.object"] } } } }),
    { import: p => { const f = path.join(DIR, path.basename(p)); return fs.existsSync(f) ? { contents: fs.readFileSync(f, "utf8") } : { error: "not found " + p }; } }));
  const errs = (out.errors || []).filter(e => e.severity === "error"); if (errs.length) throw new Error(errs.map(e => e.formattedMessage).join("\n"));
  return out.contracts;
}
async function realOnSeed(helperSrc, helperName, realSrc, realName, deployer) {
  const c = compile({ "H.sol": helperSrc, [realName + ".sol"]: realSrc });
  const h = c["H.sol"][helperName], r = c[realName + ".sol"][realName];
  const inst = await new hre.ethers.ContractFactory(h.abi, "0x" + h.evm.bytecode.object, deployer).deploy(); await inst.waitForDeployment();
  const addr = await inst.getAddress();
  await hre.network.provider.send("hardhat_setCode", [addr, "0x" + r.evm.deployedBytecode.object]); // real runtime, seeded storage
  return { addr, abi: r.abi };
}
(async () => {
  const s = await hre.ethers.getSigners(); const deployer = s[0];
  console.log(`source dir: ${DIR}  solc ${solc.version()}`);

  // ---------------- FoundationDAO ----------------
  let helper = fs.readFileSync(path.join(DIR, "genesis-seed-helpers/FoundationDAO_GenesisSeed.sol"), "utf8");
  // one pattern for every array entry: optional trailing comma and any spacing before the comment (last entry has no comma)
  let i = 0; helper = helper.replace(/address\(0\)(,?)(\s*)\/\/ /g, (_, c, sp) => s[1 + i++].address + c + sp + "// ");
  const members = s.slice(1, 16);
  ok("F0) helper patched with 15 distinct test-signer members", i === 15);
  const F = await realOnSeed(helper, "FoundationDAO_GenesisSeed", fs.readFileSync(path.join(DIR, "FoundationDAO.sol"), "utf8"), "FoundationDAO", deployer);
  const dao = (w) => new hre.ethers.Contract(F.addr, F.abi, w);
  const gp = F.abi.find(x => x.name === "getProposal"), gm = F.abi.find(x => x.name === "getProposalMeta");
  ok("F1) getProposal() ABI unchanged (9 outputs, same order)", gp && gp.outputs.map(o => o.name).join(",") === "pType,proposer,newMemberName,targetAccount,amount,tokenAddress,data,votes,status");
  ok("F2) getProposalMeta() exists: description, requiredVotes, createdAt, expiresAt", gm && gm.outputs.map(o => o.name + ":" + o.type).join(",") === "description:string,requiredVotes:uint256,createdAt:uint256,expiresAt:uint256");
  ok("F3) proposals mapping is NOT publicly readable (no auto getter) — hence the new getter", !F.abi.find(x => x.name === "proposals"));
  ok("F4) memberList seeded: 15 members", (await dao(deployer).isMember(members[14].address)) === true);
  const PT = Object.fromEntries(["AddMember","RemoveMember","SendETH","SendERC20","Execute"].map((n, k) => [n, k]));
  const rc = await (await dao(members[0]).proposeSendETH("fund workshop #1", members[0].address, 1)).wait();
  const id = await dao(deployer).proposalCount(); const blk = await hre.ethers.provider.getBlock(rc.blockNumber);
  const m1 = await dao(deployer).getProposalMeta(id); const reqNow15 = await dao(deployer).requiredVotesNow(PT.SendETH);
  ok("F5) description returned exactly", m1.description === "fund workshop #1", m1.description);
  ok("F6) requiredVotes snapshot = requiredVotesNow at creation (15 members, simple majority)", m1.requiredVotes === reqNow15, `${m1.requiredVotes} vs ${reqNow15}`);
  ok("F7) createdAt = creation block timestamp; expiresAt = createdAt + PROPOSAL_EXPIRY", m1.createdAt === BigInt(blk.timestamp) && m1.expiresAt === m1.createdAt + (await dao(deployer).PROPOSAL_EXPIRY()));
  // change membership: pass an AddMember (2/3 quorum) so the live quorum changes, then compare
  const add = await (await dao(members[1]).proposeAddMember("add new member", "New Member", s[17].address)).wait();
  const addId = await dao(deployer).proposalCount(); const need = (await dao(deployer).getProposalMeta(addId)).requiredVotes;
  const already = (await dao(deployer).getProposal(addId)).votes;
  for (let k = 2; BigInt(k - 2) < need - already; k++) await (await dao(members[k]).vote(addId)).wait();
  ok("F8) AddMember executed: 16 members now", (await dao(deployer).isMember(s[17].address)) === true);
  const m1After = await dao(deployer).getProposalMeta(id), reqNow16 = await dao(deployer).requiredVotesNow(PT.SendETH);
  ok("F9) after membership change, getProposalMeta still returns the ORIGINAL snapshot (not the live quorum)", m1After.requiredVotes === m1.requiredVotes, `stored=${m1After.requiredVotes}, requiredVotesNow=${reqNow16}`);
  ok("F10) and requiredVotesNow() changed — using it for an existing proposal would be wrong", reqNow16 !== m1.requiredVotes, `${reqNow15} -> ${reqNow16}`);
  const gp1 = await dao(deployer).getProposal(id);
  ok("F11) getProposal() still returns its original fields for the same proposal", Number(gp1.pType) === PT.SendETH && gp1.proposer === members[0].address);
  const none = await dao(deployer).getProposalMeta(999);
  ok("F12) never-created id → empty/zero (same behaviour as getProposal)", none.description === "" && none.requiredVotes === 0n && none.expiresAt === 0n);

  // ---------------- ValidatorsRegistry.paramProposals ----------------
  let rh = fs.readFileSync(path.join(DIR, "genesis-seed-helpers/ValidatorsRegistry_GenesisSeed.sol"), "utf8");
  let j = 0; rh = rh.replace(/address\(0\)(,?)(\s*)\/\/ /g, (_, c, sp) => s[1 + j++].address + c + sp + "// ");
  ok("R0) registry helper patched with 7 distinct test-signer validators", j === 7);
  const R = await realOnSeed(rh, "ValidatorsRegistry_GenesisSeed", fs.readFileSync(path.join(DIR, "ValidatorsRegistry.sol"), "utf8"), "ValidatorsRegistry", deployer);
  const reg = (w) => new hre.ethers.Contract(R.addr, R.abi, w);
  const pp = R.abi.find(x => x.name === "paramProposals");
  ok("R1) paramProposals(id) is public and exposes requiredVotes, createdAt, expiresAt", pp && ["requiredVotes","createdAt","expiresAt"].every(n => pp.outputs.some(o => o.name === n)), pp && pp.outputs.map(o => o.name).join(","));
  const rrc = await (await reg(s[1]).proposeParameterChange(3 /* RecoveryPeriod */, 7200)).wait();
  const pid = await reg(deployer).paramProposalCount ? await reg(deployer).paramProposalCount() : 1n;
  const p = await reg(deployer).paramProposals(pid); const rb = await hre.ethers.provider.getBlock(rrc.blockNumber);
  ok("R2) requiredVotes snapshot equals requiredVotesNow() at creation (7 active)", p.requiredVotes === await reg(deployer).requiredVotesNow(), `${p.requiredVotes}`);
  ok("R3) createdAt = creation block timestamp and expiresAt > createdAt", p.createdAt === BigInt(rb.timestamp) && p.expiresAt > p.createdAt, `${p.createdAt} / ${p.expiresAt}`);
  ok("R4) key and value decoded by field name from the real ABI (key=3 RecoveryPeriod, value=7200)", Number(p.key) === 3 && p.newValue === 7200n);

  const bad = results.filter(x => !x).length; console.log(`\nنتیجه: ${results.length - bad}/${results.length} گذر`); process.exit(bad ? 1 : 0);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
