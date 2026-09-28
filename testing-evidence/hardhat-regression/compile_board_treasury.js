// Produces board_artifact.json and treasury_artifact.json (needed by reproduce_bug3/bug5). Run after copying the
// current contracts as contracts_src_ValidatorsBoard.sol / contracts_src_ValidatorsTreasury.sol / contracts_src_SurAddresses.sol
const solc = require('solc'); const fs = require('fs');
function fi(p){ const m={'SurAddresses.sol':'contracts_src_SurAddresses.sol'}; const f=m[p.replace('./','')]; return f?{contents:fs.readFileSync(f,'utf8')}:{error:'nf'}; }
for (const [file,name,out] of [['contracts_src_ValidatorsBoard.sol','ValidatorsBoard','board_artifact.json'],['contracts_src_ValidatorsTreasury.sol','ValidatorsTreasury','treasury_artifact.json']]) {
  const input={language:'Solidity',sources:{[name+'.sol']:{content:fs.readFileSync(file,'utf8')}},settings:{optimizer:{enabled:true,runs:200},outputSelection:{'*':{'*':['abi','evm.bytecode.object','storageLayout']}}}};
  const o=JSON.parse(solc.compile(JSON.stringify(input),{import:fi})); const errs=(o.errors||[]).filter(e=>e.severity==='error');
  if(errs.length){console.log(errs[0].formattedMessage);process.exit(1);}
  const c=o.contracts[name+'.sol'][name]; fs.writeFileSync(out,JSON.stringify({abi:c.abi,bytecode:'0x'+c.evm.bytecode.object,layout:c.storageLayout})); console.log('ok',out);
}
