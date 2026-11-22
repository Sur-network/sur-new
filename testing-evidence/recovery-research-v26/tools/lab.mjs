#!/usr/bin/env node
// lab.mjs — throw-away QBFT lab for the emergency-recovery research (round "r26"). Every Docker object is named sur25r-*.
// Usage (node 22): node lab.mjs <cmd> <exp> [...]
//   gen <exp> <spec.json>        build keys, genesis, configs under $LAB/<exp> (spec described below)
//   regen <exp> <transitions.json|-> [--set k=v ...]  rewrite ONLY genesis.json (same keys, same alloc, same timestamp) with a new transitions array
//   up <exp> [n1 n2 ...]         create network/volumes/containers (default all) — never pulls an image
//   stop|start|restart <exp> n1 [n2 ...]
//   rpc <exp> n1 <method> [paramsJson]
//   head <exp>                   head, validator set, timestamp of every running node
//   logs <exp> n1 [grep]         container log (optionally filtered)
//   down <exp>                   removes exactly sur25r-<exp>-* containers, volumes and the network
// spec: {forks:"london"|"cancun0"|"cancunG", subnet:91, portBase:18910, nodes:4, validators:[0,1,2,3], recovery:[0,1] (optional 2nd contract at 0x4444..),
//        requestTimeout:4, blockPeriod:2, transitions:[ ... ]}   ("now+N" strings in transitions' "block" are replaced by genesisNow+N at gen/regen time)
import fs from 'node:fs'; import path from 'node:path'; import { spawnSync } from 'node:child_process';
const VIEM = process.env.VIEM_PATH || 'file:///D:/Amir/Business/SUR/NewSur/Deployments/BesuLive/node_modules/viem/_esm/index.js';
const { generatePrivateKey, privateKeyToAccount } = await import(VIEM.replace('index.js', 'accounts/index.js'));
const { keccak256, padHex, toHex, hexToBigInt } = await import(VIEM);
const LAB = process.env.LAB || 'C:/Users/Amir/AppData/Local/Temp/claude/f77a4166e619fc45/348f193f-9c16-4fb0-9e02-a3c8377e94bd/scratchpad/labs';
const IMAGE = process.env.BESU_IMAGE || 'hyperledger/besu:26.9.0';
const P = 'sur25r-';
const rt = (f) => fs.readFileSync(new URL(f, import.meta.url), 'utf8').trim();
// shanghai build for Shanghai/Cancun genesis, london build (no PUSH0) for the London control
let RUNTIME = rt('./ToyValidators.runtime.hex');
const MAIN = '0x3333333333333333333333333333333333333333', RECOV = '0x4444444444444444444444444444444444444444';
const sh = (args, o = {}) => { const r = spawnSync('docker', args, { encoding: 'utf8', ...o }); return r; };
const dir = (e) => path.join(LAB, e);
const [cmd, exp, ...rest] = process.argv.slice(2);
if (exp && !/^[a-z0-9]+$/.test(exp)) throw new Error('exp must be [a-z0-9]+');
const st = () => JSON.parse(fs.readFileSync(path.join(dir(exp), 'state.json'), 'utf8'));
const cname = (n) => `${P}${exp}-${n}`, vname = (n) => `${P}${exp}-${n}-data`, nname = () => `${P}${exp}-net`;

function storageFor(addrs) {
  const s = { [padHex('0x0', { size: 32 })]: padHex(toHex(addrs.length), { size: 32 }) };
  const base = hexToBigInt(keccak256(padHex('0x0', { size: 32 })));
  addrs.forEach((a, i) => { s[padHex(toHex(base + BigInt(i)), { size: 32 })] = padHex(a, { size: 32 }); });
  return s;
}
function resolveTransitions(tr, now, nodes) {
  // block: "now+N" -> now+N ; validators: "@0,1" -> addresses of nodes 0,1 (0-based) ; "@ALL" -> all nodes
  return tr.map((t) => { const o = { ...t };
    if (typeof o.block === 'string' && o.block.startsWith('now+')) o.block = now + Number(o.block.slice(4));
    if (typeof o.validators === 'string') o.validators = (o.validators === '@ALL' ? nodes.map((_, i) => i) : o.validators.slice(1).split(',').map(Number)).map((i) => nodes[i].address);
    return o; });
}
function buildGenesis(S) {
  if (S.spec.forks === 'london') RUNTIME = rt('./ToyValidators.runtime.london.hex');
  const cfg = { chainId: 262026, homesteadBlock: 0, eip150Block: 0, eip155Block: 0, eip158Block: 0, byzantiumBlock: 0, constantinopleBlock: 0, petersburgBlock: 0, istanbulBlock: 0, berlinBlock: 0, londonBlock: 0 };
  if (S.spec.forks === 'cancun0') { cfg.shanghaiTime = 0; cfg.cancunTime = 0; }
  if (S.spec.forks === 'cancunG') { cfg.shanghaiTime = S.genesisTs; cfg.cancunTime = S.genesisTs; }
  cfg.zeroBaseFee = true;
  cfg.qbft = { blockperiodseconds: S.spec.blockPeriod ?? 2, epochlength: 30000, requesttimeoutseconds: S.spec.requestTimeout ?? 4, validatorcontractaddress: MAIN };
  const tr = resolveTransitions(S.transitions || [], S.now, S.nodes);
  if (tr.length) cfg.transitions = { qbft: tr };
  const alloc = { [MAIN]: { balance: '0x0', code: '0x' + RUNTIME, storage: storageFor(S.spec.validators.map((i) => S.nodes[i].address)) } };
  if (S.spec.recovery) alloc[RECOV] = { balance: '0x0', code: '0x' + RUNTIME, storage: storageFor(S.spec.recovery.map((i) => S.nodes[i].address)) };
  return { config: cfg, nonce: '0x0', timestamp: toHex(S.genesisTs), gasLimit: '0x2faf080', difficulty: '0x1',
    extraData: '0xe5a0' + '00'.repeat(32) + 'c0c080c0', alloc };
}
function writeNodeFiles(S) {
  const d = dir(exp);
  fs.writeFileSync(path.join(d, 'genesis.json'), JSON.stringify(buildGenesis(S), null, 2));
  S.nodes.forEach((n, i) => {
    const nd = path.join(d, n.name); fs.mkdirSync(nd, { recursive: true });
    fs.writeFileSync(path.join(nd, 'key'), n.key.slice(2));
    fs.writeFileSync(path.join(nd, 'static-nodes.json'), JSON.stringify(S.nodes.filter((_, j) => j !== i).map((m) => `enode://${m.pub}@${m.ip}:30303`)));
    fs.writeFileSync(path.join(nd, 'config.toml'), [
      'data-path="/data"', 'genesis-file="/net/genesis.json"', `node-private-key-file="/net/${n.name}/key"`, `p2p-host="${n.ip}"`, 'p2p-port=30303',
      'nat-method="NONE"', 'discovery-enabled=false', `static-nodes-file="/net/${n.name}/static-nodes.json"`, 'sync-mode="FULL"', 'data-storage-format="BONSAI"',
      'rpc-http-enabled=true', 'rpc-http-host="0.0.0.0"', 'rpc-http-port=8545', 'rpc-http-api=["ETH","NET","WEB3","QBFT","ADMIN","DEBUG"]', 'host-allowlist=["*"]',
      'min-gas-price=0', 'logging="INFO"', ''].join('\n'));
  });
}
async function rpc(port, method, params = []) {
  try { const r = await fetch(`http://127.0.0.1:${port}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }), signal: AbortSignal.timeout(5000) }); return (await r.json()); }
  catch (e) { return { error: String(e.message || e) }; }
}
const safeName = (n) => { if (!n.startsWith(P)) throw new Error('refusing non-sur25r object ' + n); return n; };

if (cmd === 'gen') {
  const spec = JSON.parse(fs.readFileSync(rest[0], 'utf8')); fs.mkdirSync(dir(exp), { recursive: true });
  const N = spec.nodes ?? 4, now = Math.floor(Date.now() / 1000);
  const nodes = [...Array(N)].map((_, i) => { const key = generatePrivateKey(), a = privateKeyToAccount(key); return { name: `n${i + 1}`, key, address: a.address, pub: a.publicKey.slice(4), ip: `172.29.${spec.subnet}.${11 + i}`, port: spec.portBase + i }; });
  const S = { exp, spec, nodes, genesisTs: now - 10, now, transitions: spec.transitions || [], note: 'THROW-AWAY KEYS — never reuse' };
  fs.writeFileSync(path.join(dir(exp), 'state.json'), JSON.stringify(S, null, 2)); writeNodeFiles(S);
  console.log(`generated ${exp}: genesisTs=${S.genesisTs} validators(contract)=${spec.validators.map((i) => nodes[i].address).join(',')}`);
} else if (cmd === 'regen') {
  const S = st(); const now = Math.floor(Date.now() / 1000);
  S.now = now; S.transitions = rest[0] === '-' ? [] : JSON.parse(fs.readFileSync(rest[0], 'utf8'));
  fs.writeFileSync(path.join(dir(exp), 'state.json'), JSON.stringify(S, null, 2)); writeNodeFiles(S);
  console.log(`regenerated genesis.json for ${exp} at now=${now}; transitions=${JSON.stringify(resolveTransitions(S.transitions, now, S.nodes))}`);
} else if (cmd === 'up') {
  const S = st(); const want = rest.length ? rest : S.nodes.map((n) => n.name);
  if (sh(['network', 'inspect', nname()]).status !== 0) {
    const r = sh(['network', 'create', '--driver', 'bridge', '--subnet', `172.29.${S.spec.subnet}.0/24`, '--gateway', `172.29.${S.spec.subnet}.1`, '--label', 'sur25r=1', nname()]);
    if (r.status) throw new Error('network: ' + r.stderr);
  }
  for (const n of S.nodes.filter((x) => want.includes(x.name))) {
    sh(['volume', 'create', '--label', 'sur25r=1', safeName(vname(n.name))]);
    const r = sh(['run', '-d', '--pull', 'never', '--name', safeName(cname(n.name)), '--network', nname(), '--ip', n.ip, '-p', `127.0.0.1:${n.port}:8545`, '--label', 'sur25r=1',
      '--memory', '1g', '--memory-swap', '1g', '--cpus', '1', '--restart', 'no', '--stop-timeout', '20', '--log-driver', 'json-file', '--log-opt', 'max-size=30m', '--log-opt', 'max-file=3',
      '-e', 'JAVA_OPTS=-Xms128m -Xmx512m', '-v', `${dir(exp)}:/net:ro`, '-v', `${vname(n.name)}:/data`, IMAGE, `--config-file=/net/${n.name}/config.toml`]);
    console.log(r.status ? 'FAIL ' + n.name + ' ' + r.stderr : `started ${cname(n.name)} rpc=127.0.0.1:${n.port}`);
  }
} else if (['stop', 'start', 'restart'].includes(cmd)) {
  for (const n of rest) { const r = sh([cmd, ...(cmd === 'stop' ? ['-t', '20'] : []), safeName(cname(n))]); console.log(cmd, cname(n), r.status ? r.stderr : 'ok'); }
} else if (cmd === 'rpc') {
  const S = st(); const n = S.nodes.find((x) => x.name === rest[0]); console.log(JSON.stringify(await rpc(n.port, rest[1], rest[2] ? JSON.parse(rest[2]) : [])));
} else if (cmd === 'head') {
  const S = st(); const out = [];
  for (const n of S.nodes) {
    const b = await rpc(n.port, 'eth_getBlockByNumber', ['latest', false]);
    if (!b.result) { out.push(`${n.name}: down`); continue; }
    const v = await rpc(n.port, 'qbft_getValidatorsByBlockNumber', ['latest']);
    const peers = await rpc(n.port, 'net_peerCount');
    out.push(`${n.name}: #${parseInt(b.result.number, 16)} ts=${parseInt(b.result.timestamp, 16)} peers=${parseInt(peers.result || '0x0', 16)} validators=[${(v.result || []).map((a) => S.nodes.findIndex((m) => m.address.toLowerCase() === a.toLowerCase()) + 1 || a).join(',')}] miner=${S.nodes.findIndex((m) => m.address.toLowerCase() === b.result.miner.toLowerCase()) + 1}`);
  }
  console.log(`now=${Math.floor(Date.now() / 1000)}\n` + out.join('\n'));
} else if (cmd === 'logs') {
  const r = sh(['logs', safeName(cname(rest[0]))], { maxBuffer: 1 << 28 }); let t = (r.stdout || '') + (r.stderr || '');
  if (rest[1]) t = t.split('\n').filter((l) => new RegExp(rest[1]).test(l)).join('\n'); console.log(t);
} else if (cmd === 'down') {
  const S = st();
  for (const n of S.nodes) { sh(['rm', '-f', '-v', safeName(cname(n.name))]); sh(['volume', 'rm', '-f', safeName(vname(n.name))]); }
  sh(['network', 'rm', safeName(nname())]); console.log('removed', P + exp + '-*');
} else { console.error('unknown command'); process.exit(2); }
