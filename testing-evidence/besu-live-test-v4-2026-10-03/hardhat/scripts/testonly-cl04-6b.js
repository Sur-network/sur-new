// C-L04-6b — the case C-L04-6 did not exercise: a member that already VOTED on a still-PENDING proposal is removed and later RE-ADDED, then tries to vote on that same proposal again.
// (Run 1 on Net-BR had ONE wrong expectation, S3.3: it expected "already voted" for the REMOVED member, but vote() has the onlyMember modifier first, so the correct message is "caller is not a member". Run 1 is kept as Net-BR-CL04-6b-run1-14of15.json and testonly-cl04-6b.js.run1; this corrected script was re-run on a second fresh network.)
// Network (default Net-BR; env NET/PORT) (fresh G5, FoundationDAO 15-member seed, board seeded; A-live pristine check done BEFORE any transaction). Baseline contracts, real transactions.
// The proposal stays PENDING throughout (no "proposal not pending" shortcut). Contract check order in FoundationDAO._vote: found -> pending -> not expired -> "already voted" -> "not a member" -> "not eligible ...".
const { ethers, ADDR, accounts, saveEvidence } = require("./v5-lib");
const NET = process.env.NET || "Net-BR", URL = "http://127.0.0.1:" + (process.env.PORT || "9601");
const FD_ABI = [
  "function proposeAddMember(string description, string name, address account) returns (uint256)",
  "function proposeRemoveMember(string description, address account) returns (uint256)",
  "function proposeSendETH(string description, address to, uint256 amount) returns (uint256)",
  "function vote(uint256 proposalId)",
  "function hasVoted(uint256 proposalId, address voter) view returns (bool)",
  "function isMember(address) view returns (bool)",
  "function membershipNonce() view returns (uint256)",
  "function memberSinceNonce(address) view returns (uint256)",
  "function getMemberCount() view returns (uint256)",
  "function getEthBalance() view returns (uint256)",
  "function proposalCount() view returns (uint256)",
  "function requiredVotesNow(uint8 pType) view returns (uint256)",
  "function getProposal(uint256 id) view returns (uint8 pType, address proposer, string newMemberName, address targetAccount, uint256 amount, address tokenAddress, bytes data, uint256 votes, uint8 status)",
  "function getProposalMeta(uint256 id) view returns (string description, uint256 requiredVotes, uint256 createdAt, uint256 expiresAt)",
];
const ADD = 0, REMOVE = 1, SEND = 2;
const E18 = 10n ** 18n;
const reason = (e) => e.reason || e.shortMessage || e.message;

async function main() {
  const provider = new ethers.JsonRpcProvider(URL);
  const oracle = new ethers.Wallet(accounts.distributionOracle.privateKey, provider);
  const M = Array.from({ length: 15 }, (_, i) => new ethers.Wallet(accounts[`foundation${i + 1}`].privateKey, provider));
  const dao = (w) => new ethers.Contract(ADDR.FOUNDATION, FD_ABI, w || provider);
  const sink = (i) => ethers.getAddress("0x" + ethers.keccak256(ethers.toUtf8Bytes(`cl04-6b-sink-${i}`)).slice(26));
  const out = { NET, startedAt: new Date().toISOString(), steps: [], assertions: [] };
  const A = (id, text, expected, actual, pass) => { out.assertions.push({ id, text, expected: String(expected), actual: String(actual), pass: !!pass }); console.log(pass ? "PASS" : "FAIL", id, text, "| expected", String(expected), "| actual", String(actual)); return !!pass; };
  const tx = async (label, promise) => { const t = await promise; const r = await t.wait(); out.steps.push({ label, hash: r.hash, block: r.blockNumber, status: r.status, gasUsed: r.gasUsed.toString() }); return r; };
  const tryStatic = async (fn) => { try { await fn(); return "UNEXPECTED_SUCCESS"; } catch (e) { return reason(e); } };
  const minedVote = async (label, w, id) => { try { const t = await dao(w).vote(id, { gasLimit: 400000 }); const r = await t.wait(); out.steps.push({ label, hash: r.hash, status: r.status }); return r.status; } catch (e) { out.steps.push({ label, status: 0, hash: e.receipt ? e.receipt.hash : (e.transactionHash || null), note: reason(e) }); return 0; } };
  const state = async (id) => { const p = await dao().getProposal(id), m = await dao().getProposalMeta(id); return { votes: Number(p.votes), status: Number(p.status), requiredVotes: Number(m.requiredVotes), expiresAt: Number(m.expiresAt) }; };
  const isPending = async (id) => (await state(id)).status === 0;

  // S0 preconditions
  const pc0 = await dao().proposalCount();
  A("S0.1", "FoundationDAO untouched: proposalCount()==0 and membershipNonce()==0", "0;0", `${pc0};${await dao().membershipNonce()}`, pc0 === 0n && (await dao().membershipNonce()) === 0n);
  A("S0.2", "15 members, requiredVotesNow(SendETH)=8, (AddMember)=10, (RemoveMember)=10", "15;8;10;10", `${await dao().getMemberCount()};${await dao().requiredVotesNow(SEND)};${await dao().requiredVotesNow(ADD)};${await dao().requiredVotesNow(REMOVE)}`, (await dao().getMemberCount()) === 15n && (await dao().requiredVotesNow(SEND)) === 8n && (await dao().requiredVotesNow(ADD)) === 10n && (await dao().requiredVotesNow(REMOVE)) === 10n);
  // S1 funding (800,000 gas x 0.0001 SUR = 80 SUR upfront per transaction -> every sender to 500 SUR; the DAO to 5 SUR)
  for (const w of M) { const bal = await provider.getBalance(w.address); if (bal < 500n * E18) await tx(`fund ${w.address} to 500 SUR`, oracle.sendTransaction({ to: w.address, value: 500n * E18 - bal, gasLimit: 21000 })); }
  { const bal = await dao().getEthBalance(); if (bal < 5n * E18) await tx("fund FoundationDAO to 5 SUR", oracle.sendTransaction({ to: ADDR.FOUNDATION, value: 5n * E18 - bal, gasLimit: 100000 })); }

  // S2 proposal P4 (SendETH 1 SUR) created at nonce 0 (quorum 8); M1 (auto), M4 and M2 vote -> 3 votes
  const P4 = Number(await dao().proposalCount()) + 1;
  await tx("P4 propose SendETH 1 SUR (M1)", dao(M[0]).proposeSendETH("P4: M4 votes, is removed, re-added, re-votes", sink(4), E18, { gasLimit: 800000 }));
  await tx("P4 vote M4 (the member that will be removed and re-added)", dao(M[3]).vote(P4, { gasLimit: 400000 }));
  await tx("P4 vote M2", dao(M[1]).vote(P4, { gasLimit: 400000 }));
  let s = await state(P4);
  A("S2.1", "P4 pending, 3 votes (M1 auto, M4, M2), snapshot quorum 8; M4 has voted", "Pending;3;8;true", `${s.status === 0 ? "Pending" : "Executed"};${s.votes};${s.requiredVotes};${await dao().hasVoted(P4, M[3].address)}`, s.status === 0 && s.votes === 3 && s.requiredVotes === 8 && (await dao().hasVoted(P4, M[3].address)));

  // S3 REMOVE M4 (10 of 15)
  const REM = Number(await dao().proposalCount()) + 1;
  await tx("remove-M4 propose (M1)", dao(M[0]).proposeRemoveMember("remove M4", M[3].address, { gasLimit: 800000 }));
  for (const i of [1, 2, 4, 5, 6, 7, 8, 9, 10]) await tx(`remove-M4 vote M${i + 1}`, dao(M[i]).vote(REM, { gasLimit: 700000 })); // 1 + 9 = 10
  A("S3.1", "M4 removed: isMember false; 14 members; membershipNonce 1; memberSinceNonce(M4)=0", "false;14;1;0", `${await dao().isMember(M[3].address)};${await dao().getMemberCount()};${await dao().membershipNonce()};${await dao().memberSinceNonce(M[3].address)}`, !(await dao().isMember(M[3].address)) && (await dao().getMemberCount()) === 14n && (await dao().membershipNonce()) === 1n && (await dao().memberSinceNonce(M[3].address)) === 0n);
  s = await state(P4);
  A("S3.2", "P4 still PENDING after the removal; M4's vote is KEPT (hasVoted true; votes still 3); snapshot quorum still 8", "Pending;3;8;true", `${s.status === 0 ? "Pending" : "Executed"};${s.votes};${s.requiredVotes};${await dao().hasVoted(P4, M[3].address)}`, s.status === 0 && s.votes === 3 && s.requiredVotes === 8 && (await dao().hasVoted(P4, M[3].address)));
  const msgGone = await tryStatic(() => dao(M[3]).vote.staticCall(P4));
  A("S3.3", "while removed, M4's second vote on P4 is rejected (eth_call) by the onlyMember modifier, which runs BEFORE _vote (so the 'already voted' check is not reached while M4 is not a member)", "FoundationDAO: caller is not a member", msgGone, msgGone.includes("caller is not a member"));

  // S4 RE-ADD M4 (14 members: two-thirds = 10)
  const READD = Number(await dao().proposalCount()) + 1;
  await tx("re-add-M4 propose (M1)", dao(M[0]).proposeAddMember("re-add M4", "Member 4 (re-added)", M[3].address, { gasLimit: 800000 }));
  for (const i of [1, 2, 4, 5, 6, 7, 8, 9, 10]) await tx(`re-add-M4 vote M${i + 1}`, dao(M[i]).vote(READD, { gasLimit: 700000 }));
  A("S4.1", "M4 re-added: member; 15 members; membershipNonce 2; memberSinceNonce(M4)=2 (> P4's creation nonce 0)", "true;15;2;2", `${await dao().isMember(M[3].address)};${await dao().getMemberCount()};${await dao().membershipNonce()};${await dao().memberSinceNonce(M[3].address)}`, (await dao().isMember(M[3].address)) && (await dao().getMemberCount()) === 15n && (await dao().membershipNonce()) === 2n && (await dao().memberSinceNonce(M[3].address)) === 2n);
  s = await state(P4);
  A("S4.2", "P4 is STILL pending (not executed, not expired) with 3 votes and M4's old vote kept — this is the case under test", "Pending;3;true", `${s.status === 0 ? "Pending" : "Executed"};${s.votes};${await dao().hasVoted(P4, M[3].address)}`, s.status === 0 && s.votes === 3 && (await dao().hasVoted(P4, M[3].address)));
  const nowTs = (await provider.getBlock("latest")).timestamp;
  A("S4.3", "P4 has not expired (block time < expiresAt)", "true", `${nowTs} < ${s.expiresAt}`, nowTs < s.expiresAt);

  // S5 the missing scenario: the re-added member votes AGAIN on the still-pending P4
  const msgRe = await tryStatic(() => dao(M[3]).vote.staticCall(P4));
  A("S5.1", "re-added M4 re-voting on the still-pending P4 (eth_call) is rejected: 'already voted' (its earlier vote was kept and cannot be cast twice; the eligibility message is not reached for a member that already voted)", "FoundationDAO: already voted", msgRe, msgRe.includes("already voted"));
  const stRe = await minedVote("re-added M4 re-votes on P4 (mined)", M[3], P4);
  s = await state(P4);
  A("S5.2", "the same vote mined: status 0, P4 votes unchanged at 3 (no double count), still Pending", "0;3;Pending", `${stRe};${s.votes};${s.status === 0 ? "Pending" : "Executed"}`, stRe === 0 && s.votes === 3 && s.status === 0);
  A("S5.3", "'not pending' is NOT the reason: the proposal is pending at the moment of the call", "true", await isPending(P4), await isPending(P4));
  // S6 P4 completes with M4's vote counted exactly ONCE (snapshot quorum 8): votes M3, M5, M6, M7 -> 7 (pending), M8 -> 8 executes
  for (const i of [2, 4, 5, 6]) await tx(`P4 vote M${i + 1}`, dao(M[i]).vote(P4, { gasLimit: 400000 }));
  s = await state(P4);
  A("S6.1", "P4 at 7 votes is still pending (had M4's re-vote been double-counted it would be 8 and executed)", "Pending;7", `${s.status === 0 ? "Pending" : "Executed"};${s.votes}`, s.status === 0 && s.votes === 7);
  const balBefore = await dao().getEthBalance();
  await tx("P4 vote M8 (8th vote -> executes)", dao(M[7]).vote(P4, { gasLimit: 600000 }));
  s = await state(P4);
  A("S6.2", "P4 executes at exactly 8 distinct votes (M4 counted once); DAO balance −1 SUR; sink +1 SUR", "Executed;8;-1;1", `${s.status === 1 ? "Executed" : "Pending"};${s.votes};${ethers.formatEther((await dao().getEthBalance()) - balBefore)};${ethers.formatEther(await provider.getBalance(sink(4)))}`, s.status === 1 && s.votes === 8 && (await dao().getEthBalance()) === balBefore - E18 && (await provider.getBalance(sink(4))) === E18);
  const msgAfter = await tryStatic(() => dao(M[3]).vote.staticCall(P4));
  A("S6.3", "after execution the same call gives 'proposal not pending' (the different, closed-proposal reason — recorded to show it is not what S5 measured)", "FoundationDAO: proposal not pending", msgAfter, msgAfter.includes("proposal not pending"));

  out.final = { memberCount: Number(await dao().getMemberCount()), membershipNonce: Number(await dao().membershipNonce()), balance: ethers.formatEther(await dao().getEthBalance()) };
  out.finishedAt = new Date().toISOString();
  out.summary = { total: out.assertions.length, pass: out.assertions.filter((a) => a.pass).length, fail: out.assertions.filter((a) => !a.pass).length };
  console.log(JSON.stringify(out.summary));
  saveEvidence(NET + "-CL04-6b.json", out);
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
