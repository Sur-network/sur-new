# Builds the executive summary as a compact A4 Word file (no cover, no contents page) plus a PDF.
param([string]$OutDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$blocks = Join-Path $here '.summary-a4-blocks.json'
& node (Join-Path $here 'md2blocks.mjs') (Join-Path $OutDir 'sur-whitepaper-executive-summary.md') $blocks | Out-Null
& (Join-Path $here 'build-booklet.ps1') -BlocksPath $blocks -Compact -NoChapterBreaks `
  -Out (Join-Path $OutDir 'sur-whitepaper-executive-summary-A4-NOT-FOR-PUBLICATION.docx') `
  -Pdf (Join-Path $OutDir 'sur-whitepaper-executive-summary-A4-NOT-FOR-PUBLICATION.pdf') `
  -HeaderText 'خلاصهٔ مدیریتی سپیدنامهٔ بلاک‌چین سور' `
  -DocTitle 'خلاصهٔ مدیریتی سپیدنامهٔ بلاک‌چین سور (غیر قابل انتشار)'
Remove-Item $blocks -ErrorAction SilentlyContinue
