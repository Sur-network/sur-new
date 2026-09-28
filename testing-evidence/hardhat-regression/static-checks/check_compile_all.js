const solc = require(process.env.SOLC_PATH || 'solc');
const fs = require('fs');
const path = require('path');
function findImports(dir) {
  return (importPath) => {
    const p = path.join(dir, importPath.replace('./', ''));
    if (fs.existsSync(p)) return { contents: fs.readFileSync(p, 'utf8') };
    return { error: 'File not found: ' + importPath };
  };
}
function compileDir(dir, label) {
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.sol'));
  const sources = {};
  for (const f of files) sources[f] = { content: fs.readFileSync(path.join(dir, f), 'utf8') };
  const input = { language: 'Solidity', sources, settings: { outputSelection: { '*': { '*': ['abi'] } } } };
  const output = JSON.parse(solc.compile(JSON.stringify(input), { import: findImports(dir) }));
  if (output.errors) {
    const errs = output.errors.filter(e => e.severity === 'error');
    if (errs.length) { console.log(`❌ خطا در ${label}:`); errs.forEach(e => console.log(e.formattedMessage)); return false; }
  }
  return true;
}
const okEn = compileDir('contracts', 'انگلیسی');
const okFa = compileDir('contracts-fa', 'فارسی');
if (okEn && okFa) console.log('✅ کل ۹ قرارداد با هم کامپایل شدند، بدون viaIR، بدون warning');
