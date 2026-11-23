// Markdown (whitepaper) -> JSON blocks for the Word booklet builder. No dependencies.
import fs from 'node:fs';
const [,, inp, out] = process.argv;
const lines = fs.readFileSync(inp, 'utf8').replace(/^\uFEFF/, '').split(/\r?\n/);
function inline(s) {
  const segs = []; let i = 0, b = false, c = false, buf = '';
  const flush = () => { if (buf) { segs.push({ s: buf, b, c }); buf = ''; } };
  while (i < s.length) {
    if (s.startsWith('**', i)) { flush(); b = !b; i += 2; continue; }
    if (s[i] === '`') { flush(); c = !c; i++; continue; }
    buf += s[i++];
  }
  flush(); return segs;
}
const blocks = [];
let i = 0;
while (i < lines.length) {
  const L = lines[i];
  if (!L.trim()) { i++; continue; }
  let m;
  if ((m = /^(#{1,4}) (.*)$/.exec(L))) { blocks.push({ t: 'h', l: m[1].length, text: m[2].replace(/\*\*/g, '').trim() }); i++; continue; }
  if (/^---+\s*$/.test(L)) { blocks.push({ t: 'hr' }); i++; continue; }
  if (L.startsWith('|')) {
    const rows = [];
    while (i < lines.length && lines[i].startsWith('|')) {
      const cells = lines[i].trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map(x => x.trim());
      if (!cells.every(x => /^:?-{2,}:?$/.test(x))) rows.push(cells.map(inline));
      i++;
    }
    blocks.push({ t: 'table', rows }); continue;
  }
  if (L.startsWith('>')) {
    const parts = [];
    while (i < lines.length && lines[i].startsWith('>')) { parts.push(lines[i].replace(/^>\s?/, '')); i++; }
    blocks.push({ t: 'quote', segs: inline(parts.join(' ')) }); continue;
  }
  if ((m = /^- (.*)$/.exec(L))) { blocks.push({ t: 'li', segs: inline(m[1]) }); i++; continue; }
  if ((m = /^(\d+)\. (.*)$/.exec(L))) { blocks.push({ t: 'ol', n: m[1], segs: inline(m[2]) }); i++; continue; }
  blocks.push({ t: 'p', segs: inline(L.trim()) }); i++;
}
fs.writeFileSync(out, JSON.stringify(blocks), 'utf8');
const cnt = {}; blocks.forEach(b => cnt[b.t] = (cnt[b.t] || 0) + 1); console.log(cnt);
