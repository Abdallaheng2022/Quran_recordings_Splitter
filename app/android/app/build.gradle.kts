plugins {
    id("com.android.application")
    id("kotlin-android")
    // إضافة Flutter Gradle Plugin يجب أن تأتي بعد إضافات Android و Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.quran_splitter"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.quran_splitter"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // للتجربة والتوزيع المباشر: توقيع debug.
            // للنشر على Google Play أنشئ مفتاح توقيع خاصًا (راجع README).
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
