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

    // Signing-key rotation (Family Shield phase 2, owner decision
    // 2026-11-26): the release key that used to be committed here is
    // COMPROMISED (keystore + passwords are public in git history) and must
    // never sign a new build. The release key now comes ONLY from four
    // environment variables (GitHub Actions secrets, see
    // docs/signing-key-rotation.md):
    //   AETHONE_KEYSTORE_B64       base64 of the PKCS12 keystore
    //   AETHONE_KEYSTORE_PASSWORD  store password
    //   AETHONE_KEY_ALIAS          key alias
    //   AETHONE_KEY_PASSWORD       key password
    // All four present -> the release build is signed with that key.
    // Any missing -> the release build is DEBUG-signed and is NOT a release
    // candidate (CI marks it so). There is no other fallback.
    signingConfigs {
        val ksB64 = System.getenv("AETHONE_KEYSTORE_B64")
        val ksPass = System.getenv("AETHONE_KEYSTORE_PASSWORD")
        val keyAlias = System.getenv("AETHONE_KEY_ALIAS")
        val keyPass = System.getenv("AETHONE_KEY_PASSWORD")
        if (!ksB64.isNullOrBlank() && !ksPass.isNullOrEmpty() && !keyAlias.isNullOrBlank() && !keyPass.isNullOrEmpty()) {
            val ksFile = layout.buildDirectory.file("signing/release.p12").get().asFile
            ksFile.parentFile.mkdirs()
            ksFile.writeBytes(java.util.Base64.getMimeDecoder().decode(ksB64.trim()))
            create("release") {
                storeFile = ksFile
                storeType = "PKCS12"
                storePassword = ksPass
                this.keyAlias = keyAlias
                keyPassword = keyPass
            }
        }
    }

    buildTypes {
        release {
            // Secrets present -> the rotated release key; otherwise the
            // debug key (NOT a release candidate). Never the old key.
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
            // v1.1.0 — keep the JNI callback surface (see proguard-rules.pro:
            // libzeptun-jni resolves Zeptun.route by name; R8 stripped it).
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    // v1.1.0 — JVM unit tests of the hybrid-routing policy engine
    // (src/test/kotlin; run by CI's android-apk job).
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
