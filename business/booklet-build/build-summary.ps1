# Builds the executive summary (Word + PDF) with the same look as the whitepaper booklet.
param([string]$OutDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$blocks = Join-Path $here '.summary-blocks.json'
$cover  = Join-Path $here 'art\cover-summary.png'
& node (Join-Path $here 'md2blocks.mjs') (Join-Path $OutDir 'sur-whitepaper-executive-summary.md') $blocks | Out-Null
& (Join-Path $here 'cover-photo.ps1') -Background (Join-Path $here 'art\cover-art-gemini-A.jpg') -Logo (Join-Path $here 'logo-white.png') -Out $cover -Eyebrow 'خلاصهٔ مدیریتی سپیدنامه  ·  نسخهٔ ۲٫۵'
& (Join-Path $here 'build-booklet.ps1') -BlocksPath $blocks -Cover $cover `
  -Out (Join-Path $OutDir 'sur-whitepaper-executive-summary-NOT-FOR-PUBLICATION.docx') `
  -Pdf (Join-Path $OutDir 'sur-whitepaper-executive-summary-NOT-FOR-PUBLICATION.pdf') `
  -HeaderText 'خلاصهٔ مدیریتی سپیدنامهٔ بلاک‌چین سور' `
  -DocTitle 'خلاصهٔ مدیریتی سپیدنامهٔ بلاک‌چین سور (غیر قابل انتشار)' -NoChapterBreaks
Remove-Item $blocks -ErrorAction SilentlyContinue
