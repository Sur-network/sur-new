// Genesis builder for the SOAK KIT (adapted from testing-evidence/besu-live-test-v25-2026-11-19/scripts/build-genesis.js).
// Run from the kit root:  SOAK_NET=n7 node $NODE_PATH/hardhat/internal/cli/cli.js --config tools/hh/hardhat.config.js run tools/build-genesis.js
//
// "Simulate-and-extract": every structural contract is deployed through its *_GenesisSeed helper (which INHERITS the real contract)
// on a temporary in-process Hardhat network; every storage slot touched by the deployment is read back and written under the fixed
// address together with the REAL contract's runtime bytecode into genesis.json `alloc`. Same fixed addresses as round 1.
//
// Validators: like round 1 only the FIRST founder (owner1, operator op1) is Active at genesis. The other founders (and one extra
// "entrant", owner8) are seeded in Probation. The kit's bootstrap step (runtime/bootstrap.js) activates owner2..ownerN through the
// real Registry flow (setOperator + Verifier.recordActivation) before the soak clock starts. See README "Deviations".
//
// Test-only overlay (same as round 1, D-2): the three oracle addresses of SurAddresses.sol have no known private keys, so their
// storage slots (Registry.verifier, Distributor.distributionOracle, IdentityRegistry.identityOracle) are overwritten with throw-away
// test-key addresses. Runtime bytecode is unchanged.
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

const NET_DEFS = {
  n7: { chainId: 725007, validators: 7 },
  n4: { chainId: 725004, validators: 4 },
};
const netKey = process.env.SOAK_NET;
if (!NET_DEFS[netKey]) throw new Error("set SOAK_NET to one of " + Object.keys(NET_DEFS));
const V = NET_DEFS[netKey].validators;
const NET = {
  name: netKey, chainId: NET_DEFS[netKey].chainId, validators: V,
  subnetDefault: "172.29.71", rpcBase: 19600, blockreward: "2000000000000000000",
  nodes: [...Array.from({ length: V }, (_, i) => "n" + (i + 1)), "x1", "x2"],
  nodeOperator: Object.fromEntries([...Array.from({ length: V }, (_, i) => ["n" + (i + 1), "op" + (i + 1)]), ["x1", "opX1"], ["x2", "opE"]]),
  nodeIpSuffix: Object.fromEntries([...Array.from({ length: V }, (_, i) => ["n" + (i + 1), 11 + i]), ["x1", 21], ["x2", 22]]),
  swapOwner: "owner" + (V - 1), swapOps: ["op" + (V - 1), "opX1"], suspendOwner: "owner" + V,
  entrantOwner: "owner8", entrantOp: "opE",
};
const BLOCK_PERIOD = Number(process.env.SOAK_BLOCKPERIOD || 2);
const GENESIS_TS = Number(process.env.SOAK_GENESIS_TS || Math.floor(Date.now() / 1000) - 60);

async function main() {
  const provider = new ethers.BrowserProvider(hre.network.provider);
  const signer = await provider.getSigner(0);
  const genesisTimestamp = GENESIS_TS;
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
    console.log(`[inject] ${realName} <- ${helperName}: ${codeBytes} bytes, ${Object.keys(storage).length} slots`);
    return h;
  }

  // ----- founders: owner1..ownerV become validators (owner1 at genesis, the rest by the bootstrap step); owner8 is the entrant (stays Probation)
  const owners = []; const operators = [];
  for (let i = 1; i <= V; i++) { owners.push(A("owner" + i)); operators.push(A("op" + i)); }
  owners.push(A(NET.entrantOwner)); // seeded as a founder in Probation, never given an operator at genesis
  summary.seedArgs.registry = { firstOwner: owners[0], firstOperator: operators[0], otherFounders: owners.slice(1), genesisTimestamp };
  const regH = await inject("ValidatorsRegistry", "ValidatorsRegistry_GenesisSeed", [owners[0], operators[0], owners.slice(1), genesisTimestamp], { verifier: A("verifier") });
  const regGV = await regH.contract.getValidators();
  if (regGV.length !== 1 || regGV[0].toLowerCase() !== operators[0].toLowerCase()) throw new Error("seed getValidators mismatch: " + regGV);

  summary.seedArgs.seatNft = { founderOwners: owners };
  await inject("ValidatorSeatNFT", "ValidatorSeatNFT_GenesisSeed", [owners]);

  // Validators board: 5 founding members. Seat holders of the board cannot selfSuspend, so the owners the load generator suspends
  // (suspendOwner) must NOT be on it: n7 -> owner1..5; n4 -> owner1, owner2 + owner9..11 (owner3 swaps, owner4 suspends).
  const boardRoles = V === 7 ? [1, 2, 3, 4, 5].map((i) => "owner" + i) : ["owner1", "owner2", "owner9", "owner10", "owner11"];
  const boardMembers = boardRoles.map(A);
  summary.seedArgs.board = { roles: boardRoles, members: boardMembers, genesisTimestamp };
  await inject("ValidatorsBoard", "ValidatorsBoard_GenesisSeed", [boardMembers, genesisTimestamp]);

  const fmArgs = [[A("fm1"), A("fm2"), A("fm3")], ["Test Member One", "Test Member Two", "Test Member Three"], [0, 0, 0], [ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress], [100n, 200n, 300n]];
  await inject("FoundationMembers", "FoundationMembers_GenesisSeed", fmArgs);

  const daoList = [1, 2, 3, 4, 5, 6, 7].map((i) => A("dao" + i));
  const termEnd = genesisTimestamp + 730 * 86400;
  await inject("FoundationDAO", "FoundationDAO_GenesisSeed", [daoList, A("inspector"), A("dao1"), A("dao2"), A("ceo"), termEnd]);
  alloc[FIXED.FoundationDAO.toLowerCase()].balance = hex(SUREN(20_000_000));

  const claims = [SUREN(1000), SUREN(2400), SUREN(5000)];
  const claimants = [A("claimant1"), A("claimant2"), A("claimant3")];
  const claimsH = await inject("GenesisClaimsVault", "GenesisClaimsVault_GenesisSeed", [claimants, claims, genesisTimestamp]);
  alloc[FIXED.GenesisClaimsVault.toLowerCase()].balance = hex(await claimsH.contract.totalHeld());

  await inject("BlockRewardDistributor", "BlockRewardDistributor", [], { distributionOracle: A("distOracle") });
  await inject("ValidatorsTreasury", "ValidatorsTreasury", []);
  await inject("IdentityRegistry", "IdentityRegistry", [], { identityOracle: A("identityOracle") });
  await inject("ValidatorLottery", "ValidatorLottery", []);

  // ----- plain accounts (generous balances: the soak pays 1e14 wei x gas per transaction for days)
  const bal = (role, n) => { alloc[A(role).toLowerCase()] = { balance: hex(SUREN(n)) }; };
  for (let i = 1; i <= 8; i++) bal("owner" + i, 1_000_000);
  bal("verifier", 10_000_000); bal("identityOracle", 10_000_000); bal("distOracle", 20000);
  for (let i = 1; i <= 8; i++) bal("lg" + i, 1_000_000_000);

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

  // ----- node dirs: static-nodes enodes use FIXED container IPs <subnet>.<suffix>; the subnet is the kit default 172.29.71 and
  // run-soak.sh refuses to run if SOAK_SUBNET differs (the enodes are baked into nets/*/*/static-nodes.json).
  const nodesInfo = NET.nodes.map((n) => {
    const k = keys[NET.nodeOperator[n]];
    const ip = `${NET.subnetDefault}.${NET.nodeIpSuffix[n]}`;
    const pub = new ethers.SigningKey(k.privateKey).publicKey.slice(4);
    return { node: n, role: NET.nodeOperator[n], operatorAddress: k.address, ip, rpcHostPort: NET.rpcBase + NET.nodeIpSuffix[n], enode: `enode://${pub}@${ip}:30303` };
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
rpc-http-api=["ETH","NET","QBFT","ADMIN","WEB3","TXPOOL"]
rpc-http-cors-origins=["*"]
host-allowlist=["*"]
min-gas-price=100000000000000
discovery-enabled=true
sync-min-peers=1
`);
    fs.writeFileSync(path.join(d, "static-nodes.json"), JSON.stringify(nodesInfo.filter((x) => x.node !== ni.node).map((x) => x.enode), null, 2));
  }
  fs.writeFileSync(path.join(netDir, "nodes-info.json"), JSON.stringify(nodesInfo, null, 2));
  // plain-text table for the shell scripts (no jq on the server): name ip rpcHostPort operatorAddress
  fs.writeFileSync(path.join(netDir, "nodes.tsv"), nodesInfo.map((x) => [x.node, x.ip, x.rpcHostPort, x.operatorAddress].join("\t")).join("\n") + "\n");
  const soakNet = {
    name: NET.name, chainId: NET.chainId, validators: V, genesisTimestamp, blockPeriodSeconds: BLOCK_PERIOD,
    validatorNodes: NET.nodes.slice(0, V), extraNodes: ["x1", "x2"], nodeOperator: NET.nodeOperator,
    owners: Object.fromEntries([...Array.from({ length: V }, (_, i) => ["owner" + (i + 1), "op" + (i + 1)]), [NET.entrantOwner, NET.entrantOp]]),
    swapOwner: NET.swapOwner, swapOps: NET.swapOps, swapNodes: { [NET.swapOps[0]]: "n" + (V - 1), opX1: "x1" },
    suspendOwner: NET.suspendOwner, entrantOwner: NET.entrantOwner, entrantOp: NET.entrantOp, entrantNode: "x2",
    boardRoles, addr: Object.fromEntries(Object.entries(FIXED).map(([k, v]) => [k, v])),
  };
  fs.writeFileSync(path.join(netDir, "soak-net.json"), JSON.stringify(soakNet, null, 2));
  summary.nodes = nodesInfo;

  // ----- round trip: apply the alloc storage to freshly deployed REAL contracts and read back
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
  summary.roundTrip = { registryGetValidators: Array.from(rtv), registryVerifier: await reg.verifier(), statuses: {} };
  for (const o of owners) summary.roundTrip.statuses[o] = Number((await reg.validators(o)).status);
  const dist = await realAt("BlockRewardDistributor"); const idr = await realAt("IdentityRegistry");
  if (summary.roundTrip.registryVerifier !== A("verifier") || (await dist.distributionOracle()) !== A("distOracle") || (await idr.identityOracle()) !== A("identityOracle")) throw new Error("overlay round trip failed");
  if (rtv.length !== 1 || rtv[0] !== operators[0]) throw new Error("round trip getValidators");

  // ----- ABIs for the runtime scripts (only what the load generator and bootstrap call)
  const want = {
    ValidatorsRegistry: ["getValidators", "getActiveOwners", "validators", "operatorOf", "ownerOfOperator", "pendingOperator", "setOperator", "proposeOperator", "confirmOperatorReady", "cancelOperatorChange",
      "recordActivation", "selfSuspend", "requestResume", "recordResume", "resumeRequested", "verifier"],
    IdentityRegistry: ["registerIdentity", "setPhoneVerified", "setTelegramVerified", "isFullyVerified", "identityOracle"],
  };
  const abis = {};
  for (const [name, fns] of Object.entries(want)) {
    const art = await hre.artifacts.readArtifact(name);
    abis[name] = fns.map((f) => { const x = art.abi.find((e) => e.type === "function" && e.name === f); if (!x) throw new Error("ABI function missing: " + name + "." + f); return x; });
  }
  fs.writeFileSync(path.join(E, "runtime", "abi.json"), JSON.stringify(abis, null, 1));

  fs.mkdirSync(path.join(E, "nets", "_build-summaries"), { recursive: true });
  fs.writeFileSync(path.join(E, "nets", "_build-summaries", NET.name + "-build-summary.json"), JSON.stringify(summary, null, 2));
  console.log(`[done] ${NET.name} genesis sha256 ${summary.genesisSha256}`);
}
main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
