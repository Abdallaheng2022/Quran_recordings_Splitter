# مُقسّم التلاوة — بنية المستودع (بعد تضمين مجلد الأندرويد)

```
app/                          ← مشروع Flutter كامل
├── lib/                      ← كود التطبيق (Dart)
├── pubspec.yaml
└── android/                  ← مشروع الأندرويد الكامل (Gradle/Manifest/الأيقونات)
.github/workflows/build-android.yml
```

لم يعد الـ workflow يولّد أي شيء (`flutter create` أُزيلت) — المستودع يحتوي كل شيء.

## البناء
1. بدّل عنوان `API_BASE` في `build-android.yml` بعنوان سيرفرك.
2. Actions → **Android CI** → Run workflow.
3. نزّل `quran-splitter-apk` من Artifacts.

## ملاحظات
- **غلاف Gradle (gradlew/wrapper) غير مضمَّن عمدًا**: أداة Flutter تحقنه تلقائيًا
  بالنسخة المتوافقة مع إصدارها عند أول بناء — هذا يمنع تعارض النسخ.
- نسخ الإضافات في `android/settings.gradle.kts` (AGP 8.9.1 / Kotlin 2.1.20):
  لو ظهر تحذير/خطأ توافق مع نسخة Flutter المستقبلية، حدّث الرقمين هناك فقط.
- توقيع الإصدار حاليًا بمفتاح debug (يكفي للتوزيع المباشر والتجربة).
  **للنشر على Google Play**: أنشئ keystore خاصًا وأضف signingConfig في
  `android/app/build.gradle.kts` — لا ترفع المفتاح إلى المستودع.
- تغيير اسم الحزمة `com.example.quran_splitter` لاحقًا يتطلب تعديل: namespace
  و applicationId في `android/app/build.gradle.kts` ومسار مجلد `kotlin/…`.
