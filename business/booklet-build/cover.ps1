param(
  [string]$Logo,          # white logo png (transparent background)
  [string]$Out,           # cover png
  [string]$TitleFont = 'IRANSansWeb(FaNum)',
  [int]$PxW = 1748, [int]$PxH = 2480   # A5 at 300 dpi
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
function RGBc($r,$g,$b){ return [int]($r + $g*256 + $b*65536) }

# ghost copy of the logo (12% opacity) for the large background mark
$ghost = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'sur-logo-ghost.png')
$src = New-Object System.Drawing.Bitmap $Logo
$gb = New-Object System.Drawing.Bitmap $src.Width, $src.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for($y=0;$y -lt $src.Height;$y++){ for($x=0;$x -lt $src.Width;$x++){ $p=$src.GetPixel($x,$y); $gb.SetPixel($x,$y,[System.Drawing.Color]::FromArgb([int]($p.A*0.08),255,255,255)) } }
$gb.Save($ghost,[System.Drawing.Imaging.ImageFormat]::Png); $gb.Dispose(); $src.Dispose()

$W = [single]419.53; $H = [single]595.28
$pp = New-Object -ComObject PowerPoint.Application
try {
  $pres = $pp.Presentations.Add(0)
  $pres.PageSetup.SlideWidth = $W; $pres.PageSetup.SlideHeight = $H
  $s = $pres.Slides.Add(1, 12)   # blank
  $sh = $s.Shapes

  function Rect($l,$t,$w,$h){ $r = $sh.AddShape(1,[single]$l,[single]$t,[single]$w,[single]$h); $r.Line.Visible = 0; return $r }
  function Blob($l,$t,$d,$col,$tr,$soft){ $o = $sh.AddShape(9,[single]$l,[single]$t,[single]$d,[single]$d); $o.Line.Visible = 0; $o.Fill.ForeColor.RGB = $col; $o.Fill.Transparency = [single]$tr; $o.SoftEdge.Radius = [single]$soft; return $o }
  function Txt($text,$l,$t,$w,$h,$font,$size,$bold,$col,$align,$rtl,$spacing){
    $b = $sh.AddTextbox(1,[single]$l,[single]$t,[single]$w,[single]$h)
    $tf = $b.TextFrame2; $tf.MarginLeft = 0; $tf.MarginRight = 0; $tf.MarginTop = 0; $tf.MarginBottom = 0; $tf.WordWrap = -1; $tf.AutoSize = 0
    $tr = $tf.TextRange; $tr.Text = $text
    $tr.Font.Name = $font; $tr.Font.NameComplexScript = $font; $tr.Font.Size = [single]$size; $tr.Font.Bold = [int]$bold
    $tr.Font.Fill.ForeColor.RGB = $col
    if($spacing){ $tr.Font.Spacing = [single]$spacing }
    $tr.ParagraphFormat.TextDirection = [int]$(if($rtl){2}else{1})
    $tr.ParagraphFormat.Alignment = [int]$align   # 1 left, 2 center, 3 right
    return $b
  }

  # 1) background: deep night-indigo, diagonal
  $bg = Rect 0 0 $W $H
  $bg.Fill.TwoColorGradient(3, 1)                       # diagonal
  $bg.Fill.GradientStops.Item(1).Color.RGB = (RGBc 7 9 34)
  $bg.Fill.GradientStops.Item(2).Color.RGB = (RGBc 30 33 112)
  $bg.Fill.GradientStops.Insert((RGBc 16 19 66), [single]0.55)

  # 2) aurora light: soft, blurred colour fields
  [void](Blob -170 -150 420 (RGBc 98 62 255) 0.35 100)
  [void](Blob 200 120 300 (RGBc 0 178 255) 0.55 100)
  [void](Blob -60 380 330 (RGBc 70 52 210) 0.45 100)
  [void](Blob 250 460 260 (RGBc 180 70 255) 0.72 100)

  # 3) large ghost mark of the logo, bleeding off the left edge
  $gm = $sh.AddPicture($ghost, 0, -1, [single]-150, [single]150, [single]430, [single]430)

  # 4) hairline frame + thin rules
  $fr = Rect 22 22 ($W-44) ($H-44); $fr.Fill.Visible = 0; $fr.Line.Visible = -1; $fr.Line.ForeColor.RGB = (RGBc 255 255 255); $fr.Line.Transparency = [single]0.82; $fr.Line.Weight = [single]0.6

  # 5) brand row: logo + wordmark (top right)
  $lg = $sh.AddPicture($Logo, 0, -1, [single]($W-38-64), [single]34, [single]64, [single]64)
  [void](Txt 'SUR' ($W-110-120) 52 120 22 'Segoe UI Semibold' 17 0 (RGBc 255 255 255) 3 $false 6)
  [void](Txt 'BLOCKCHAIN' ($W-110-120) 74 120 14 'Segoe UI' 7.5 0 (RGBc 150 170 255) 3 $false 3)

  # 6) title block (right aligned)
  $R = $W - 46
  [void](Txt 'سپیدنامه  ·  نسخهٔ ۲٫۵' 46 238 ($R-46) 20 $TitleFont 11 0 (RGBc 110 210 255) 3 $true 0)
  $t1 = Txt 'بلاک‌چین' 46 258 ($R-46) 70 $TitleFont 50 -1 (RGBc 255 255 255) 3 $true 0
  $t2 = Txt 'سور' 46 318 ($R-46) 86 $TitleFont 66 -1 (RGBc 255 255 255) 3 $true 0
  $t2.TextFrame2.TextRange.Font.Fill.TwoColorGradient(1, 1)
  $t2.TextFrame2.TextRange.Font.Fill.GradientStops.Item(1).Color.RGB = (RGBc 120 225 255)
  $t2.TextFrame2.TextRange.Font.Fill.GradientStops.Item(2).Color.RGB = (RGBc 170 120 255)
  $acc = Rect ($R-58) 412 58 3; $acc.Fill.TwoColorGradient(2,1); $acc.Fill.GradientStops.Item(1).Color.RGB = (RGBc 0 200 255); $acc.Fill.GradientStops.Item(2).Color.RGB = (RGBc 160 100 255)
  [void](Txt 'شبکهٔ عمومی بلاک‌چین برای توسعه‌دهندگان و کاربران ایرانی' 46 424 ($R-46) 40 $TitleFont 12.5 0 (RGBc 205 212 255) 3 $true 0)

  # 7) glass card with three key facts
  $cy = 478; $cx = 46; $cw = $R - 46; $ch = 54
  $card = $sh.AddShape(5, [single]$cx, [single]$cy, [single]$cw, [single]$ch)
  $card.Adjustments.Item(1) = [single]0.18
  $card.Fill.ForeColor.RGB = (RGBc 255 255 255); $card.Fill.Transparency = [single]0.91
  $card.Line.ForeColor.RGB = (RGBc 255 255 255); $card.Line.Transparency = [single]0.75; $card.Line.Weight = [single]0.6
  $facts = @(@('نهایی‌شدن فوری','اجماع QBFT'), @('۳ ثانیه','زمان هر بلاک'), @('۱۲ قرارداد','پایه، بدون ادمین'))
  $colW = $cw / 3
  for($k=0; $k -lt 3; $k++){
    $x = $cx + $cw - ($k+1)*$colW   # right-to-left order
    [void](Txt $facts[$k][0] $x ($cy+11) $colW 18 $TitleFont 11 -1 (RGBc 255 255 255) 2 $true 0)
    [void](Txt $facts[$k][1] $x ($cy+30) $colW 14 $TitleFont 7.5 0 (RGBc 170 182 240) 2 $true 0)
    if($k -lt 2){ $sep = Rect ($x) ($cy+12) 0.6 ($ch-24); $sep.Fill.ForeColor.RGB = (RGBc 255 255 255); $sep.Fill.Transparency = [single]0.75 }
  }

  # 8) "not for publication" pill + footer
  $pill = $sh.AddShape(5, [single]46, [single]548, [single]118, [single]22)
  $pill.Adjustments.Item(1) = [single]0.5
  $pill.Fill.ForeColor.RGB = (RGBc 255 184 64); $pill.Fill.Transparency = [single]0.86
  $pill.Line.ForeColor.RGB = (RGBc 255 190 80); $pill.Line.Weight = [single]0.9
  $ptr = $pill.TextFrame2; $ptr.MarginLeft = 2; $ptr.MarginRight = 2; $ptr.MarginTop = 0; $ptr.MarginBottom = 0; $ptr.VerticalAnchor = 3
  $ptr.TextRange.Text = 'غیر قابل انتشار'
  $ptr.TextRange.Font.Name = $TitleFont; $ptr.TextRange.Font.NameComplexScript = $TitleFont; $ptr.TextRange.Font.Size = [single]9.5; $ptr.TextRange.Font.Bold = -1
  $ptr.TextRange.Font.Fill.ForeColor.RGB = (RGBc 255 200 100)
  $ptr.TextRange.ParagraphFormat.TextDirection = 2; $ptr.TextRange.ParagraphFormat.Alignment = 2
  [void](Txt 'بنیاد سور  ·  آبان ۱۴۰۵' 170 552 ($R-170) 16 $TitleFont 9 0 (RGBc 180 188 235) 3 $true 0)

  $s.Export($Out, 'PNG', $PxW, $PxH)
  $pres.Close()
} finally { $pp.Quit(); Remove-Item $ghost -ErrorAction SilentlyContinue }
"cover: $Out"
