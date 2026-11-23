param(
  [string]$BlocksPath,   # JSON from md2blocks.mjs
  [string]$Out,      # output .docx
  [string]$Logo,     # white logo png (transparent bg)
  [string]$Pdf = ''  # optional PDF export for checking
)
$ErrorActionPreference = 'Stop'
function RGBc($r,$g,$b){ return [int]($r + $g*256 + $b*65536) }
$cDark  = RGBc 18 21 74
$cBrand = RGBc 46 49 146
$cAcc   = RGBc 124 134 255
$cGold  = RGBc 245 185 66
$cTint  = RGBc 238 240 255
$cText  = RGBc 28 30 58
$cGrey  = RGBc 107 111 141
$cLine  = RGBc 214 217 238
$FONT = 'Vazirmatn'
$TOC_TAB_ALIGN = 2

$global:__wordApp = $null
$app = New-Object -ComObject Word.Application
trap { Write-Host ("ERR: " + $_.Exception.Message + " @ line " + $_.InvocationInfo.ScriptLineNumber + " :: " + $_.InvocationInfo.Line.Trim()); try{ $app.Quit(0) }catch{}; break }
$app.Visible = $false
$app.ScreenUpdating = $false
$doc = $app.Documents.Add()
$doc.Content.NoProofing = -1

# ---------- page: A5 booklet ----------
$ps = $doc.PageSetup
$ps.PageWidth = 419.53; $ps.PageHeight = 595.28
$ps.TopMargin = 54; $ps.BottomMargin = 56; $ps.LeftMargin = 42; $ps.RightMargin = 42
$ps.HeaderDistance = 26; $ps.FooterDistance = 26

function SetFont($f,$size,$bold,$color){
  $f.Name = $FONT; $f.NameBi = $FONT; $f.NameAscii = $FONT; $f.NameOther = $FONT
  $f.Size = [single]$size; $f.SizeBi = [single]$size
  $f.Bold = [int]$bold; $f.BoldBi = [int]$bold; $f.Italic = [int]0; $f.ItalicBi = [int]0
  $f.Color = $color
}
# ---------- styles ----------
$n = $doc.Styles.Item('Normal')
SetFont $n.Font 10 0 $cText
$n.ParagraphFormat.ReadingOrder = 0
$n.ParagraphFormat.Alignment = 0
$n.ParagraphFormat.SpaceAfter = 6; $n.ParagraphFormat.SpaceBefore = 0
$n.ParagraphFormat.LineSpacingRule = 5; $n.ParagraphFormat.LineSpacing = $app.LinesToPoints(1.45)
$n.LanguageID = 1065

$h1 = $doc.Styles.Item('Heading 1')
SetFont $h1.Font 21 -1 $cBrand
$h1.ParagraphFormat.ReadingOrder = 0; $h1.ParagraphFormat.Alignment = 0
$h1.ParagraphFormat.PageBreakBefore = -1; $h1.ParagraphFormat.KeepWithNext = -1
$h1.ParagraphFormat.SpaceBefore = 0; $h1.ParagraphFormat.SpaceAfter = 14
$h1.ParagraphFormat.LineSpacingRule = 0
$bb = $h1.ParagraphFormat.Borders.Item(-3); $bb.LineStyle = 1; $bb.LineWidth = 12; $bb.Color = $cAcc
$h1.ParagraphFormat.Borders.DistanceFromBottom = 6

$h2 = $doc.Styles.Item('Heading 2')
SetFont $h2.Font 12.5 -1 $cDark
$h2.ParagraphFormat.ReadingOrder = 0; $h2.ParagraphFormat.Alignment = 0
$h2.ParagraphFormat.KeepWithNext = -1; $h2.ParagraphFormat.PageBreakBefore = 0
$h2.ParagraphFormat.SpaceBefore = 14; $h2.ParagraphFormat.SpaceAfter = 5
$h2.ParagraphFormat.LineSpacingRule = 0

$lb = $doc.Styles.Item('List Bullet')
SetFont $lb.Font 10 0 $cText
$lb.ParagraphFormat.ReadingOrder = 0; $lb.ParagraphFormat.Alignment = 0
$lb.ParagraphFormat.SpaceAfter = 4

$co = $doc.Styles.Add('SurCallout', 1)
$co.BaseStyle = 'Normal'
SetFont $co.Font 9.5 0 $cText
$co.ParagraphFormat.ReadingOrder = 0; $co.ParagraphFormat.Alignment = 0
$co.ParagraphFormat.Shading.BackgroundPatternColor = $cTint
$cb = $co.ParagraphFormat.Borders.Item(-4); $cb.LineStyle = 1; $cb.LineWidth = 24; $cb.Color = $cBrand
$co.ParagraphFormat.Borders.DistanceFromRight = 8
$co.ParagraphFormat.LeftIndent = 8; $co.ParagraphFormat.RightIndent = 8
$co.ParagraphFormat.SpaceBefore = 6; $co.ParagraphFormat.SpaceAfter = 10

$ol = $doc.Styles.Add('SurNumbered', 1); $ol.BaseStyle = 'Normal'
$ol.ParagraphFormat.ReadingOrder = 0
$ol.ParagraphFormat.RightIndent = 18; $ol.ParagraphFormat.FirstLineIndent = -18
$ol.ParagraphFormat.SpaceAfter = 4

$tt = $doc.Styles.Add('SurTocTitle', 1); $tt.BaseStyle = 'Normal'
SetFont $tt.Font 24 -1 $cBrand
$tt.ParagraphFormat.ReadingOrder = 0; $tt.ParagraphFormat.SpaceAfter = 4
$tt.ParagraphFormat.LineSpacingRule = 0

$tc = $doc.Styles.Add('SurToc', 1); $tc.BaseStyle = 'Normal'
SetFont $tc.Font 11 0 $cText
$tc.ParagraphFormat.ReadingOrder = 0; $tc.ParagraphFormat.Alignment = 0
$tc.ParagraphFormat.SpaceAfter = 9; $tc.ParagraphFormat.SpaceBefore = 0; $tc.ParagraphFormat.LineSpacingRule = 0
$tc.ParagraphFormat.TabStops.ClearAll()
[void]$tc.ParagraphFormat.TabStops.Add([single]($ps.PageWidth - $ps.LeftMargin - $ps.RightMargin), $TOC_TAB_ALIGN, 1)

# ---------- inline writer ----------
function WriteSegs($start,$segs,$baseSize){
  $pos = $start
  foreach($sg in $segs){
    $txt = [string]$sg.s
    if($txt.Length -eq 0){ continue }
    $rg = $doc.Range($pos,$pos)
    $rg.InsertAfter($txt)
    $rg = $doc.Range($pos,$pos+$txt.Length)
    # explicit formatting per segment (inserted text inherits the previous run otherwise)
    $bv = $(if($sg.b){ -1 } else { 0 })
    $rg.Font.Bold = [int]$bv; $rg.Font.BoldBi = [int]$bv
    $rg.Font.Size = [single]$baseSize; $rg.Font.SizeBi = [single]$baseSize
    if($sg.c){
      $rg.Font.Name = 'Consolas'; $rg.Font.NameAscii = 'Consolas'
      $rg.Font.Size = [single]($baseSize - 1)
      $rg.Shading.BackgroundPatternColor = $cTint; $rg.Font.Color = $cBrand
    } else {
      $rg.Font.Name = $FONT; $rg.Font.NameAscii = $FONT; $rg.Font.NameBi = $FONT
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
  $doc.Content.InsertParagraphAfter()
}
function AddTable($rows){
  $nr = $rows.Count
  $nc = 0; foreach($r in $rows){ if($r.Count -gt $nc){ $nc = $r.Count } }
  $p = $doc.Paragraphs.Last
  $p.Range.Style = 'Normal'; $p.Range.ParagraphFormat.Reset()
  $t = $doc.Tables.Add($p.Range, $nr, $nc)
  $t.TableDirection = 0
  $t.Range.Font.Size = [single]8.5; $t.Range.Font.SizeBi = [single]8.5
  $t.Range.ParagraphFormat.SpaceAfter = 0
  $t.Range.ParagraphFormat.LineSpacingRule = 5; $t.Range.ParagraphFormat.LineSpacing = $app.LinesToPoints(1.25)
  $t.TopPadding = 3; $t.BottomPadding = 3; $t.LeftPadding = 4; $t.RightPadding = 4
  for($i=0;$i -lt $nr;$i++){
    $row = $rows[$i]
    for($j=0;$j -lt $nc;$j++){
      $cell = $t.Cell($i+1,$j+1)
      if($j -lt $row.Count){ [void](WriteSegs $cell.Range.Start $row[$j] 8.5) }
    }
  }
  $t.Borders.InsideLineStyle = 1; $t.Borders.OutsideLineStyle = 1
  $t.Borders.InsideColor = $cLine; $t.Borders.OutsideColor = $cLine
  $t.Borders.InsideLineWidth = 4; $t.Borders.OutsideLineWidth = 4
  $hr = $t.Rows.Item(1)
  $hr.Shading.BackgroundPatternColor = $cBrand
  $hr.Range.Font.Color = (RGBc 255 255 255); $hr.Range.Font.Bold = -1; $hr.Range.Font.BoldBi = -1
  $hr.HeadingFormat = -1
  for($i=2;$i -le $nr;$i++){ if($i % 2 -eq 1){ $t.Rows.Item($i).Shading.BackgroundPatternColor = (RGBc 247 248 255) } }
  $t.Rows.AllowBreakAcrossPages = 0
  $t.AutoFitBehavior(2)
  $script:afterTable = $true
}

# =====================================================================
# SECTION 1: COVER
# =====================================================================
$doc.Paragraphs.Item(1).Range.Text = ''
$anchor = $doc.Paragraphs.Item(1).Range
$W = 419.53; $H = 595.28; $R = 62   # right text edge = W - R

function MarkShape($s){ $s.RelativeHorizontalPosition = 1; $s.RelativeVerticalPosition = 1; $s.WrapFormat.Type = 3; $s.WrapFormat.AllowOverlap = -1 }
function NoLine($s){ $s.Line.Visible = 0 }

$bg = $doc.Shapes.AddShape(1, 0, 0, $W, $H, $anchor)
MarkShape $bg; NoLine $bg; $bg.Left = 0; $bg.Top = 0
$bg.Fill.Visible = -1; $bg.Fill.TwoColorGradient(1,1); $bg.Fill.ForeColor.RGB = $cDark; $bg.Fill.BackColor.RGB = $cBrand
$bg.Name = 'CoverBackground'

function Glow($x,$y,$d,$tr){ $s = $doc.Shapes.AddShape(9,$x,$y,$d,$d,$anchor); MarkShape $s; NoLine $s; $s.Fill.ForeColor.RGB = $cAcc; $s.Fill.Transparency = [single]$tr; $s.Left=[single]$x; $s.Top=[single]$y; return $s }
[void](Glow -140 -170 400 0.9)
[void](Glow 230 380 300 0.93)
[void](Glow 300 -40 160 0.94)

# node network motif (echoes the logo)
$nodes = @( @(40,430), @(112,392), @(190,430), @(270,392), @(350,430), @(112,468), @(190,505), @(270,468), @(58,512), @(335,506) )
$edges = @( @(0,1),@(1,2),@(2,3),@(3,4),@(0,5),@(2,6),@(3,7),@(5,6),@(6,7),@(5,8),@(4,9),@(7,9) )
foreach($e in $edges){
  $a = $nodes[$e[0]]; $b = $nodes[$e[1]]
  $ln = $doc.Shapes.AddLine($a[0],$a[1],$b[0],$b[1],$anchor); MarkShape $ln
  $ln.Line.ForeColor.RGB = (RGBc 255 255 255); $ln.Line.Weight = [single]1; $ln.Line.Transparency = [single]0.78
}
foreach($nd in $nodes){
  $s = $doc.Shapes.AddShape(9,$nd[0]-5,$nd[1]-5,10,10,$anchor); MarkShape $s; NoLine $s
  $s.Fill.ForeColor.RGB = (RGBc 255 255 255); $s.Fill.Transparency = [single]0.45; $s.Left = [single]($nd[0]-5); $s.Top = [single]($nd[1]-5)
}

# logo (white), top right
$lg = $doc.Shapes.AddPicture($Logo, $false, $true, $W-$R-84, 34, 104, 104, $anchor)
MarkShape $lg; $lg.Left = [single]($W - $R - 78); $lg.Top = [single]30; $lg.Width = [single]104; $lg.Height = [single]104; $lg.Name = 'CoverLogo'

function TB($txt,$left,$top,$w,$h,$size,$bold,$color,$rtl,$font){
  $s = $doc.Shapes.AddTextbox(1,$left,$top,$w,$h,$anchor); MarkShape $s; NoLine $s
  $s.Fill.Visible = 0
  $s.TextFrame.MarginLeft = 0; $s.TextFrame.MarginRight = 0; $s.TextFrame.MarginTop = 0; $s.TextFrame.MarginBottom = 0
  $s.TextFrame.WordWrap = -1
  $tr = $s.TextFrame.TextRange; $tr.Text = $txt
  $f = $tr.Font; $f.Name = $font; $f.NameBi = $font; $f.NameAscii = $font; $f.Size = [single]$size; $f.SizeBi = [single]$size
  $f.Bold = [int]$bold; $f.BoldBi = [int]$bold; $f.Color = $color
  $tr.ParagraphFormat.ReadingOrder = $(if($rtl){0}else{1})
  $tr.ParagraphFormat.Alignment = 2
  $tr.ParagraphFormat.LineSpacingRule = 0; $tr.ParagraphFormat.SpaceAfter = 0
  $s.Left = [single]$left; $s.Top = [single]$top
  return $s
}
$tw = $W - 2*$R + 20
$left0 = $R - 10
[void](TB 'SUR BLOCKCHAIN   ·   WHITEPAPER' $left0 168 $tw 14 8.5 0 $cAcc $true $FONT)
[void](TB 'سپیدنامه' $left0 188 $tw 72 62 -1 (RGBc 255 255 255) $true $FONT)
[void](TB 'بلاک‌چین سور' $left0 258 $tw 44 30 -1 (RGBc 220 223 255) $true $FONT)
$gl = $doc.Shapes.AddShape(1,$W-$R-52,312,52,3.5,$anchor); MarkShape $gl; NoLine $gl; $gl.Fill.ForeColor.RGB = $cGold; $gl.Left = [single]($W-$R-52); $gl.Top = [single]312
[void](TB 'شبکهٔ عمومی برای توسعه‌دهندگان و کاربران ایرانی؛ طرح نسخهٔ ۲٫۵ به زبان ساده' $left0 328 ($tw-40) 48 12 0 (RGBc 200 205 245) $true $FONT)

# badge: not for publication
$bd = $doc.Shapes.AddShape(5, $W-$R-170, 528, 170, 28, $anchor); MarkShape $bd
$bd.Fill.Visible = 0; $bd.Line.Visible = -1; $bd.Line.ForeColor.RGB = $cGold; $bd.Line.Weight = [single]1.25
$bd.Left = [single]($W-$R-170); $bd.Top = [single]528
$bt = $bd.TextFrame; $bt.MarginLeft = 4; $bt.MarginRight = 4; $bt.MarginTop = 2; $bt.MarginBottom = 2; $bt.VerticalAnchor = 3
$btr = $bt.TextRange; $btr.Text = 'غیر قابل انتشار'
$btr.Font.Name = $FONT; $btr.Font.NameBi = $FONT; $btr.Font.Size = [single]12; $btr.Font.SizeBi = [single]12; $btr.Font.Bold = -1; $btr.Font.BoldBi = -1; $btr.Font.Color = $cGold
$btr.ParagraphFormat.ReadingOrder = 0; $btr.ParagraphFormat.Alignment = 1; $btr.ParagraphFormat.SpaceAfter = 0; $btr.ParagraphFormat.LineSpacingRule = 0
[void](TB 'پیش‌نویس داخلی؛ پیش از حسابرسی مستقل منتشر نمی‌شود' $left0 562 $tw 14 8.5 0 (RGBc 170 176 230) $true $FONT)
[void](TB 'بنیاد سور  ·  آبان ۱۴۰۵' $left0 576 $tw 14 8.5 0 (RGBc 170 176 230) $true $FONT)

# section break -> section 2
$doc.Content.InsertParagraphAfter()
$doc.Paragraphs.Last.Range.InsertBreak(2)

# =====================================================================
# SECTION 2: TOC + BODY
# =====================================================================
$sec2 = $doc.Sections.Item(2)
# TOC page
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

# front matter (reader's note + legend) starts on its own page after the TOC
$doc.Paragraphs.Last.Range.InsertBreak(7)
# body
foreach($b in $blocks){
  switch($b.t){
    'h' {
      if($b.l -eq 1){ continue }   # document title lives on the cover
      $p = $doc.Paragraphs.Last
      $style = $(if($b.l -eq 2){'Heading 1'}else{'Heading 2'})
      $p.Range.Style = $style; $p.Range.ParagraphFormat.Reset()
      if($script:afterTable){ $script:afterTable = $false }
      $p.Range.InsertAfter($b.text)
      $doc.Content.InsertParagraphAfter()
    }
    'hr' { }
    'p'  { AddPara $b.segs 'Normal' 10 }
    'li' { AddPara $b.segs 'List Bullet' 10 }
    'ol' {
      $segs = @(@{ s = ($b.n + '.' + "`t"); b = $true; c = $false }) + @($b.segs)
      AddPara $segs 'SurNumbered' 10
    }
    'quote' { AddPara $b.segs 'SurCallout' 9.5 }
    'table' { AddTable $b.rows }
  }
}
# drop trailing empty paragraph
$last = $doc.Paragraphs.Last
if($last.Range.Text.Trim().Length -eq 0){ $r = $last.Range; $r.MoveStart(1,-1) | Out-Null; $r.Delete() | Out-Null }

# ---------- table of contents (live PAGEREF fields; right-to-left lines) ----------
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
  $fr0 = $doc.Range($pos, $pos)
  [void]$doc.Fields.Add($fr0, -1, ('PAGEREF SurH' + $k + ' \h'), $false)
}

# ---------- headers / footers / watermark (section 2 only) ----------
$hf = $sec2.Headers.Item(1); $hf.LinkToPrevious = $false
$ff = $sec2.Footers.Item(1); $ff.LinkToPrevious = $false
$hr = $hf.Range; $hr.Text = 'سپیدنامهٔ بلاک‌چین سور   |   غیر قابل انتشار'
SetFont $hr.Font 7.5 0 $cGrey
$hr.ParagraphFormat.ReadingOrder = 0; $hr.ParagraphFormat.Alignment = 0; $hr.ParagraphFormat.SpaceAfter = 0
$hb = $hr.ParagraphFormat.Borders.Item(-3); $hb.LineStyle = 1; $hb.LineWidth = 4; $hb.Color = $cLine
$fr = $ff.Range; $fr.Text = ''
$fr.ParagraphFormat.Alignment = 1; $fr.ParagraphFormat.ReadingOrder = 0
[void]$fr.Fields.Add($fr, 33)
$fr = $ff.Range; SetFont $fr.Font 8.5 0 $cGrey; $fr.ParagraphFormat.Alignment = 1; $fr.ParagraphFormat.SpaceAfter = 0
# cover: no header/footer
$doc.Sections.Item(1).Headers.Item(1).Range.Text = ''
$doc.Sections.Item(1).Footers.Item(1).Range.Text = ''

$wm = $hf.Shapes.AddTextEffect(0, 'غیر قابل انتشار', $FONT, 1, 0, 0, 0, 0, $hf.Range)
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
  $bt.InvokeMember('Value','SetProperty',$null,$ti,@('سپیدنامهٔ بلاک‌چین سور (غیر قابل انتشار)'))
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
      $run = $m.Value
      # the stroke element points at a relationship owned by the source header part; drop it (the shape is unstroked anyway)
      $run = [regex]::Replace($run, '<v:stroke [^>]*/>', '')
      SetText $name ($x.Remove($m.Index, $m.Length))
      $tx = GetText $target
      foreach($ns in @(@('v','urn:schemas-microsoft-com:vml'),@('o','urn:schemas-microsoft-com:office:office'),@('w10','urn:schemas-microsoft-com:office:word'))){
        if($tx -notmatch ('xmlns:' + $ns[0] + '=')){ $tx = $tx.Replace('<w:hdr ', ('<w:hdr xmlns:' + $ns[0] + '="' + $ns[1] + '" ')) }
      }
      $i = $tx.IndexOf('</w:pPr>'); if($i -lt 0){ throw 'no pPr in target header' }
      SetText $target ($tx.Insert($i + 8, $run))
      $moved = $true
    }
  }
}
$tmp = $Out + '.tmp'
if(Test-Path $tmp){ Remove-Item $tmp -Force }
$dst = [IO.Compression.ZipFile]::Open($tmp, 'Create')
$order = @('[Content_Types].xml','_rels/.rels') + @($parts.Keys | ? { $_ -ne '[Content_Types].xml' -and $_ -ne '_rels/.rels' })
foreach($n in $order){
  $ne = $dst.CreateEntry($n, [IO.Compression.CompressionLevel]::Optimal)
  $os = $ne.Open(); $os.Write($parts[$n], 0, $parts[$n].Length); $os.Close()
}
$dst.Dispose()
Move-Item $tmp $Out -Force
"watermark moved to $target : $moved"

if($Pdf){
  $app2 = New-Object -ComObject Word.Application; $app2.Visible = $false
  try { $d2 = $app2.Documents.Open($Out, $false, $true); $d2.ExportAsFixedFormat($Pdf, 17); $d2.Close(0) } finally { $app2.Quit() }
}
