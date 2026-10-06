import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase Cloud Messaging: needs google-services.json in android/app/.
    id("com.google.gms.google-services")
}

// The release key lives outside version control: android/key.properties names
// the keystore and its passwords. Without that file (a fresh clone, CI) the
// build falls back to the debug key so it still runs.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.nischalpandey.kharcha"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.nischalpandey.kharcha"

        // 23 (Android 6.0) is required by local_auth's BiometricPrompt and by
        // flutter_secure_storage's AES-GCM + RSA key wrapping.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // `flutter build apk --target-platform android-arm,android-arm64`
        // (see tool/release.ps1) leaves the app's own code out for other
        // processors, but the plugins' small native libraries would still be
        // packed for them. A device that found that half-empty folder would
        // choose it and crash for want of the engine, so the same list
        // decides which folders are packed at all. Without the flag (the app
        // bundle, a debug run) Flutter names every processor it builds for.
        //
        // Flutter's own plugin has already filled this list with all three
        // by the time this runs, so it is replaced, not added to.
        (project.findProperty("target-platform") as String?)?.let { platforms ->
            val abis = platforms.split(',').mapNotNull { platform ->
                when (platform.trim()) {
                    "android-arm" -> "armeabi-v7a"
                    "android-arm64" -> "arm64-v8a"
                    "android-x64" -> "x86_64"
                    else -> null
                }
            }
            if (abis.isNotEmpty()) {
                ndk {
                    abiFilters.clear()
                    abiFilters.addAll(abis)
                }
            }
        }
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (hasReleaseKey) "release" else "debug",
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
