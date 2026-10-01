const solc = require(process.env.SOLC_PATH || 'solc'); const fs = require('fs'); const path = require('path');
function layout(file, name) {
  const dir = path.dirname(file);
  const input = { language:'Solidity', sources:{'x.sol':{content:fs.readFileSync(file,'utf8')}}, settings:{outputSelection:{'*':{'*':['storageLayout']}}} };
  const out = JSON.parse(solc.compile(JSON.stringify(input), {import:(p)=>{const fp=path.join(dir,p.replace('./',''));const fp2=path.join(path.dirname(dir),p.replace('./',''));
     if(fs.existsSync(fp))return{contents:fs.readFileSync(fp,'utf8')}; if(fs.existsSync(fp2))return{contents:fs.readFileSync(fp2,'utf8')}; return{error:'nf'};}}));
  const errs=(out.errors||[]).filter(e=>e.severity==='error'); if(errs.length){console.log(errs[0].formattedMessage);process.exit(1);}
  return out.contracts['x.sol'][name].storageLayout;
}
function describe(l){ // label -> {slot, offset, shape}
  // L04: structural, recursive shape description — contract-qualified type names (e.g. "struct X.Foo" vs "struct X_GenesisSeed.Foo")
  // are stripped so identical layouts compare equal; nested mapping -> array<struct> is described by its members, not by its name.
  const strip=lbl=>lbl.replace(/struct [A-Za-z0-9_]+\./g,'struct ').replace(/enum [A-Za-z0-9_]+\./g,'enum ');
  const shapeOf=(tid,depth=0)=>{ const t=l.types[tid]; if(depth>6) return strip(t.label);
    if(t.encoding==='mapping') return 'mapping('+strip(l.types[t.key].label)+')->'+shapeOf(t.value,depth+1);
    if(t.members) return 'struct{'+t.members.map(x=>x.label+':'+x.slot+'/'+x.offset+':'+shapeOf(x.type,depth+1)).join(',')+'}';
    if((t.encoding==='dynamic_array'||/\[\d*\]$/.test(t.label)) && t.base) return (t.encoding==='dynamic_array'?'array<':'fixedarray<')+shapeOf(t.base,depth+1)+'>';
    return strip(t.label); };
  const m={}; for(const s of l.storage){ m[s.label]={slot:s.slot,offset:s.offset,shape:shapeOf(s.type)}; } return m; }
// ✅ FIXED (independent review, 2026-09-29): two real defects fixed here.
// (1) A helper-only variable whose name matches this padding convention (e.g. `__gap1`) is a
//     DELIBERATE slot-reservation placeholder (see ValidatorsRegistry_GenesisSeed.sol's own doc
//     comment on it) — it is expected to have no same-named counterpart in the real contract, and
//     must NOT be reported as a mismatch. Only genuinely unexpected helper-only names are bad.
// (2) This script never called process.exit(1) on a real mismatch, so a broken layout would print
//     "❌" but still exit 0 — indistinguishable from success to any caller checking the exit code
//     (including this bundle's own README, which documents "exit 0" as the pass criterion for
//     every static check). It now tracks failures across all pairs and exits 1 if any real
//     mismatch (not a recognized gap) was found.
const GAP_PATTERN = /^__gap\d*$/;
let anyBad = false;
for (const lang of ['contracts','contracts-fa']) {
  for (const [real, helper] of [['ValidatorsRegistry','ValidatorsRegistry_GenesisSeed'],['ValidatorsBoard','ValidatorsBoard_GenesisSeed'],['FoundationDAO','FoundationDAO_GenesisSeed']]) {
    const R=describe(layout(`${lang}/${real}.sol`,real)), H=describe(layout(`${lang}/genesis-seed-helpers/${helper}.sol`,helper));
    let bad=[]; for(const k of Object.keys(H)){ if(GAP_PATTERN.test(k)) continue; if(!R[k]) bad.push(`helper-only var: ${k}`); else if(R[k].slot!==H[k].slot||R[k].offset!==H[k].offset) bad.push(`SLOT MISMATCH ${k}: real ${R[k].slot}/${R[k].offset} vs helper ${H[k].slot}/${H[k].offset}`); else if(R[k].shape!==H[k].shape) bad.push(`SHAPE MISMATCH ${k}: ${R[k].shape} vs ${H[k].shape}`); }
    const missing=Object.keys(R).filter(k=>!H[k]);
    if (bad.length) anyBad = true;
    console.log(`${lang}/${real}: ${bad.length? '❌ '+bad.join(' | ') : '✅ تمام متغیرهای helper با قرارداد واقعی هم‌slot و هم‌شکل‌اند (فاصله‌های عمدیِ __gap* نادیده گرفته شدند)'}${missing.length?'  | در helper نیستند: '+missing.join(', '):''}`);
  }
}
process.exit(anyBad ? 1 : 0);
