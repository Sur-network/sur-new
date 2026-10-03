// C-L04 on Net-L04: eligibility-snapshot (L04) regression across Registry param, Treasury cap,
// and Distributor rate proposals. C6 joins AFTER P1/T1/D1 are created -> its votes rejected.
// V5 suspended before P2/T2/D2 creation -> its later vote rejected. V4 suspended AFTER creation
// (was eligible) -> blocked while suspended by onlyActiveValidator, votable again after recovery.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const RPC = "http://127.0.0.1:8731";
const REGISTRY = "0x3333333333333333333333333333333333333333";
const TREASURY = "0x5555555555555555555555555555555555555555";
const DISTRIBUTOR = "0x2222222222222222222222222222222222222222";

const REG_ABI = [
  "function requestMembership() external payable",
  "function currentEntryThreshold() view returns (uint256)",
  "function currentMembershipFee() view returns (uint256)",
  "function recordActivation(address,bytes32) external returns (uint256)",
  "function recordSuspension(address,bytes32) external returns (uint256)",
  "function recordRecovery(address,bytes32) external returns (uint256)",
  "function requestExit() external",
  "function proposeParameterChange(uint8,uint256) external returns (uint256)",
  "function voteParameterChange(uint256) external",
  "function paramProposals(uint256) view returns (uint8 key,uint256 newValue,uint256 votes,uint256 requiredVotes,uint256 createdAt,uint256 expiresAt,bool executed,uint256 createdAtNonce)",
  "function getActiveValidatorCount() view returns (uint256)",
  "function getValidatorInfo(address) view returns (uint8,uint256,uint256,uint256,uint256,bool)",
  "function isValidator(address) view returns (bool)",
];
const TREASURY_ABI = [
  "function proposeCapChange(uint8,uint256) external returns (uint256)",
  "function voteCapChange(uint256) external",
  "function capChangeProposals(uint256) view returns (uint8 kind,uint256 newValue,uint256 votes,uint256 requiredVotes,uint256 createdAt,uint256 expiresAt,bool executed,uint256 createdAtNonce)",
];
const DIST_ABI = [
  "function proposeRateChange(uint256,uint256) external returns (uint256)",
  "function validatorVoteRateChange(uint256) external",
  "function rateProposalCount() view returns (uint256)",
];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const founders = [1, 2, 3, 4, 5].map((i) => new ethers.Wallet(accounts[`g5_v${i}`].privateKey, provider));
  const [V1, V2, V3, V4, V5] = founders;
  const C6 = new ethers.Wallet(accounts.g5_c6.privateKey, provider);
  const verifier = new ethers.Wallet(accounts.verifier.privateKey, provider);
  const registry = new ethers.Contract(REGISTRY, REG_ABI, provider);
  const out = {};

  // Step 1: C6 requestMembership
  const threshold = await registry.currentEntryThreshold();
  const fee = await registry.currentMembershipFee();
  const regC6 = new ethers.Contract(REGISTRY, REG_ABI, C6);
  const joinTx = await regC6.requestMembership({ value: threshold + fee, gasLimit: 600000 });
  const joinRcpt = await joinTx.wait();
  out.c6_join = { txHash: joinRcpt.hash, status: joinRcpt.status };
  console.log("C6 joined:", JSON.stringify(out.c6_join));

  // Build P1 (Registry param: MaxEntriesPerWindow -> 12), T1 (Treasury cap), D1 (rate) BEFORE C6 activation
  const regV1 = new ethers.Contract(REGISTRY, REG_ABI, V1);
  const p1Tx = await regV1.proposeParameterChange(0 /* MaxEntriesPerWindow */, 12, { gasLimit: 400000 });
  await p1Tx.wait();
  const trV1 = new ethers.Contract(TREASURY, TREASURY_ABI, V1);
  const t1Tx = await trV1.proposeCapChange(0 /* PerPayment */, ethers.parseEther("60000"), { gasLimit: 400000 });
  await t1Tx.wait();
  const distV1 = new ethers.Contract(DISTRIBUTOR, DIST_ABI, V1);
  const currentBlock = await provider.getBlockNumber();
  const d1Tx = await distV1.proposeRateChange(currentBlock + 500000, ethers.parseEther("2.5"), { gasLimit: 400000 });
  await d1Tx.wait();
  const distFull = new ethers.Contract(DISTRIBUTOR, [...DIST_ABI], provider);
  const idD1 = Number(await distFull.rateProposalCount());
  out.proposals_before_c6 = { idP1: 1, idT1: 1, idD1 };
  console.log("P1/T1/D1 built before C6 activation:", JSON.stringify(out.proposals_before_c6));

  // Step 2: wait probation, activate C6
  const infoC6 = await registry.getValidatorInfo(C6.address);
  const probationPeriod = 300; // overlay value, known
  const readyAt = Number(infoC6[2]) + probationPeriod;
  const waitMs = Math.max(0, readyAt - Math.floor(Date.now() / 1000) + 3) * 1000;
  console.log(`Waiting ${waitMs}ms for C6 probation...`);
  await new Promise((r) => setTimeout(r, waitMs));
  const regVerifier = new ethers.Contract(REGISTRY, REG_ABI, verifier);
  const actTx = await regVerifier.recordActivation(C6.address, ethers.keccak256(ethers.toUtf8Bytes("c6-activation")), { gasLimit: 600000 });
  await actTx.wait();
  out.c6_activated = { isValidator: await registry.isValidator(C6.address) };
  console.log("C6 activated:", JSON.stringify(out.c6_activated));

  // C-L04-1: C6 votes on P1/T1/D1 -> all rejected
  out.cl04_1 = {};
  const regC6v = new ethers.Contract(REGISTRY, REG_ABI, C6);
  try { await regC6v.voteParameterChange.staticCall(1); out.cl04_1.P1 = "UNEXPECTED_SUCCESS"; } catch (e) { out.cl04_1.P1 = e.reason || e.message; }
  const trC6 = new ethers.Contract(TREASURY, TREASURY_ABI, C6);
  try { await trC6.voteCapChange.staticCall(1); out.cl04_1.T1 = "UNEXPECTED_SUCCESS"; } catch (e) { out.cl04_1.T1 = e.reason || e.message; }
  const distC6 = new ethers.Contract(DISTRIBUTOR, DIST_ABI, C6);
  try { await distC6.validatorVoteRateChange.staticCall(idD1); out.cl04_1.D1 = "UNEXPECTED_SUCCESS"; } catch (e) { out.cl04_1.D1 = e.reason || e.message; }
  console.log("=== C-L04-1 ===", JSON.stringify(out.cl04_1, null, 2));

  // Step 3: suspend V5 (active 6->5)
  const susV5Tx = await regVerifier.recordSuspension(V5.address, ethers.keccak256(ethers.toUtf8Bytes("l04-susp-v5")), { gasLimit: 600000 });
  await susV5Tx.wait();
  out.v5_suspended_count = (await registry.getActiveValidatorCount()).toString();

  // Build P2/T2/D2 with V5 inactive, V4 active
  const p2Tx = await regV1.proposeParameterChange(0, 13, { gasLimit: 400000 });
  await p2Tx.wait();
  const t2Tx = await trV1.proposeCapChange(0, ethers.parseEther("61000"), { gasLimit: 400000 });
  await t2Tx.wait();
  const d2Tx = await distV1.proposeRateChange(currentBlock + 600000, ethers.parseEther("2.6"), { gasLimit: 400000 });
  await d2Tx.wait();
  const idD2 = Number(await distFull.rateProposalCount());
  out.proposals_p2t2d2 = { idP2: 2, idT2: 2, idD2 };
  console.log("P2/T2/D2 built with V5 suspended:", JSON.stringify(out.proposals_p2t2d2));

  // Step 4: suspend V4 (active 5->4)
  const susV4Tx = await regVerifier.recordSuspension(V4.address, ethers.keccak256(ethers.toUtf8Bytes("l04-susp-v4")), { gasLimit: 600000 });
  await susV4Tx.wait();
  out.v4_suspended_count = (await registry.getActiveValidatorCount()).toString();

  // C-L04-3 part1: V4 (suspended) tries to vote on P2 -> rejected by onlyActiveValidator
  const regV4 = new ethers.Contract(REGISTRY, REG_ABI, V4);
  try { await regV4.voteParameterChange.staticCall(2); out.v4_vote_while_suspended = "UNEXPECTED_SUCCESS"; } catch (e) { out.v4_vote_while_suspended = e.reason || e.message; }
  console.log("V4 vote while suspended:", out.v4_vote_while_suspended);

  // Step 5: V3 votes on P2 (counted), then requestExit()
  const regV3 = new ethers.Contract(REGISTRY, REG_ABI, V3);
  const v3VoteTx = await regV3.voteParameterChange(2, { gasLimit: 400000 });
  const v3VoteRcpt = await v3VoteTx.wait();
  out.v3_vote_p2 = { status: v3VoteRcpt.status };
  const v3ExitTx = await regV3.requestExit({ gasLimit: 600000 });
  await v3ExitTx.wait();
  out.active_after_v3_exit = (await registry.getActiveValidatorCount()).toString();
  // V3's fresh vote attempt on T2 (hasn't voted there) should now be rejected (no longer active)
  const trV3 = new ethers.Contract(TREASURY, TREASURY_ABI, V3);
  try { await trV3.voteCapChange.staticCall(2); out.v3_vote_t2_after_exit = "UNEXPECTED_SUCCESS"; } catch (e) { out.v3_vote_t2_after_exit = e.reason || e.message; }
  console.log("V3 exit + fresh vote after exit:", JSON.stringify({ active_after_v3_exit: out.active_after_v3_exit, v3_vote_t2_after_exit: out.v3_vote_t2_after_exit }));

  fs.mkdirSync(path.join(ROOT, "evidence", "04-results"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "evidence", "04-results", "Net-L04-CL04-part1.json"), JSON.stringify(out, null, 2));
  console.log("\nWrote part1 evidence file. V5+V4 recovery + C-L04-2/3-part2/5 to follow after recoveryPeriod wait.");
}

main().catch((err) => { console.error(err); process.exitCode = 1; });
