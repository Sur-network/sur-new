# ساخت کتابچهٔ سپیدنامه (Word)

بازسازی فایل `../sur-whitepaper-booklet-NOT-FOR-PUBLICATION.docx` از متن `../sur-whitepaper.md`. نیازها: Node، و Microsoft Word و PowerPoint روی ویندوز. قلم‌های B Nazanin (متن)، Adobe Arabic (تیترها، فهرست و نوشته‌های کوچک جلد)، B Titr (عنوان بزرگ جلد) و IRANSansWeb(FaNum) (سرصفحه، سرستون جدول‌ها و واترمارک) باید نصب باشند.

```powershell
node md2blocks.mjs ../sur-whitepaper.md .blocks.json
powershell -NoProfile -ExecutionPolicy Bypass -File cover-photo.ps1 -Background <مسیر کامل art/cover-art-gemini-A.jpg> -Logo <مسیر کامل logo-white.png> -Out <مسیر کامل art/cover.png>
powershell -NoProfile -ExecutionPolicy Bypass -File build-booklet.ps1 -BlocksPath .blocks.json -Out <مسیر خروجی.docx> -Cover <مسیر کامل cover.png> [-Pdf <خروجی.pdf>]
```

- قطع A5. همهٔ پاراگراف‌ها و جدول‌ها راست‌به‌چپ‌اند. متن هم‌تراز (justified) است، و عنوان‌ها و جدول‌ها راست‌چین.
- صفحه‌ها به این ترتیب‌اند: ۱ جلد (تصویر تمام‌صفحه‌ای که `cover-photo.ps1` در PowerPoint از طرح Gemini (`art/cover-art-gemini-A.jpg`، بدون نوشته) و عنوان، لوگو و نشان می‌سازد؛ خروجی `art/cover.png`)، ۲ فهرست فصل‌ها (فیلدهای زندهٔ PAGEREF)، ۳ یادداشت و علامت‌ها، و بعد فصل‌ها.
- هر علامت ✅ 🔶 ⚠️ ⏸️ که بعد از متن بیاید به سطر تازه می‌رود (شکست سطر دستی در `md2blocks.mjs`).
- واترمارک «غیر قابل انتشار» روی همهٔ صفحه‌ها هست جز جلد. جلد نشان خودش را دارد. سرصفحه فقط عنوان سند است.
- `logo-white.png` نسخهٔ سفیدِ `../../brand/sur-logo-transparent.png` است.
- در Word، پاراگراف راست‌به‌چپ برای قرارگرفتن روی حاشیهٔ راست به `wdAlignParagraphRight` نیاز دارد. با `wdAlignParagraphLeft` متن به چپ می‌چسبد.
