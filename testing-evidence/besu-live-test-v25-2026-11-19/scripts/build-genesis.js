// Genesis builder for the v2.5 live Besu test ("simulate-and-extract", as in contracts-tests/test/helpers.js deployAtFixed).
// Run:  SUR25_NET=A node <hardhat cli> --config scripts/hh/hardhat.config.js run scripts/build-genesis.js
//
// For every structural contract: deploy the *_GenesisSeed helper (which INHERITS the real contract) -- or the contract itself
// when it has no helper -- on a temporary in-process Hardhat network, collect every storage slot touched by the deployment
// transaction (debug_traceTransaction), read the final values with getStorage, and write them under the fixed address together
// with the REAL contract's deployedBytecode (runtime code) into genesis.json `alloc`.
//
// Test-only overlay (DEVIATIONS.md D-2): the three oracle addresses of SurAddresses.sol have no known private keys, so their
// storage slots (ValidatorsRegistry.verifier, BlockRewardDistributor.distributionOracle, IdentityRegistry.identityOracle) are
// overwritten with throw-away test-key addresses. The runtime bytecode is NOT changed.
const hre = require("hardhat");
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const E = path.resolve(__dirname, "..");
const keys = JSON.parse(fs.readFileSync(path.join(E, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const A = (r) => keys[r].address;
const SUREN = (n) => ethers.parseEther(String(n));
const hex = (n) => "0x" + BigInt(n).toString(16);
const pad32 = (n) => ethers.zeroPadValue(ethers.toBeHex(BigInt(n)), 32);

const FIXED = {
  FoundationDAO: "0x1111111111111111111111111111111111111111",
  BlockRewardDistributor: "0x2222222222222222222222222222222222222222",
  ValidatorsRegistry: "0x3333333333333333333333333333333333333333",
  ValidatorsBoard: "0x4444444444444444444444444444444444444444",
  ValidatorsTreasury: "0x5555555555555555555555555555555555555555",
  IdentityRegistry: "0x6666666666666666666666666666666666666666",
  FoundationMembers: "0x7777777777777777777777777777777777777777",
  ValidatorSeatNFT: "0x8888888888888888888888888888888888888888",
  GenesisClaimsVault: "0x9999999999999999999999999999999999999999",
  ValidatorLottery: "0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa",
};

// ---------------------------------------------------------------- network definitions
const NETS = {
  A: { name: "Net-A", chainId: 425025, founders: 7, blockreward: "2000000000000000000", subnet: "172.29.51", rpcBase: 19100,
       nodes: ["n1", "n2", "n3", "n4", "n5", "n6", "n7", "n2b", "n3b", "nC"] },
  S: { name: "Net-S", chainId: 425026, founders: 1, blockreward: "3000000000000000000", subnet: "172.29.52", rpcBase: 19200, nodes: ["n1"] },
  T: { name: "Net-T", chainId: 425028, founders: 1, blockreward: "2000000000000000000", subnet: "172.29.54", rpcBase: 19400, nodes: ["n1", "nC"],
       // TEST-ONLY overlay of ValidatorsRegistry storage variables (NOT constants): short time parameters so probation/exit can elapse in minutes
       regOverlay: { probationPeriod: 120, exitCooldown: 60, entryWindowSeconds: 30, recoveryPeriod: 60 } },
  L2: { name: "Net-L2", chainId: 425027, founders: 1, blockreward: "2000000000000000000", subnet: "172.29.53", rpcBase: 19300, nodes: ["n1"] },
};
const NODE_OPERATOR = { n1: "op1", n2: "op2", n3: "op3", n4: "op4", n5: "op5", n6: "op6", n7: "op7", n2b: "op2b", n3b: "op3b", nC: "opC" };
const NODE_IPSUFFIX = { n1: 11, n2: 12, n3: 13, n4: 14, n5: 15, n6: 16, n7: 17, n2b: 22, n3b: 23, nC: 31 };

const netKey = process.env.SUR25_NET;
if (!NETS[netKey]) throw new Error("set SUR25_NET to one of " + Object.keys(NETS));
const NET = NETS[netKey];
const BLOCK_PERIOD = Number(process.env.SUR25_BLOCKPERIOD || 2);

async function main() {
  const provider = new ethers.BrowserProvider(hre.network.provider);
  const signer = await provider.getSigner(0);
  const genesisTimestamp = Math.floor(Date.now() / 1000) - 60;
  const summary = { net: NET.name, genesisTimestamp, genesisTimestampISO: new Date(genesisTimestamp * 1000).toISOString(), contracts: {}, overlays: {}, seedArgs: {} };

  async function deployHelper(helperName, args) {
    const art = await hre.artifacts.readArtifact(helperName);
    const f = new ethers.ContractFactory(art.abi, art.bytecode, signer);
    const c = await f.deploy(...args);
    const rc = await c.deploymentTransaction().wait();
    const trace = await hre.network.provider.send("debug_traceTransaction", [rc.hash, { disableMemory: true, disableStack: true }]);
    const slots = new Set();
    for (const step of trace.structLogs) if (step.storage) for (const k of Object.keys(step.storage)) slots.add(k.startsWith("0x") ? k : "0x" + k);
    const addr = await c.getAddress();
    const storage = {};
    for (const k of slots) {
      const v = await provider.getStorage(addr, k);
      if (BigInt(v) !== 0n) storage[pad32(BigInt(k))] = pad32(BigInt(v));
    }
    return { contract: c, addr, storage, touched: slots.size };
  }

  async function slotOf(realName, label) {
    const fq = (await hre.artifacts.getAllFullyQualifiedNames()).find((n) => n.endsWith(`/${realName}.sol:${realName}`));
    const bi = await hre.artifacts.getBuildInfo(fq);
    const src = fq.split(":")[0];
    const layout = bi.output.contracts[src][realName].storageLayout.storage.find((s) => s.label === label);
    if (!layout) throw new Error("no slot " + label);
    if (layout.offset !== 0) throw new Error("overlay variable is packed: " + label);
    return pad32(BigInt(layout.slot));
  }

  const alloc = {};
  async function inject(realName, helperName, args, overlay) {
    const h = await deployHelper(helperName, args);
    const real = await hre.artifacts.readArtifact(realName);
    const storage = { ...h.storage };
    if (overlay) for (const [label, value] of Object.entries(overlay)) {
      const slot = await slotOf(realName, label);
      const old = storage[slot];
      storage[slot] = pad32(BigInt(value));
      summary.overlays[`${realName}.${label}`] = { slot, old: old ? "0x" + old.slice(26) : null, new: value };
    }
    const addr = FIXED[realName];
    alloc[addr.toLowerCase()] = { ...(alloc[addr.toLowerCase()] || {}), code: real.deployedBytecode, storage };
    const codeBytes = (real.deployedBytecode.length - 2) / 2;
    summary.contracts[realName] = {
      address: addr, helper: helperName, runtimeCodeBytes: codeBytes, exceedsEip170: codeBytes > 24576,
      runtimeCodeSha256: crypto.createHash("sha256").update(Buffer.from(real.deployedBytecode.slice(2), "hex")).digest("hex"),
      touchedSlots: h.touched, nonZeroSlotsWritten: Object.keys(storage).length,
    };
    console.log(`[inject] ${realName} <- ${helperName}: ${codeBytes} bytes, ${Object.keys(storage).length} slots (touched ${h.touched})`);
    return h;
  }

  // ----- founders
  const nF = NET.founders;
  const owners = []; const operators = [];
  for (let i = 1; i <= nF; i++) { owners.push(A("owner" + i)); operators.push(A("op" + i)); }

  // ValidatorsRegistry: first owner Active with its OPERATOR key; the others Probation (no collateral, no operator yet)
  summary.seedArgs.registry = { firstOwner: owners[0], firstOperator: operators[0], otherFounders: owners.slice(1), genesisTimestamp };
  const regH = await inject("ValidatorsRegistry", "ValidatorsRegistry_GenesisSeed", [owners[0], operators[0], owners.slice(1), genesisTimestamp], { verifier: A("verifier"), ...(NET.regOverlay || {}) });
  const regGV = await regH.contract.getValidators();
  if (regGV.length !== 1 || regGV[0].toLowerCase() !== operators[0].toLowerCase()) throw new Error("seed getValidators mismatch: " + regGV);
  summary.seedArgs.registryHelperGetValidators = Array.from(regGV);

  // ValidatorSeatNFT: seats minted in the same order (ids 1..n)
  summary.seedArgs.seatNft = { founderOwners: owners };
  await inject("ValidatorSeatNFT", "ValidatorSeatNFT_GenesisSeed", [owners]);

  // ValidatorsBoard: 5 founding board members = owner1..owner5 (on single-founder nets owner2..5 are not registered validators)
  const boardMembers = [1, 2, 3, 4, 5].map((i) => A("owner" + i));
  summary.seedArgs.board = { members: boardMembers, genesisTimestamp };
  await inject("ValidatorsBoard", "ValidatorsBoard_GenesisSeed", [boardMembers, genesisTimestamp]);

  // FoundationMembers
  const fmArgs = [[A("fm1"), A("fm2"), A("fm3")], ["Test Member One", "Test Member Two", "Test Member Three"], [0, 0, 0], [ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress], [100n, 200n, 300n]];
  summary.seedArgs.foundationMembers = { accounts: fmArgs[0], names: fmArgs[1], shares: fmArgs[4].map(String) };
  await inject("FoundationMembers", "FoundationMembers_GenesisSeed", fmArgs);

  // FoundationDAO: 5 principals + 2 alternates, inspector, chair=dao1, treasurer=dao2, ceo
  const daoList = [1, 2, 3, 4, 5, 6, 7].map((i) => A("dao" + i));
  const termEnd = genesisTimestamp + 730 * 86400;
  summary.seedArgs.dao = { principalsAndAlternates: daoList, inspector: A("inspector"), chair: A("dao1"), treasurer: A("dao2"), ceo: A("ceo"), termEnd };
  await inject("FoundationDAO", "FoundationDAO_GenesisSeed", [daoList, A("inspector"), A("dao1"), A("dao2"), A("ceo"), termEnd]);
  alloc[FIXED.FoundationDAO.toLowerCase()].balance = hex(SUREN(20_000_000));

  // GenesisClaimsVault
  const claims = [SUREN(1000), SUREN(2400), SUREN(5000)];
  const claimants = [A("claimant1"), A("claimant2"), A("claimant3")];
  const claimsH = await inject("GenesisClaimsVault", "GenesisClaimsVault_GenesisSeed", [claimants, claims, genesisTimestamp]);
  const totalHeld = await claimsH.contract.totalHeld();
  alloc[FIXED.GenesisClaimsVault.toLowerCase()].balance = hex(totalHeld);
  summary.seedArgs.claims = { claimants, claims: claims.map(String), totalHeld: totalHeld.toString() };

  // contracts without a seed helper: deploy the contract itself (state-variable initialisers only)
  await inject("BlockRewardDistributor", "BlockRewardDistributor", [], { distributionOracle: A("distOracle") });
  await inject("ValidatorsTreasury", "ValidatorsTreasury", []);
  await inject("IdentityRegistry", "IdentityRegistry", [], { identityOracle: A("identityOracle") });
  await inject("ValidatorLottery", "ValidatorLottery", []);

  // ----- plain accounts
  const bal = (role, n) => { alloc[A(role).toLowerCase()] = { balance: hex(SUREN(n)) }; };
  for (let i = 1; i <= 7; i++) bal("owner" + i, 5000);
  bal("cand", 700_000); bal("buyer", 5000); bal("outsider", 5000);
  bal("verifier", 20000); bal("identityOracle", 20000); bal("distOracle", 20000);
  for (let i = 1; i <= 7; i++) bal("dao" + i, 5000);
  bal("inspector", 1000); bal("ceo", 5000);
  for (let i = 1; i <= 6; i++) bal("lot" + i, 5000);
  for (let i = 1; i <= 3; i++) bal("claimant" + i, 100);
  bal("tester", 20000);

  // ----- genesis.json (same fork / EVM settings as the v2.2 campaign nets: forks through London, zeroBaseFee, QBFT contract mode)
  const genesis = {
    config: {
      chainId: NET.chainId,
      homesteadBlock: 0, eip150Block: 0, eip155Block: 0, eip158Block: 0, byzantiumBlock: 0, constantinopleBlock: 0, petersburgBlock: 0,
      istanbulBlock: 0, berlinBlock: 0, londonBlock: 0, zeroBaseFee: true,
      qbft: {
        blockperiodseconds: BLOCK_PERIOD, epochlength: 30000, requesttimeoutseconds: 10,
        validatorcontractaddress: FIXED.ValidatorsRegistry,
        miningbeneficiary: FIXED.BlockRewardDistributor,
        blockreward: NET.blockreward,
      },
    },
    gasLimit: "0x1c9c380", difficulty: "0x1", timestamp: hex(genesisTimestamp),
    extraData: "0xe5a00000000000000000000000000000000000000000000000000000000000000000c0c080c0",
    alloc,
  };
  const netDir = path.join(E, "nets", NET.name);
  fs.mkdirSync(netDir, { recursive: true });
  fs.writeFileSync(path.join(netDir, "genesis.json"), JSON.stringify(genesis, null, 2));
  summary.genesisSha256 = crypto.createHash("sha256").update(fs.readFileSync(path.join(netDir, "genesis.json"))).digest("hex");
  summary.blockperiodseconds = BLOCK_PERIOD; summary.blockreward = NET.blockreward; summary.chainId = NET.chainId;

  // ----- node dirs
  const nodesInfo = [];
  NET.nodes.forEach((n, idx) => {
    const k = keys[NODE_OPERATOR[n]];
    const ip = `${NET.subnet}.${NODE_IPSUFFIX[n]}`;
    const pub = new ethers.SigningKey(k.privateKey).publicKey.slice(4);
    nodesInfo.push({ node: n, role: NODE_OPERATOR[n], operatorAddress: k.address, ip, p2p: 30303, rpcHostPort: NET.rpcBase + (NODE_IPSUFFIX[n]), enode: `enode://${pub}@${ip}:30303` });
  });
  for (const ni of nodesInfo) {
    const d = path.join(netDir, ni.node);
    fs.mkdirSync(d, { recursive: true });
    fs.writeFileSync(path.join(d, "key"), keys[ni.role].privateKey.replace(/^0x/, ""));
    fs.writeFileSync(path.join(d, "config.toml"),
`data-path="/data"
genesis-file="/net/genesis.json"
node-private-key-file="/net/${ni.node}/key"
p2p-host="${ni.ip}"
p2p-port=30303
rpc-http-enabled=true
rpc-http-host="0.0.0.0"
rpc-http-port=8545
rpc-http-api=["ETH","NET","QBFT","ADMIN","WEB3","DEBUG","TRACE","TXPOOL"]
rpc-http-cors-origins=["*"]
host-allowlist=["*"]
min-gas-price=100000000000000
discovery-enabled=true
sync-min-peers=1
`);
    fs.writeFileSync(path.join(d, "static-nodes.json"), JSON.stringify(nodesInfo.filter((x) => x.node !== ni.node).map((x) => x.enode), null, 2));
  }
  fs.writeFileSync(path.join(netDir, "nodes-info.json"), JSON.stringify(nodesInfo, null, 2));
  summary.nodes = nodesInfo;

  // ----- round-trip verification of the produced alloc on a fresh in-process deployment of the REAL contracts
  summary.roundTrip = {};
  async function realAt(name) {
    const art = await hre.artifacts.readArtifact(name);
    const f = new ethers.ContractFactory(art.abi, art.bytecode, signer);
    const c = await f.deploy();
    await c.waitForDeployment();
    const a = await c.getAddress();
    for (const [slot, v] of Object.entries(alloc[FIXED[name].toLowerCase()].storage)) await hre.network.provider.send("hardhat_setStorageAt", [a, hex(BigInt(slot)), v]);
    return c;
  }
  const reg = await realAt("ValidatorsRegistry");
  const rtv = await reg.getValidators();
  summary.roundTrip.registryGetValidators = Array.from(rtv);
  summary.roundTrip.registryVerifier = await reg.verifier();
  summary.roundTrip.registryGenesisTime = (await reg.genesisTime()).toString();
  summary.roundTrip.registryStatuses = {};
  for (const o of owners) summary.roundTrip.registryStatuses[o] = Number((await reg.validators(o)).status);
  const nft = await realAt("ValidatorSeatNFT");
  summary.roundTrip.nftTotalMinted = (await nft.totalMinted()).toString();
  summary.roundTrip.nftOwners = [];
  for (let i = 1; i <= nF; i++) summary.roundTrip.nftOwners.push(await nft.ownerOf(i));
  const dist = await realAt("BlockRewardDistributor");
  summary.roundTrip.distributionOracle = await dist.distributionOracle();
  const idr = await realAt("IdentityRegistry");
  summary.roundTrip.identityOracle = await idr.identityOracle();
  const dao = await realAt("FoundationDAO");
  summary.roundTrip.daoBoard = Array.from(await dao.getBoard());
  summary.roundTrip.daoCeo = await dao.ceo();
  const vb = await realAt("ValidatorsBoard");
  summary.roundTrip.boardMembers = Array.from(await vb.getBoardMembers());
  const cv = await realAt("GenesisClaimsVault");
  summary.roundTrip.claimsTotalHeld = (await cv.totalHeld()).toString();
  if (summary.roundTrip.registryVerifier !== A("verifier") || summary.roundTrip.distributionOracle !== A("distOracle") || summary.roundTrip.identityOracle !== A("identityOracle")) throw new Error("overlay round trip failed");
  if (rtv.length !== 1 || rtv[0] !== operators[0]) throw new Error("round trip getValidators");

  const evDir = path.join(E, "evidence", "02-genesis", NET.name);
  fs.mkdirSync(evDir, { recursive: true });
  fs.writeFileSync(path.join(evDir, "build-summary.json"), JSON.stringify(summary, null, 2));
  console.log(`[done] ${NET.name} genesis sha256 ${summary.genesisSha256}`);
}
main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
