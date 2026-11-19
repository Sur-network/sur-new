// BG-01 Genesis boots (+ BG-SIZE: calls to the two oversized injected contracts, + BG-11 partial reads later)
const { Net, Checks, writeResult, ethers, ADDR, keys, sealSigners, sleep } = require("./lib");
(async () => {
  const net = new Net("A", "n1");
  const c = new Checks();
  const p = net.provider;
  const net_ver = await p.send("web3_clientVersion", []);
  const chainId = await p.send("eth_chainId", []);
  const h0 = await net.head();
  await net.waitBlocks(5);
  const h1 = await net.head();
  c.ok("blocks are produced (head advanced by >=5)", h1 >= h0 + 5, { h0, h1 });
  const g = await net.block(0);
  const gen = await net.block(1);
  c.ok("block 1 timestamp after genesis", BigInt(gen.timestamp) > BigInt(g.timestamp));
  const reg = net.c("REG");
  const gv = Array.from(await reg.getValidators());
  const op1 = net.addr("op1"), owner1 = net.addr("owner1");
  c.ok("Registry.getValidators() == [operator1]", gv.length === 1 && gv[0] === op1, gv);
  c.ok("operator key differs from owner key (owner1 not in the list)", op1 !== owner1 && !gv.includes(owner1), { op1, owner1 });
  const owners = Array.from(await reg.getActiveOwners());
  c.ok("Registry.getActiveOwners() == [owner1]", owners.length === 1 && owners[0] === owner1, owners);
  const head = await net.head();
  const q = await net.qbftValidators(head);
  c.ok("qbft_getValidatorsByBlockNumber(latest) == [operator1]", q.length === 1 && ethers.getAddress(q[0]) === op1, q);
  const q1 = await net.qbftValidators(1);
  c.ok("qbft validators at block 1 == [operator1]", q1.length === 1 && ethers.getAddress(q1[0]) === op1, q1);
  // miner of the last blocks
  const miners = [];
  for (let n = head - 4; n <= head; n++) miners.push(ethers.getAddress((await net.block(n)).miner));
  c.ok("miner of last 5 blocks is operator1", miners.every((m) => m === op1), miners);
  // owner statuses
  const st = {};
  for (let i = 1; i <= 7; i++) st["owner" + i] = Number((await reg.validators(net.addr("owner" + i))).status);
  c.ok("only owner1 Active (2) at genesis, owners 2..7 Probation (1)", st.owner1 === 2 && [2,3,4,5,6,7].every((i) => st["owner" + i] === 1), st);
  const nftTotal = await net.c("NFT").totalMinted();
  c.ok("7 founder seats minted", nftTotal === 7n, nftTotal);
  const nftOwners = []; for (let i = 1; i <= 7; i++) nftOwners.push(await net.c("NFT").ownerOf(i));
  c.ok("seat ids 1..7 owned by owner1..owner7 in order", nftOwners.every((a, i) => a === net.addr("owner" + (i + 1))), nftOwners);
  // oracle overlays visible on chain
  c.ok("Registry.verifier == test verifier", (await reg.verifier()) === net.addr("verifier"));
  c.ok("Distributor.distributionOracle == test oracle", (await net.c("DIST").distributionOracle()) === net.addr("distOracle"));
  c.ok("IdentityRegistry.identityOracle == test oracle", (await net.c("IDENTITY").identityOracle()) === net.addr("identityOracle"));
  // BG-SIZE
  const sizes = {};
  for (const k of ["DAO", "REG", "BOARD", "DIST", "NFT", "LOTTERY"]) sizes[k] = (await p.getCode(ADDR[k])).length / 2 - 0.5;
  c.ok("eth_getCode DAO/Registry > 24576 bytes (injected via alloc)", sizes.DAO > 24576 && sizes.REG > 24576, sizes);
  // balances
  const bal = { dao: await net.balance(ADDR.DAO), vault: await net.balance(ADDR.VAULT), dist: await net.balance(ADDR.DIST) };
  c.ok("FoundationDAO balance == 20,000,000 Suren at genesis block (+ no inflow)", (await net.balance(ADDR.DAO, "0x0")) === ethers.parseEther("20000000"), (await net.balance(ADDR.DAO, "0x0")));
  const sw = await Promise.all([1, 2, 3].map((n) => sealSigners(net, head - n, [op1])));
  c.ok("committed-seal signers recovered cryptographically and all == operator1", sw.every((s) => s.signers && s.signers.every((a) => a === op1)), sw);
  const metrics = await p.send("qbft_getSignerMetrics", []).catch((e) => String(e.message));
  writeResult("BG-01", { verdict: c.verdict, summary: `head=${head}, validators=[operator1]`, besu: net_ver, chainId, checks: c.items, qbftValidatorsLatest: q, signerMetrics: metrics, balances: { dao: bal.dao.toString(), vault: bal.vault.toString(), dist: bal.dist.toString() } });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
