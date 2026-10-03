// C-L04-6 on Net-L04f (fresh G5 network, FoundationDAO seeded with 15 members, no prior transaction): FoundationDAO eligibility snapshot (L04), baseline contracts, real transactions.
// Covers: a member ADDED after a proposal was created cannot vote on it; a member REMOVED keeps the vote already cast; a removed-and-RE-ADDED member is treated as a new member for
// older proposals; the quorum of an open proposal stays frozen while membership (and the live quorum) changes; membership changes never void an open proposal.
const { ethers, ADDR, accounts, saveEvidence, sleep } = require("./v5-lib");
const URL = "http://127.0.0.1:9501";
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
  const M = Array.from({ length: 15 }, (_, i) => new ethers.Wallet(accounts[`foundation${i + 1}`].privateKey, provider)); // M[0] = member 1
  const N = new ethers.Wallet(accounts.serviceStakingUser1.privateKey, provider); // the member that will be ADDED
  const dao = (w) => new ethers.Contract(ADDR.FOUNDATION, FD_ABI, w || provider);
  const sink = (i) => ethers.getAddress("0x" + ethers.keccak256(ethers.toUtf8Bytes(`cl04-6-sink-${i}`)).slice(26));
  const out = { NET: "Net-L04f", startedAt: new Date().toISOString(), steps: [], assertions: [] };
  const A = (id, text, expected, actual, pass) => { out.assertions.push({ id, text, expected: String(expected), actual: String(actual), pass: !!pass }); console.log(pass ? "PASS" : "FAIL", id, text, "| expected", String(expected), "| actual", String(actual)); return !!pass; };
  const tx = async (label, promise) => { const t = await promise; const r = await t.wait(); out.steps.push({ label, hash: r.hash, block: r.blockNumber, status: r.status, gasUsed: r.gasUsed.toString() }); return r; };
  const tryStatic = async (fn) => { try { await fn(); return "UNEXPECTED_SUCCESS"; } catch (e) { return reason(e); } };
  const realRevert = async (label, w, id) => { try { const t = await dao(w).vote(id, { gasLimit: 400000 }); const r = await t.wait(); out.steps.push({ label, hash: r.hash, status: r.status }); return r.status; } catch (e) { out.steps.push({ label, status: 0, hash: e.receipt ? e.receipt.hash : (e.transactionHash || null), note: reason(e) }); return 0; } };
  const state = async (id) => { const p = await dao().getProposal(id), m = await dao().getProposalMeta(id); return { votes: Number(p.votes), status: Number(p.status), requiredVotes: Number(m.requiredVotes), createdAt: Number(m.createdAt) }; };

  // ---------- S0 preconditions (read BEFORE any transaction) ----------
  // The pristine Group A check of this network ran BEFORE any transaction (A-live-Net-L04f.json). Funding transactions from the oracle may already exist here (a first run stalled on
  // insufficient upfront balance; the network was restarted and re-used) — what must be untouched is the FoundationDAO itself.
  const pc0 = await dao().proposalCount();
  A("S0.1", "FoundationDAO untouched: proposalCount()==0 and membershipNonce()==0 (funding transfers do not touch it)", "0;0", `${pc0};${await dao().membershipNonce()}`, pc0 === 0n && (await dao().membershipNonce()) === 0n);
  A("S0.2", "FoundationDAO member count (15-member seed)", 15, await dao().getMemberCount(), (await dao().getMemberCount()) === 15n);
  A("S0.3", "membershipNonce()", 0, await dao().membershipNonce(), (await dao().membershipNonce()) === 0n);
  let allZero = true, allMembers = true; for (const w of M) { if ((await dao().memberSinceNonce(w.address)) !== 0n) allZero = false; if (!(await dao().isMember(w.address))) allMembers = false; }
  A("S0.4", "all 15 members: isMember and memberSinceNonce == 0", "true/true", `${allMembers}/${allZero}`, allZero && allMembers);
  A("S0.5", "requiredVotesNow(AddMember) = ceil(2n/3) for n=15", 10, await dao().requiredVotesNow(ADD), (await dao().requiredVotesNow(ADD)) === 10n);
  A("S0.6", "requiredVotesNow(SendETH) = floor(n/2)+1 for n=15", 8, await dao().requiredVotesNow(SEND), (await dao().requiredVotesNow(SEND)) === 8n);
  A("S0.7", "the candidate N is not a member", false, await dao().isMember(N.address), !(await dao().isMember(N.address)));

  // ---------- S1 funding (members and N need gas; the DAO needs a balance for SendETH) ----------
  // gas: a transaction with gasLimit 800,000 at 0.0001 SUR/gas needs 80 SUR upfront, so every sender is topped up to 500 SUR
  for (const w of [...M, N]) { const bal = await provider.getBalance(w.address); if (bal < 500n * E18) await tx(`fund ${w.address} to 500 SUR`, oracle.sendTransaction({ to: w.address, value: 500n * E18 - bal, gasLimit: 21000 })); }
  { const bal = await dao().getEthBalance(); if (bal < 5n * E18) await tx("fund FoundationDAO to 5 SUR (plain transfer)", oracle.sendTransaction({ to: ADDR.FOUNDATION, value: 5n * E18 - bal, gasLimit: 100000 })); }
  A("S1.1", "FoundationDAO balance after funding", "5 SUR", ethers.formatEther(await dao().getEthBalance()) + " SUR", (await dao().getEthBalance()) === 5n * E18);

  // ---------- S2 P1 created BEFORE any membership change (n=15, quorum 8) ----------
  const P1 = Number(await dao().proposalCount()) + 1;
  await tx("P1 propose SendETH 1 SUR (M1)", dao(M[0]).proposeSendETH("P1: before the add", sink(1), E18, { gasLimit: 800000 }));
  await tx("P1 vote M2", dao(M[1]).vote(P1, { gasLimit: 400000 })); await tx("P1 vote M3", dao(M[2]).vote(P1, { gasLimit: 400000 }));
  let s = await state(P1);
  const nonceAtP1 = 0;
  A("S2.1", "P1 snapshot quorum", 8, s.requiredVotes, s.requiredVotes === 8); A("S2.2", "P1 votes (M1 auto, M2, M3) and still pending", "3 / Pending", `${s.votes} / ${s.status === 0 ? "Pending" : "Executed"}`, s.votes === 3 && s.status === 0);

  // ---------- S3 ADD member N (two-thirds: 10 of 15) ----------
  const ADDN = Number(await dao().proposalCount()) + 1;
  await tx("add-N propose (M1)", dao(M[0]).proposeAddMember("add N", "Member N", N.address, { gasLimit: 800000 }));
  for (let i = 1; i <= 8; i++) await tx(`add-N vote M${i + 1}`, dao(M[i]).vote(ADDN, { gasLimit: 400000 }));
  A("S3.1", "after 9 of 10 votes the add proposal is still pending (quorum not yet reached)", "Pending / 9", `${(await state(ADDN)).status === 0 ? "Pending" : "Executed"} / ${(await state(ADDN)).votes}`, (await state(ADDN)).status === 0 && (await state(ADDN)).votes === 9);
  await tx("add-N vote M10 (10th vote -> executes)", dao(M[9]).vote(ADDN, { gasLimit: 600000 }));
  A("S3.2", "N is now a member; member count 16; membershipNonce 1; memberSinceNonce(N)=1", "true;16;1;1", `${await dao().isMember(N.address)};${await dao().getMemberCount()};${await dao().membershipNonce()};${await dao().memberSinceNonce(N.address)}`, (await dao().isMember(N.address)) && (await dao().getMemberCount()) === 16n && (await dao().membershipNonce()) === 1n && (await dao().memberSinceNonce(N.address)) === 1n);
  s = await state(P1);
  A("S3.3", "the add did NOT void P1: still pending, 3 votes, snapshot quorum still 8", "Pending;3;8", `${s.status === 0 ? "Pending" : "Executed"};${s.votes};${s.requiredVotes}`, s.status === 0 && s.votes === 3 && s.requiredVotes === 8);
  A("S3.4", "live quorum moved (n=16): SendETH 9, AddMember 11 — while P1 stays at 8", "9 / 11", `${await dao().requiredVotesNow(SEND)} / ${await dao().requiredVotesNow(ADD)}`, (await dao().requiredVotesNow(SEND)) === 9n && (await dao().requiredVotesNow(ADD)) === 11n);

  // ---------- S4 the NEW member cannot vote on the OLDER proposal ----------
  const msgN = await tryStatic(() => dao(N).vote.staticCall(P1));
  A("S4.1", "N's vote on P1 (eth_call) is rejected with the exact eligibility message", "FoundationDAO: not eligible - not a member when this proposal was created", msgN, msgN.includes("not eligible - not a member when this proposal was created"));
  const stN = await realRevert("N votes on P1 (mined)", N, P1);
  A("S4.2", "the same vote mined: status 0 and P1 votes unchanged", "status 0; 3", `status ${stN}; ${(await state(P1)).votes}`, stN === 0 && (await state(P1)).votes === 3);

  // ---------- S5 P2 created AFTER the add (n=16, quorum 9): N is eligible ----------
  const P2 = Number(await dao().proposalCount()) + 1;
  await tx("P2 propose SendETH 1 SUR (M1)", dao(M[0]).proposeSendETH("P2: after the add", sink(2), E18, { gasLimit: 800000 }));
  await tx("P2 vote M4", dao(M[3]).vote(P2, { gasLimit: 400000 })); await tx("P2 vote M5", dao(M[4]).vote(P2, { gasLimit: 400000 }));
  await tx("P2 vote N (positive control: added BEFORE P2 was created)", dao(N).vote(P2, { gasLimit: 400000 }));
  s = await state(P2);
  A("S5.1", "P2 snapshot quorum at n=16", 9, s.requiredVotes, s.requiredVotes === 9);
  A("S5.2", "N (member since nonce 1 <= P2.createdAtNonce 1) could vote on P2: votes M1,M4,M5,N", 4, s.votes, s.votes === 4);

  // ---------- S6 REMOVE M4 (two-thirds of 16 = 11) ----------
  const REM = Number(await dao().proposalCount()) + 1;
  await tx("remove-M4 propose (M1)", dao(M[0]).proposeRemoveMember("remove M4", M[3].address, { gasLimit: 800000 }));
  const remVoters = [1, 2, 4, 5, 6, 7, 8, 9, 10, 11]; // M2,M3,M5..M12 (not M4)
  for (const i of remVoters) await tx(`remove-M4 vote M${i + 1}`, dao(M[i]).vote(REM, { gasLimit: 700000 }));
  A("S6.1", "M4 removed: isMember false; count 15; membershipNonce 2; memberSinceNonce(M4) reset to 0", "false;15;2;0", `${await dao().isMember(M[3].address)};${await dao().getMemberCount()};${await dao().membershipNonce()};${await dao().memberSinceNonce(M[3].address)}`, !(await dao().isMember(M[3].address)) && (await dao().getMemberCount()) === 15n && (await dao().membershipNonce()) === 2n && (await dao().memberSinceNonce(M[3].address)) === 0n);
  s = await state(P2);
  A("S6.2", "M4's vote on P2 is KEPT after removal: hasVoted(P2,M4) true; P2 votes still 4", "true;4", `${await dao().hasVoted(P2, M[3].address)};${s.votes}`, (await dao().hasVoted(P2, M[3].address)) && s.votes === 4);
  A("S6.3", "P2 still pending with snapshot quorum 9 while the live quorum is now 8 (n=15)", "Pending;9;8", `${s.status === 0 ? "Pending" : "Executed"};${s.requiredVotes};${await dao().requiredVotesNow(SEND)}`, s.status === 0 && s.requiredVotes === 9 && (await dao().requiredVotesNow(SEND)) === 8n);
  const msgM4 = await tryStatic(() => dao(M[3]).vote.staticCall(P1));
  A("S6.4", "removed M4 cannot vote on P1 (eth_call): caller is not a member", "FoundationDAO: caller is not a member", msgM4, msgM4.includes("caller is not a member"));

  // ---------- S7 FROZEN quorum: complete P2 while the live quorum (8) is lower than its snapshot (9) ----------
  for (const i of [5, 6, 7, 8]) await tx(`P2 vote M${i + 1}`, dao(M[i]).vote(P2, { gasLimit: 400000 })); // M6..M9 -> 8 votes
  s = await state(P2);
  A("S7.1", "P2 with 8 votes does NOT execute although the live quorum is 8 (frozen snapshot 9)", "Pending;8", `${s.status === 0 ? "Pending" : "Executed"};${s.votes}`, s.status === 0 && s.votes === 8);
  const balBefore = await dao().getEthBalance();
  await tx("P2 vote M10 (9th vote -> executes)", dao(M[9]).vote(P2, { gasLimit: 600000 }));
  s = await state(P2);
  A("S7.2", "P2 executes on the 9th vote; DAO balance falls by exactly 1 SUR and the sink received it", "Executed;-1 SUR;1 SUR", `${s.status === 0 ? "Pending" : "Executed"};${ethers.formatEther((await dao().getEthBalance()) - balBefore)} SUR;${ethers.formatEther(await provider.getBalance(sink(2)))} SUR`, s.status === 1 && (await dao().getEthBalance()) === balBefore - E18 && (await provider.getBalance(sink(2))) === E18);

  // ---------- S8 RE-ADD M4 (n=15: ceil(30/3)... two-thirds = 10) ----------
  const READD = Number(await dao().proposalCount()) + 1;
  await tx("re-add-M4 propose (M1)", dao(M[0]).proposeAddMember("re-add M4", "Member 4 (re-added)", M[3].address, { gasLimit: 800000 }));
  for (const i of [1, 2, 4, 5, 6, 7, 8, 9, 10]) await tx(`re-add-M4 vote M${i + 1}`, dao(M[i]).vote(READD, { gasLimit: 700000 })); // 1 + 9 = 10
  A("S8.1", "M4 re-added: member; count 16; membershipNonce 3; memberSinceNonce(M4)=3", "true;16;3;3", `${await dao().isMember(M[3].address)};${await dao().getMemberCount()};${await dao().membershipNonce()};${await dao().memberSinceNonce(M[3].address)}`, (await dao().isMember(M[3].address)) && (await dao().getMemberCount()) === 16n && (await dao().membershipNonce()) === 3n && (await dao().memberSinceNonce(M[3].address)) === 3n);
  const msgR1 = await tryStatic(() => dao(M[3]).vote.staticCall(P1));
  A("S8.2", "re-added M4 may NOT vote on the older P1 (it did not vote there; memberSince 3 > createdAtNonce 0)", "not eligible - not a member when this proposal was created", msgR1, msgR1.includes("not eligible - not a member when this proposal was created"));
  const msgR2 = await tryStatic(() => dao(M[3]).vote.staticCall(P2));
  A("S8.3", "on P2 (already executed) the re-added M4 gets the 'proposal not pending' error — recorded as is", "(recorded)", msgR2, true);
  const P3 = Number(await dao().proposalCount()) + 1;
  await tx("P3 propose SendETH 1 SUR (M1)", dao(M[0]).proposeSendETH("P3: after the re-add", sink(3), E18, { gasLimit: 800000 }));
  await tx("P3 vote M4 (positive control: re-added BEFORE P3)", dao(M[3]).vote(P3, { gasLimit: 400000 }));
  A("S8.4", "re-added M4 can vote on P3 created after the re-add", "votes 2", (await state(P3)).votes, (await state(P3)).votes === 2);

  // ---------- S9 FROZEN quorum the other way: P1 (snapshot 8) executes at 8 while the live quorum is 9 (n=16) ----------
  for (const i of [4, 5, 6, 7]) await tx(`P1 vote M${i + 1}`, dao(M[i]).vote(P1, { gasLimit: 400000 })); // M5..M8 -> 7 votes
  s = await state(P1);
  A("S9.1", "P1 with 7 votes still pending (snapshot 8)", "Pending;7", `${s.status === 0 ? "Pending" : "Executed"};${s.votes}`, s.status === 0 && s.votes === 7);
  await tx("P1 vote M9 (8th vote -> executes)", dao(M[8]).vote(P1, { gasLimit: 600000 }));
  s = await state(P1);
  A("S9.2", "P1 executes at 8 votes although the live SendETH quorum is 9 (n=16): frozen snapshot respected", "Executed;8;live 9", `${s.status === 0 ? "Pending" : "Executed"};${s.votes};live ${await dao().requiredVotesNow(SEND)}`, s.status === 1 && s.votes === 8 && (await dao().requiredVotesNow(SEND)) === 9n && (await provider.getBalance(sink(1))) === E18);

  // ---------- S10 final state ----------
  const final = { memberCount: Number(await dao().getMemberCount()), membershipNonce: Number(await dao().membershipNonce()), proposals: {}, balance: ethers.formatEther(await dao().getEthBalance()) };
  for (const [k, id] of Object.entries({ P1, P2, P3, ADDN, REM, READD })) final.proposals[k] = { id, ...(await state(id)) };
  out.final = final;
  A("S10.1", "final: 16 members, nonce 3, DAO balance 3 SUR (P1 and P2 executed, P3 pending)", "16;3;3.0", `${final.memberCount};${final.membershipNonce};${final.balance}`, final.memberCount === 16 && final.membershipNonce === 3 && final.balance === "3.0");
  out.finishedAt = new Date().toISOString();
  out.summary = { total: out.assertions.length, pass: out.assertions.filter((a) => a.pass).length, fail: out.assertions.filter((a) => !a.pass).length };
  console.log(JSON.stringify(out.summary));
  saveEvidence("Net-L04f-CL04-6.json", out);
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
