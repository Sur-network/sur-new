const solc = require('solc');
const fs = require('fs');

function findImports(importPath) {
  const clean = importPath.replace('./', '');
  const map = {
    'ValidatorsRegistry.sol': 'contracts_src_ValidatorsRegistry.sol',
    'SurAddresses.sol': 'contracts_src_SurAddresses.sol',
  };
  const p = map[clean];
  if (p && fs.existsSync(p)) return { contents: fs.readFileSync(p, 'utf8') };
  return { error: 'File not found: ' + importPath };
}

const mockSrc = 'pragma solidity ^0.8.24; contract Mock { receive() external payable {} function receiveMembershipFee() external payable {} }';

const input = {
  language: 'Solidity',
  sources: {
    'ValidatorsRegistry.sol': { content: fs.readFileSync('contracts_src_ValidatorsRegistry.sol', 'utf8') },
    'Mock.sol': { content: mockSrc },
  },
  settings: {
    optimizer: { enabled: true, runs: 200 },
    outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object', 'evm.deployedBytecode.object', 'storageLayout'] } }
  }
};

const output = JSON.parse(solc.compile(JSON.stringify(input), { import: findImports }));
if (output.errors) {
  const errs = output.errors.filter(e => e.severity === 'error');
  if (errs.length) { console.log(JSON.stringify(errs, null, 2)); process.exit(1); }
}
const reg = output.contracts['ValidatorsRegistry.sol']['ValidatorsRegistry'];
const mock = output.contracts['Mock.sol']['Mock'];
fs.writeFileSync('artifacts3.json', JSON.stringify({
  registry: { abi: reg.abi, bytecode: '0x' + reg.evm.bytecode.object },
  mock: { abi: mock.abi, bytecode: '0x' + mock.evm.bytecode.object, deployedBytecode: '0x' + mock.evm.deployedBytecode.object },
  layout: reg.storageLayout
}));
console.log('✅ کامپایل موفق');
