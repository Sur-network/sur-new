param(
  [string]$BlocksPath,   # JSON from md2blocks.mjs
  [string]$Out,          # output .docx
  [string]$Cover,        # full-page cover image (png, A5 portrait) from cover.ps1
  [string]$Pdf = '',     # optional PDF export for checking
  [string]$HeaderText = 'سپیدنامهٔ بلاک‌چین سور',
  [string]$DocTitle = 'سپیدنامهٔ بلاک‌چین سور (غیر قابل انتشار)',
  [switch]$NoChapterBreaks   # short documents: chapters do not start on a new page
)
$ErrorActionPreference = 'Stop'
function RGBc($r,$g,$b){ return [int]($r + $g*256 + $b*65536) }
$cDark  = RGBc 18 21 74
$cBrand = RGBc 46 49 146
$cAcc   = RGBc 124 134 255
$cTint  = RGBc 238 240 255
$cText  = RGBc 28 30 40
$cGrey  = RGBc 107 111 141
$cLine  = RGBc 214 217 238
$BODY  = 'B Nazanin'            # reading text
$HEAD  = 'IRANSansWeb(FaNum)'   # table headers, running header/footer, watermark
$TITLE = 'Adobe Arabic'         # chapter and section titles, contents
$SZ    = 12                     # body size (pt)
$TOC_TAB_ALIGN = 2

$app = New-Object -ComObject Word.Application
trap { Write-Host ("ERR: " + $_.Exception.Message + " @ line " + $_.InvocationInfo.ScriptLineNumber + " :: " + $_.InvocationInfo.Line.Trim()); try{ $app.Quit(0) }catch{}; break }
$app.Visible = $false
$app.ScreenUpdating = $false
$doc = $app.Documents.Add()
$doc.Content.NoProofing = -1

# ---------- page: A5 booklet, right-to-left ----------
$ps = $doc.PageSetup
$ps.PageWidth = [single]419.53; $ps.PageHeight = [single]595.28
$ps.TopMargin = 54; $ps.BottomMargin = 56; $ps.LeftMargin = 42; $ps.RightMargin = 42
$ps.HeaderDistance = 26; $ps.FooterDistance = 26
$ps.SectionDirection = 0

function SetFont($f,$size,$bold,$color,$font){
  if(-not $font){ $font = $BODY }
  $f.Name = $font; $f.NameBi = $font; $f.NameAscii = $font; $f.NameOther = $font
  $f.Size = [single]$size; $f.SizeBi = [single]$size
  $f.Bold = [int]$bold; $f.BoldBi = [int]$bold; $f.Italic = [int]0; $f.ItalicBi = [int]0
  $f.Color = $color
}
# In Word an RTL paragraph needs wdAlignParagraphRight (2) to sit on the right margin; 3 = justified.
function Rtl($pf){ $pf.ReadingOrder = 0; $pf.Alignment = 2 }
function RtlJ($pf){ $pf.ReadingOrder = 0; $pf.Alignment = 3 }

# ---------- styles ----------
$n = $doc.Styles.Item('Normal')
SetFont $n.Font $SZ 0 $cText $BODY
RtlJ $n.ParagraphFormat
$n.ParagraphFormat.SpaceAfter = 6; $n.ParagraphFormat.SpaceBefore = 0
$n.ParagraphFormat.LineSpacingRule = 5; $n.ParagraphFormat.LineSpacing = $app.LinesToPoints(1.3)
$n.LanguageID = 1065

$h1 = $doc.Styles.Item('Heading 1')
SetFont $h1.Font 26 -1 $cBrand $TITLE
Rtl $h1.ParagraphFormat
$h1.ParagraphFormat.PageBreakBefore = $(if($NoChapterBreaks){0}else{-1}); $h1.ParagraphFormat.KeepWithNext = -1
$h1.ParagraphFormat.SpaceBefore = 0; $h1.ParagraphFormat.SpaceAfter = 14
$h1.ParagraphFormat.LineSpacingRule = 0
$bb = $h1.ParagraphFormat.Borders.Item(-3); $bb.LineStyle = 1; $bb.LineWidth = 12; $bb.Color = $cAcc
$h1.ParagraphFormat.Borders.DistanceFromBottom = 6

$h2 = $doc.Styles.Item('Heading 2')
SetFont $h2.Font 17 -1 $cDark $TITLE
Rtl $h2.ParagraphFormat
$h2.ParagraphFormat.KeepWithNext = -1; $h2.ParagraphFormat.PageBreakBefore = 0
$h2.ParagraphFormat.SpaceBefore = 14; $h2.ParagraphFormat.SpaceAfter = 5
$h2.ParagraphFormat.LineSpacingRule = 0

$lb = $doc.Styles.Item('List Bullet')
SetFont $lb.Font $SZ 0 $cText $BODY
RtlJ $lb.ParagraphFormat
$lb.ParagraphFormat.SpaceAfter = 4

$co = $doc.Styles.Add('SurCallout', 1); $co.BaseStyle = 'Normal'
SetFont $co.Font 11 0 $cText $BODY
RtlJ $co.ParagraphFormat
$co.ParagraphFormat.Shading.BackgroundPatternColor = $cTint
$cb = $co.ParagraphFormat.Borders.Item(-4); $cb.LineStyle = 1; $cb.LineWidth = 24; $cb.Color = $cBrand
$co.ParagraphFormat.Borders.DistanceFromRight = 8
$co.ParagraphFormat.LeftIndent = 8; $co.ParagraphFormat.RightIndent = 8
$co.ParagraphFormat.SpaceBefore = 6; $co.ParagraphFormat.SpaceAfter = 10

$ol = $doc.Styles.Add('SurNumbered', 1); $ol.BaseStyle = 'Normal'
RtlJ $ol.ParagraphFormat
$ol.ParagraphFormat.RightIndent = 18; $ol.ParagraphFormat.FirstLineIndent = -18
$ol.ParagraphFormat.SpaceAfter = 4

$tt = $doc.Styles.Add('SurTocTitle', 1); $tt.BaseStyle = 'Normal'
SetFont $tt.Font 30 -1 $cBrand $TITLE
Rtl $tt.ParagraphFormat
$tt.ParagraphFormat.SpaceAfter = 8; $tt.ParagraphFormat.LineSpacingRule = 0

$tc = $doc.Styles.Add('SurToc', 1); $tc.BaseStyle = 'Normal'
SetFont $tc.Font 15 0 $cText $TITLE
Rtl $tc.ParagraphFormat
$tc.ParagraphFormat.SpaceAfter = 9; $tc.ParagraphFormat.SpaceBefore = 0; $tc.ParagraphFormat.LineSpacingRule = 0
$tc.ParagraphFormat.TabStops.ClearAll()
[void]$tc.ParagraphFormat.TabStops.Add([single]($ps.PageWidth - $ps.LeftMargin - $ps.RightMargin), $TOC_TAB_ALIGN, 1)

# ---------- inline writer ----------
# Segments carry bold (b) and code (c); "\u000B" inside a segment is a manual line break.
function WriteSegs($start,$segs,$baseSize){
  $pos = $start
  foreach($sg in $segs){
    $txt = [string]$sg.s
    if($txt.Length -eq 0){ continue }
    $rg = $doc.Range($pos,$pos)
    $rg.InsertAfter($txt)
    $rg = $doc.Range($pos,$pos+$txt.Length)
    $bv = $(if($sg.b){ -1 } else { 0 })
    $rg.Font.Bold = [int]$bv; $rg.Font.BoldBi = [int]$bv
    $rg.Font.Size = [single]$baseSize; $rg.Font.SizeBi = [single]$baseSize
    if($sg.c){
      $rg.Font.Name = 'Consolas'; $rg.Font.NameAscii = 'Consolas'
      $rg.Font.Size = [single]($baseSize - 2)
      $rg.Shading.BackgroundPatternColor = $cTint; $rg.Font.Color = $cBrand
    } else {
      $rg.Font.Name = $BODY; $rg.Font.NameAscii = $BODY; $rg.Font.NameBi = $BODY
      $rg.Shading.BackgroundPatternColor = -16777216
      $rg.Font.Color = $(if($sg.b){ $cDark } else { $cText })
    }
    $pos += $txt.Length
  }
  return $pos
}
$script:afterTable = $false
function AddPara($segs,$style,$baseSize){
  $p = $doc.Paragraphs.Last
  $p.Range.Style = $style
  $p.Range.ParagraphFormat.Reset()
  $p.Range.Font.Reset()
  if($script:afterTable){ $p.SpaceBefore = 10; $script:afterTable = $false }
  [void](WriteSegs $p.Range.Start $segs $baseSize)
  # justified lines would be stretched before a manual line break, so such paragraphs are right-aligned
  if((@($segs | % { [string]$_.s }) -join '').Contains([string][char]11)){ $doc.Paragraphs.Last.Alignment = 2 }
  $doc.Content.InsertParagraphAfter()
}
function AddTable($rows){
  $nr = $rows.Count
  $nc = 0; foreach($r in $rows){ if($r.Count -gt $nc){ $nc = $r.Count } }
  $p = $doc.Paragraphs.Last
  $p.Range.Style = 'Normal'; $p.Range.ParagraphFormat.Reset()
  $t = $doc.Tables.Add($p.Range, $nr, $nc)
  $t.TableDirection = 0                                  # right-to-left table: first column on the right
  $t.Range.ParagraphFormat.ReadingOrder = 0; $t.Range.ParagraphFormat.Alignment = 2
  $t.Range.ParagraphFormat.SpaceAfter = 0
  $t.Range.ParagraphFormat.LineSpacingRule = 5; $t.Range.ParagraphFormat.LineSpacing = $app.LinesToPoints(1.15)
  $t.TopPadding = 3; $t.BottomPadding = 3; $t.LeftPadding = 5; $t.RightPadding = 5
  for($i=0;$i -lt $nr;$i++){
    $row = $rows[$i]
    for($j=0;$j -lt $nc;$j++){
      $cell = $t.Cell($i+1,$j+1)
      if($j -lt $row.Count){ [void](WriteSegs $cell.Range.Start $row[$j] 10.5) }
    }
  }
  $t.Borders.InsideLineStyle = 1; $t.Borders.OutsideLineStyle = 1
  $t.Borders.InsideColor = $cLine; $t.Borders.OutsideColor = $cLine
  $t.Borders.InsideLineWidth = 4; $t.Borders.OutsideLineWidth = 4
  $hr = $t.Rows.Item(1)
  $hr.Shading.BackgroundPatternColor = $cBrand
  SetFont $hr.Range.Font 8.5 -1 (RGBc 255 255 255) $HEAD
  $hr.HeadingFormat = -1
  for($i=2;$i -le $nr;$i++){ if($i % 2 -eq 1){ $t.Rows.Item($i).Shading.BackgroundPatternColor = (RGBc 247 248 255) } }
  $t.Rows.AllowBreakAcrossPages = 0
  $t.AutoFitBehavior(1); $t.AutoFitBehavior(2)   # size columns to content, then fit the page width
  $script:afterTable = $true
}

# =====================================================================
# SECTION 1: COVER (one full-page image)
# =====================================================================
$doc.Paragraphs.Item(1).Range.Text = ''
$anchor = $doc.Paragraphs.Item(1).Range
$cv = $doc.Shapes.AddPicture($Cover, $false, $true, [single]0, [single]0, [single]419.53, [single]595.28, $anchor)
$cv.RelativeHorizontalPosition = 1; $cv.RelativeVerticalPosition = 1
$cv.WrapFormat.Type = 5; $cv.WrapFormat.AllowOverlap = -1
$cv.LockAspectRatio = 0
$cv.Left = [single]0; $cv.Top = [single]0; $cv.Width = [single]419.53; $cv.Height = [single]595.28
$cv.AlternativeText = 'جلد سپیدنامهٔ بلاک‌چین سور، غیر قابل انتشار'
$cv.Name = 'Cover'
$doc.Content.InsertParagraphAfter()
$doc.Paragraphs.Last.Range.InsertBreak(2)

# =====================================================================
# SECTION 2: CONTENTS + BODY
# =====================================================================
$sec2 = $doc.Sections.Item(2)
$sec2.PageSetup.SectionDirection = 0
$p = $doc.Paragraphs.Last
$p.Range.Style = 'SurTocTitle'
$p.Range.InsertAfter('فهرست مطالب')
$doc.Content.InsertParagraphAfter()
$blocks = Get-Content -Raw -Encoding UTF8 $BlocksPath | ConvertFrom-Json
$chapters = @($blocks | ? { $_.t -eq 'h' -and $_.l -eq 2 })
$nCh = $chapters.Count
for($k = 0; $k -lt $nCh; $k++){
  $q = $doc.Paragraphs.Last; $q.Range.Style = 'SurToc'; $q.Range.ParagraphFormat.Reset()
  $doc.Content.InsertParagraphAfter()
}
$tocFirstIdx = $doc.Paragraphs.Count - $nCh

# front matter (reader's note + legend) starts on its own page after the contents
$doc.Paragraphs.Last.Range.InsertBreak(7)

foreach($b in $blocks){
  switch($b.t){
    'h' {
      if($b.l -eq 1){ continue }   # document title lives on the cover
      $p = $doc.Paragraphs.Last
      $style = $(if($b.l -eq 2){'Heading 1'}else{'Heading 2'})
      $p.Range.Style = $style; $p.Range.ParagraphFormat.Reset()
      $script:afterTable = $false
      $p.Range.InsertAfter($b.text)
      $doc.Content.InsertParagraphAfter()
    }
    'hr' { }
    'p'  { AddPara $b.segs 'Normal' $SZ }
    'li' { AddPara $b.segs 'List Bullet' $SZ }
    'ol' {
      $segs = @(@{ s = ($b.n + '.' + "`t"); b = $true; c = $false }) + @($b.segs)
      AddPara $segs 'SurNumbered' $SZ
    }
    'quote' { AddPara $b.segs 'SurCallout' 11 }
    'table' { AddTable $b.rows }
  }
}
$last = $doc.Paragraphs.Last
if($last.Range.Text.Trim().Length -eq 0){ $r = $last.Range; $r.MoveStart(1,-1) | Out-Null; $r.Delete() | Out-Null }

# ---------- contents: live PAGEREF fields on right-to-left lines ----------
$bm = 0
foreach($par in $doc.Paragraphs){
  if($par.OutlineLevel -eq 1){
    $rgb = $par.Range; [void]$rgb.MoveEnd(1,-1)
    [void]$doc.Bookmarks.Add(('SurH' + $bm), $rgb)
    $bm++
  }
}
for($k = 0; $k -lt $nCh; $k++){
  $q = $doc.Paragraphs.Item($tocFirstIdx + $k)
  $rg = $q.Range; [void]$rg.MoveEnd(1,-1)
  $rg.Text = ([string]$chapters[$k].text + "`t")
  $q = $doc.Paragraphs.Item($tocFirstIdx + $k)
  $pos = $q.Range.End - 1
  [void]$doc.Fields.Add($doc.Range($pos, $pos), -1, ('PAGEREF SurH' + $k + ' \h'), $false)
}

# ---------- every paragraph explicitly right-to-left (not only through styles) ----------
$doc.Content.ParagraphFormat.ReadingOrder = 0

# ---------- running header / page number / watermark (section 2 only) ----------
$hf = $sec2.Headers.Item(1); $hf.LinkToPrevious = $false
$ff = $sec2.Footers.Item(1); $ff.LinkToPrevious = $false
$hr = $hf.Range; $hr.Text = $HeaderText
SetFont $hr.Font 7.5 0 $cGrey $HEAD
Rtl $hr.ParagraphFormat; $hr.ParagraphFormat.SpaceAfter = 0
$hb = $hr.ParagraphFormat.Borders.Item(-3); $hb.LineStyle = 1; $hb.LineWidth = 4; $hb.Color = $cLine
$fr = $ff.Range; $fr.Text = ''
$fr.ParagraphFormat.ReadingOrder = 0; $fr.ParagraphFormat.Alignment = 1
[void]$fr.Fields.Add($fr, 33)
$fr = $ff.Range; SetFont $fr.Font 8.5 0 $cGrey $HEAD; $fr.ParagraphFormat.Alignment = 1; $fr.ParagraphFormat.SpaceAfter = 0
$doc.Sections.Item(1).Headers.Item(1).Range.Text = ''
$doc.Sections.Item(1).Footers.Item(1).Range.Text = ''

$wm = $hf.Shapes.AddTextEffect(0, 'غیر قابل انتشار', $HEAD, 1, 0, 0, 0, 0, $hf.Range)
$wm.Name = 'PowerPlusWaterMarkObject1'
$wm.TextEffect.NormalizedHeight = 0
$wm.Line.Visible = 0
$wm.Fill.Visible = -1; $wm.Fill.Solid(); $wm.Fill.ForeColor.RGB = (RGBc 200 203 230); $wm.Fill.Transparency = [single]0.72
$wm.Rotation = 315; $wm.LockAspectRatio = -1
$wm.Height = 70; $wm.Width = 330
$wm.WrapFormat.AllowOverlap = -1; $wm.WrapFormat.Type = 3
$wm.RelativeHorizontalPosition = 0; $wm.RelativeVerticalPosition = 0
$wm.Left = -999995; $wm.Top = -999995
$wm.ZOrder(5)

# ---------- finish ----------
$doc.Fields.Update() | Out-Null
$doc.EmbedTrueTypeFonts = -1; $doc.SaveSubsetFonts = -1
try{
  $props = $doc.BuiltInDocumentProperties; $bt = [System.__ComObject]
  $ti = $bt.InvokeMember('Item','GetProperty',$null,$props,@('Title'))
  $bt.InvokeMember('Value','SetProperty',$null,$ti,@($DocTitle))
}catch{}
$app.ScreenUpdating = $true
$doc.SaveAs2($Out, 16)
"pages: " + $doc.ComputeStatistics(2)
$doc.Close(0); $app.Quit()

# ---------- watermark: move the WordArt run into the body-section header (Word anchors it to the wrong section) ----------
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$enc = New-Object Text.UTF8Encoding($false)
$src = [IO.Compression.ZipFile]::OpenRead($Out)
$parts = [System.Collections.Specialized.OrderedDictionary]::new()
foreach($e in $src.Entries){
  $ms = New-Object IO.MemoryStream; $st = $e.Open(); $st.CopyTo($ms); $st.Close()
  $parts[$e.FullName] = $ms.ToArray()
}
$src.Dispose()
function GetText($n){ return $enc.GetString($parts[$n]) }
function SetText($n,$t){ $parts[$n] = $enc.GetBytes($t) }
$docXml = GetText 'word/document.xml'
$rels = GetText 'word/_rels/document.xml.rels'
$sect = [regex]::Matches($docXml, '<w:sectPr\b.*?</w:sectPr>', 'Singleline')
$lastSect = $sect[$sect.Count - 1].Value
$rid = [regex]::Match($lastSect, '<w:headerReference w:type="default" r:id="(rId\d+)"').Groups[1].Value
$relM = [regex]::Match($rels, '<Relationship [^>]*Id="' + $rid + '"[^>]*>').Value
$target = 'word/' + [regex]::Match($relM, 'Target="([^"]+)"').Groups[1].Value
$runRx = '<w:r(?: [^>]*)?>(?:<w:rPr>(?:(?!</w:rPr>).)*</w:rPr>)?<w:pict(?: [^>]*)?>.*?</w:pict></w:r>'
$moved = $false
foreach($name in @($parts.Keys | ? { $_ -match '^word/header\d+\.xml$' })){
  $x = GetText $name
  if($name -ne $target -and $x -match 'PowerPlusWaterMark|v:textpath'){
    $m = [regex]::Match($x, $runRx, 'Singleline')
    if($m.Success){
      # the stroke element points at a relationship owned by the source header part; drop it (the shape is unstroked)
      $run = [regex]::Replace($m.Value, '<v:stroke [^>]*/>', '')
      SetText $name ($x.Remove($m.Index, $m.Length))
      $tx = GetText $target
      foreach($ns in @(@('v','urn:schemas-microsoft-com:vml'),@('o','urn:schemas-microsoft-com:office:office'),@('w10','urn:schemas-microsoft-com:office:word'))){
        if($tx -notmatch ('xmlns:' + $ns[0] + '=')){ $tx = $tx.Replace('<w:hdr ', ('<w:hdr xmlns:' + $ns[0] + '="' + $ns[1] + '" ')) }
      }
      $i = $tx.IndexOf('</w:pPr>'); if($i -lt 0){ throw 'no pPr in target header' }
      SetText $target ($tx.Insert($i + 8, $run))
      $moved = $true
    }
  } elseif($name -eq $target -and $x -match 'PowerPlusWaterMark'){ $moved = $true }
}
$tmp = $Out + '.tmp'
if(Test-Path $tmp){ Remove-Item $tmp -Force }
$dst = [IO.Compression.ZipFile]::Open($tmp, 'Create')
$order = @('[Content_Types].xml','_rels/.rels') + @($parts.Keys | ? { $_ -ne '[Content_Types].xml' -and $_ -ne '_rels/.rels' })
foreach($nm in $order){
  $ne = $dst.CreateEntry($nm, [IO.Compression.CompressionLevel]::Optimal)
  $os = $ne.Open(); $os.Write($parts[$nm], 0, $parts[$nm].Length); $os.Close()
}
$dst.Dispose()
Move-Item $tmp $Out -Force
"watermark in $target : $moved"

if($Pdf){
  $app2 = New-Object -ComObject Word.Application; $app2.Visible = $false
  try { $d2 = $app2.Documents.Open($Out, $false, $true); $d2.ExportAsFixedFormat($Pdf, 17); $d2.Close(0) } finally { $app2.Quit() }
}
