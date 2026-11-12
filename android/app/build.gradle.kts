plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.chakcaad.aethone"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // AGP 9 disables buildFeatures.resValues BY DEFAULT (the phase-2 CI
    // failure: "Build Type debug contains custom resource values, but the
    // feature is disabled") — the DA variant's resValue app_name needs the
    // feature explicitly back on.
    buildFeatures {
        resValues = true
    }

    defaultConfig {
        applicationId = "com.chakcaad.aethone"
        // minSdk 24 = the recorded CANDIDATE (workflow env note + employer note
        // 2026-10-31): Flutter 3.47.9 default IS 24, but it stays CANDIDATE —
        // symbol-level proof vs bionic API 24 + runtime proof at API 24 are
        // NOT TESTED until M2 wires the native engines into the app.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Test-install signing ONLY: release builds are signed with the
            // debug keystore so the CI APK installs on a real phone. A real
            // release keystore + signing workflow is a recorded open item —
            // no public release may ship from this config.
            signingConfig = signingConfigs.getByName("debug")
            // The launcher label of the MAIN package (the manifest reads
            // @string/app_name so the DA variant below can differ).
            resValue("string", "app_name", "AETHONE")
        }
        debug {
            // DA — Device-Acceptance (the 2026-11-08 precedent, now in the
            // standard low-change form): the debug variant installs BESIDE
            // the main app under its own package id com.chakcaad.aethone.da
            // and its own label. The main applicationId above is NEVER
            // touched — release builds stay com.chakcaad.aethone.
            //
            // Suffix-safety review (PHASE 2, 2026-11-09): the manifest has
            // NO provider authorities, NO deep links and NO custom
            // permissions; both services use RELATIVE class names and are
            // not exported; the DISCONNECT action string is app-internal
            // (never cross-app). Nothing else resolves the package id at
            // build time.
            applicationIdSuffix = ".da"
            versionNameSuffix = "-da"
            resValue("string", "app_name", "AETHONE DA")
        }
    }

    // M2 (engine wiring): the packaged native libraries must be EXTRACTED to
    // nativeLibraryDir — Aether spawns the lyrebird PT binary from there
    // (exec needs a real file with the exec bit; in-APK loading cannot be
    // exec'd). libaether.so / libzeptun-jni.so load fine either way.
    packaging {
        jniLibs {
            useLegacyPackaging = true
            // PHASE-2 CI lesson (run 42617837962): AGP's
            // StripDebugSymbolsTask llvm-strips packaged .so files EVEN IN
            // DEBUG builds when an NDK is present (flutter.ndkVersion pulls
            // r28c on CI). That silently breaks the byte-identity gate — the
            // APK's engine must BE the built engine, sha256-verified — and
            // throws away the symbols the owner wants for on-device crash
            // diagnostics. Keep the Firefox engine EXACTLY as built.
            keepDebugSymbols.add("**/libfirefoxvpn.so")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // M2: NotificationCompat + ServiceCompat for the VpnService foreground
    // notification (specialUse type gating per API level).
    implementation("androidx.core:core-ktx:1.13.1")
    // AndroidX WebKit ProxyController routes the Firefox login WebView
    // through the temporary loopback DNS-aware CONNECT proxy.
    implementation("androidx.webkit:webkit:1.18.0")
}

flutter {
    source = "../.."
}
