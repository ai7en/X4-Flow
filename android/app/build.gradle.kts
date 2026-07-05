plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.myapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.x4flow.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 🎯 Split APK по ABI + универсальный APK
    splits {
        abi {
            isEnable = true
            isUniversalApk = true  // Создаёт универсальный APK тоже
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    //  Переименование APK
    applicationVariants.all {
        val variant = this
        variant.outputs.all {
            val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            val fileName = output.outputFileName
            // Универсальный APK: app-universal-release.apk → X4 Flow-1.0.0.apk
            // Split APK: app-arm64-v8a-release.apk → X4 Flow-1.0.0-arm64-v8a.apk
            if (fileName.contains("universal") || !fileName.contains("-")) {
                output.outputFileName = "X4 Flow-${variant.versionName}.apk"
            } else {
                val abiName = fileName
                    .replace("app-", "")
                    .replace("-release.apk", "")
                    .replace("-debug.apk", "")
                output.outputFileName = "X4 Flow-${variant.versionName}-$abiName.apk"
            }
        }
    }
}

flutter {
    source = "../.."
}

tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.add("-Xlint:-options")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}