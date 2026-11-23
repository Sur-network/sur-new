param(
  [string]$Background,    # cover artwork without text (e.g. generated in Gemini), portrait
  [string]$Logo,          # white logo png (transparent background)
  [string]$Out,           # cover png
  [string]$TitleFont = 'Adobe Arabic',
  [int]$PxW = 1748, [int]$PxH = 2480   # A5 at 300 dpi
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
function RGBc($r,$g,$b){ return [int]($r + $g*256 + $b*65536) }
$W = [single]419.53; $H = [single]595.28

$img = [System.Drawing.Image]::FromFile($Background); $iw = $img.Width; $ih = $img.Height; $img.Dispose()
$pp = New-Object -ComObject PowerPoint.Application
try {
  $pres = $pp.Presentations.Add(0)
  $pres.PageSetup.SlideWidth = $W; $pres.PageSetup.SlideHeight = $H
  $s = $pres.Slides.Add(1, 12); $sh = $s.Shapes

  # artwork, scaled to cover the page (centred crop)
  $scale = [Math]::Max($W / $iw, $H / $ih)
  $bw = [single]($iw * $scale); $bh = [single]($ih * $scale)
  [void]$sh.AddPicture($Background, 0, -1, [single](($W - $bw) / 2), [single](($H - $bh) / 2), $bw, $bh)

  function Shade($top,$height,$darkAtTop){
    $r = $sh.AddShape(1, [single]0, [single]$top, $W, [single]$height); $r.Line.Visible = 0
    $r.Fill.TwoColorGradient(1, 1)
    $g = $r.Fill.GradientStops
    $g.Item(1).Color.RGB = (RGBc 5 7 28); $g.Item(2).Color.RGB = (RGBc 5 7 28)
    if($darkAtTop){ $g.Item(1).Transparency = [single]0.15; $g.Item(2).Transparency = [single]1 }
    else          { $g.Item(1).Transparency = [single]1;    $g.Item(2).Transparency = [single]0.2 }
  }
  Shade 0 300 $true          # keeps the title area calm and legible
  Shade 470 125.28 $false     # footer band

  function Txt($text,$l,$t,$w,$h,$font,$size,$bold,$col,$align,$rtl,$spacing){
    $b = $sh.AddTextbox(1,[single]$l,[single]$t,[single]$w,[single]$h)
    $tf = $b.TextFrame2; $tf.MarginLeft = 0; $tf.MarginRight = 0; $tf.MarginTop = 0; $tf.MarginBottom = 0; $tf.WordWrap = -1; $tf.AutoSize = 0
    $tr = $tf.TextRange; $tr.Text = $text
    $tr.Font.Name = $font; $tr.Font.NameComplexScript = $font; $tr.Font.Size = [single]$size; $tr.Font.Bold = [int]$bold
    $tr.Font.Fill.ForeColor.RGB = $col
    if($spacing){ $tr.Font.Spacing = [single]$spacing }
    $tr.ParagraphFormat.TextDirection = [int]$(if($rtl){2}else{1})
    $tr.ParagraphFormat.Alignment = [int]$align
    return $b
  }
  $R = $W - 40

  # brand row (top right)
  [void]$sh.AddPicture($Logo, 0, -1, [single]($R-54), [single]30, [single]54, [single]54)
  [void](Txt 'SUR' ($R-60-110) 44 110 20 'Segoe UI Semibold' 15 0 (RGBc 255 255 255) 3 $false 6)
  [void](Txt 'BLOCKCHAIN' ($R-60-110) 64 110 12 'Segoe UI' 6.5 0 (RGBc 170 200 255) 3 $false 3)

  # title block (upper area)
  [void](Txt 'سپیدنامه  ·  نسخهٔ ۲٫۵' 40 120 ($R-40) 24 $TitleFont 15 0 (RGBc 120 220 255) 3 $true 0)
  [void](Txt 'بلاک‌چین' 40 136 ($R-40) 86 $TitleFont 68 -1 (RGBc 255 255 255) 3 $true 0)
  $t2 = Txt 'سور' 40 196 ($R-40) 104 $TitleFont 92 -1 (RGBc 255 255 255) 3 $true 0
  $t2.TextFrame2.TextRange.Font.Fill.TwoColorGradient(1, 1)
  $t2.TextFrame2.TextRange.Font.Fill.GradientStops.Item(1).Color.RGB = (RGBc 255 214 140)
  $t2.TextFrame2.TextRange.Font.Fill.GradientStops.Item(2).Color.RGB = (RGBc 120 220 255)
  $acc = $sh.AddShape(1, [single]($R-56), [single]298, [single]56, [single]2.5); $acc.Line.Visible = 0
  $acc.Fill.ForeColor.RGB = (RGBc 255 200 110)
  [void](Txt 'شبکهٔ بلاک‌چین عمومی برای توسعه‌دهندگان و کاربران ایرانی' 40 306 ($R-40) 40 $TitleFont 16.5 0 (RGBc 220 228 255) 3 $true 0)

  # footer: not-for-publication pill + foundation line
  $pill = $sh.AddShape(5, [single]40, [single]550, [single]112, [single]22)
  $pill.Adjustments.Item(1) = [single]0.5
  $pill.Fill.ForeColor.RGB = (RGBc 255 184 64); $pill.Fill.Transparency = [single]0.8
  $pill.Line.ForeColor.RGB = (RGBc 255 200 100); $pill.Line.Weight = [single]0.9
  $ptf = $pill.TextFrame2; $ptf.MarginLeft = 2; $ptf.MarginRight = 2; $ptf.MarginTop = 0; $ptf.MarginBottom = 0; $ptf.VerticalAnchor = 3
  $ptf.TextRange.Text = 'غیر قابل انتشار'
  $ptf.TextRange.Font.Name = $TitleFont; $ptf.TextRange.Font.NameComplexScript = $TitleFont; $ptf.TextRange.Font.Size = [single]13; $ptf.TextRange.Font.Bold = -1
  $ptf.TextRange.Font.Fill.ForeColor.RGB = (RGBc 255 214 130)
  $ptf.TextRange.ParagraphFormat.TextDirection = 2; $ptf.TextRange.ParagraphFormat.Alignment = 2
  [void](Txt 'بنیاد سور  ·  آبان ۱۴۰۵' 160 551 ($R-160) 22 $TitleFont 13 0 (RGBc 205 212 245) 3 $true 0)

  $s.Export($Out, 'PNG', $PxW, $PxH)
  $pres.Close()
} finally { $pp.Quit() }
"cover: $Out"
