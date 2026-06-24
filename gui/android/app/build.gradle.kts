plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "top.vollate.pars_gui"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "top.vollate.pars_gui"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir(layout.buildDirectory.dir("rustJniLibs"))
        }
    }
}

androidComponents {
    onVariants { variant ->
        val capitalizedVariantName =
            variant.name.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
        val rustProfile = if (variant.buildType == "release") "release" else "debug"
        val buildParsBridge = tasks.register<Exec>("buildParsBridge$capitalizedVariantName") {
            workingDir = project.rootDir.parentFile.parentFile
            commandLine("bash", "gui/bridge/build_unix.sh", "android")
            environment("PARS_ANDROID_PROFILE", rustProfile)
            environment(
                "PARS_ANDROID_OUTPUT_DIR",
                layout.buildDirectory.dir("rustJniLibs").get().asFile.absolutePath,
            )
        }

        tasks.matching { it.name == "merge${capitalizedVariantName}NativeLibs" }.configureEach {
            dependsOn(buildParsBridge)
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
