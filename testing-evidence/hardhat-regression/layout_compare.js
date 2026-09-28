const solc = require('solc'); const fs = require('fs'); const path = require('path');
function layout(file, name) {
  const dir = path.dirname(file);
  const input = { language:'Solidity', sources:{'x.sol':{content:fs.readFileSync(file,'utf8')}}, settings:{outputSelection:{'*':{'*':['storageLayout']}}} };
  const out = JSON.parse(solc.compile(JSON.stringify(input), {import:(p)=>{const fp=path.join(dir,p.replace('./',''));const fp2=path.join(path.dirname(dir),p.replace('./',''));
     if(fs.existsSync(fp))return{contents:fs.readFileSync(fp,'utf8')}; if(fs.existsSync(fp2))return{contents:fs.readFileSync(fp2,'utf8')}; return{error:'nf'};}}));
  const errs=(out.errors||[]).filter(e=>e.severity==='error'); if(errs.length){console.log(errs[0].formattedMessage);process.exit(1);}
  return out.contracts['x.sol'][name].storageLayout;
}
function describe(l){ // label -> {slot, offset, shape}
  const m={}; for(const s of l.storage){ const t=l.types[s.type]; let shape=t.label;
    if(t.encoding==='mapping'){const vt=l.types[t.value]; shape='mapping->'+(vt.members?vt.members.map(x=>x.label+':'+x.slot).join(','):vt.label);} 
    if(t.encoding==='dynamic_array' && t.base){ const bt=l.types[t.base]; if(bt.members) shape='array<struct>->'+bt.members.map(x=>x.label+':'+x.slot+'/'+x.offset+':'+l.types[x.type].label).join(','); }
    m[s.label]={slot:s.slot,offset:s.offset,shape}; } return m; }
for (const lang of ['contracts','contracts-fa']) {
  for (const [real, helper] of [['ValidatorsRegistry','ValidatorsRegistry_GenesisSeed'],['ValidatorsBoard','ValidatorsBoard_GenesisSeed'],['FoundationDAO','FoundationDAO_GenesisSeed']]) {
    const R=describe(layout(`${lang}/${real}.sol`,real)), H=describe(layout(`${lang}/genesis-seed-helpers/${helper}.sol`,helper));
    let bad=[]; for(const k of Object.keys(H)){ if(!R[k]) bad.push(`helper-only var: ${k}`); else if(R[k].slot!==H[k].slot||R[k].offset!==H[k].offset) bad.push(`SLOT MISMATCH ${k}: real ${R[k].slot}/${R[k].offset} vs helper ${H[k].slot}/${H[k].offset}`); else if(R[k].shape!==H[k].shape) bad.push(`SHAPE MISMATCH ${k}: ${R[k].shape} vs ${H[k].shape}`); }
    const missing=Object.keys(R).filter(k=>!H[k]);
    console.log(`${lang}/${real}: ${bad.length? '❌ '+bad.join(' | ') : '✅ تمام متغیرهای helper با قرارداد واقعی هم‌slot و هم‌شکل‌اند'}${missing.length?'  | در helper نیستند: '+missing.join(', '):''}`);
  }
}
