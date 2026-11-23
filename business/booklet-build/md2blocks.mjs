// Markdown (whitepaper) -> JSON blocks for the Word booklet builder. No dependencies.
// Status markers (✅ 🔶 ⚠️ ⏸️) that follow other text start a new line (a manual line break, "\u000B").
import fs from 'node:fs';
const [,, inp, out] = process.argv;
const lines = fs.readFileSync(inp, 'utf8').replace(/^﻿/, '').split(/\r?\n/);

const MARK = /(✅|🔶|⚠️|⚠|⏸️|⏸)/u;
const MARK_G = /(✅|🔶|⚠️|⚠|⏸️|⏸)/gu;
const isMarkOnly = s => s.replace(MARK_G, '').replace(/[\s️·]/g, '') === '';

function inline(s) {
  const segs = []; let i = 0, b = false, c = false, buf = '';
  const flush = () => { if (buf) { segs.push({ s: buf, b, c }); buf = ''; } };
  while (i < s.length) {
    if (s.startsWith('**', i)) { flush(); b = !b; i += 2; continue; }
    if (s[i] === '`') { flush(); c = !c; i++; continue; }
    buf += s[i++];
  }
  flush(); return breakBeforeMarkers(segs);
}

// Insert a line break before every marker that has real text before it in the same paragraph/cell.
// A marker directly after another marker (e.g. "⚠️ 🔶") stays on the same line.
function breakBeforeMarkers(segs) {
  let before = '';                       // everything emitted so far in this paragraph
  const outSegs = [];
  for (const sg of segs) {
    if (sg.c) { outSegs.push(sg); before += sg.s; continue; }
    let text = sg.s, res = '';
    while (true) {
      const m = MARK.exec(text);
      if (!m) { res += text; break; }
      const head = text.slice(0, m.index);
      const sofar = before + res + head;
      const tail = sofar.replace(/[\s·]+$/u, '');
      // no break when the marker is only being referred to, e.g. "(علامت ✅: ...)"
      const referred = /(علامت|\()\s*$/u.test(sofar);
      const needBreak = tail.length > 0 && !referred && !isMarkOnly(sofar) && !MARK.test(tail.slice(-2));
      if (needBreak) {
        // trim spaces / middle dots right before the marker (possibly at the end of the previous segment)
        let h = head.replace(/[\s·]+$/u, '');
        if (h.length === 0 && res.length === 0 && outSegs.length) {
          const prev = outSegs[outSegs.length - 1];
          if (!prev.c) prev.s = prev.s.replace(/[\s·]+$/u, '');
        }
        res = res.replace(/[\s·]+$/u, '') + h + '\u000B' + m[0];
      } else {
        res += head + m[0];
      }
      text = text.slice(m.index + m[0].length);
    }
    outSegs.push({ ...sg, s: res });
    before += res;
  }
  return outSegs.filter(x => x.s.length);
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
  if ((m = /^\s{2,}- (.*)$/.exec(L))) { blocks.push({ t: 'li2', segs: inline(m[1]) }); i++; continue; }
  if ((m = /^(\d+)\. (.*)$/.exec(L))) { blocks.push({ t: 'ol', n: m[1], segs: inline(m[2]) }); i++; continue; }
  blocks.push({ t: 'p', segs: inline(L.trim()) }); i++;
}
fs.writeFileSync(out, JSON.stringify(blocks), 'utf8');
const cnt = {}; blocks.forEach(b => cnt[b.t] = (cnt[b.t] || 0) + 1); console.log(cnt);
