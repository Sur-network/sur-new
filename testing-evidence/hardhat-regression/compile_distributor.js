const solc=require(process.env.SOLC_PATH || 'solc'),fs=require('fs');
const fi=p=>({contents:fs.readFileSync({'SurAddresses.sol':'contracts_src_SurAddresses.sol'}[p.replace('./','')],'utf8')});
const input={language:'Solidity',sources:{'D.sol':{content:fs.readFileSync('contracts_src_BlockRewardDistributor.sol','utf8')}},settings:{optimizer:{enabled:true,runs:200},outputSelection:{'*':{'*':['abi','evm.bytecode.object','storageLayout']}}}};
const o=JSON.parse(solc.compile(JSON.stringify(input),{import:fi}));const e=(o.errors||[]).filter(x=>x.severity==='error');if(e.length){console.log(e[0].formattedMessage);process.exit(1);}
const c=o.contracts['D.sol'].BlockRewardDistributor;fs.writeFileSync('distributor_artifact.json',JSON.stringify({abi:c.abi,bytecode:'0x'+c.evm.bytecode.object,layout:c.storageLayout}));console.log('ok distributor_artifact.json');
