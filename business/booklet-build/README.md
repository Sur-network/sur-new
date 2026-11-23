# ساخت کتابچهٔ سپیدنامه (Word)

بازسازی فایل `../sur-whitepaper-booklet-NOT-FOR-PUBLICATION.docx` از متن `../sur-whitepaper.md`؛ نیاز: Node و Microsoft Word روی ویندوز، و قلم Vazirmatn نصب‌شده.

```powershell
node md2blocks.mjs ../sur-whitepaper.md .blocks.json
powershell -NoProfile -ExecutionPolicy Bypass -File build-booklet.ps1 -BlocksPath .blocks.json -Out <مسیر خروجی.docx> -Logo logo-white.png [-Pdf <خروجی.pdf>]
```

- قطع A5، راست‌به‌چپ؛ صفحهٔ ۱ جلد، صفحهٔ ۲ فهرست فصل‌ها (فیلدهای زندهٔ PAGEREF)، صفحهٔ ۳ یادداشت و علامت‌ها، سپس فصل‌ها.
- واترمارک «غیر قابل انتشار» روی همهٔ صفحه‌ها جز جلد؛ جلد نشان خودش را دارد.
- `logo-white.png` نسخهٔ سفیدِ `../../brand/sur-logo-transparent.png` است.
- قلم Vazirmatn در فایل جاسازی می‌شود (در صورت اجازهٔ قلم).
