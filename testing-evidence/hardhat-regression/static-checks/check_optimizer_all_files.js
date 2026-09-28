const solc=require(process.env.SOLC_PATH || 'solc'),fs=require('fs'),path=require('path'),cp=require('child_process');
let bad=0,n=0;
for (const lang of ['contracts','contracts-fa']) {
  const files=cp.execSync(`find ${lang} -name "*.sol"`).toString().trim().split('\n').sort();
  for (const f of files) {
    n++;
    const fi=p=>{for(const d of [lang,lang+'/genesis-seed-helpers',lang+'/reference-dapps']){const fp=path.join(d,p.replace('./','').replace('../',''));if(fs.existsSync(fp))return{contents:fs.readFileSync(fp,'utf8')};}return{error:'nf'};};
    const input={language:'Solidity',sources:{'x.sol':{content:fs.readFileSync(f,'utf8')}},settings:{optimizer:{enabled:true,runs:200},outputSelection:{'*':{'*':['abi','evm.bytecode.object']}}}};
    const out=JSON.parse(solc.compile(JSON.stringify(input),{import:fi}));
    const errs=(out.errors||[]).filter(e=>e.severity==='error');
    if(errs.length){bad++;console.log('❌',f,':',errs[0].message.split('\n')[0]);}
  }
}
console.log(`optimizer: ${n} فایل بررسی شد، ${bad} خطا`);
