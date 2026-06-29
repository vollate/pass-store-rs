import org.gradle.api.tasks.PathSensitivity

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
        val flutterTargetPlatforms =
            (project.findProperty("target-platform") as? String)
                ?.split(",")
                ?.map { it.trim() }
                ?.filter { it.isNotEmpty() }
                ?: listOf("android-arm64")
        val rustAndroidTargets =
            flutterTargetPlatforms.map { targetPlatform ->
                when (targetPlatform) {
                    "android-arm" -> "armeabi-v7a"
                    "android-arm64" -> "arm64-v8a"
                    "android-x64" -> "x86_64"
                    "android-x86" -> "x86"
                    else -> error("Unsupported Flutter Android target platform: $targetPlatform")
                }
            }
        val repoRoot = project.rootDir.parentFile.parentFile
        val rustJniLibsDir = layout.buildDirectory.dir("rustJniLibs")
        val buildParsBridge = tasks.register<Exec>("buildParsBridge$capitalizedVariantName") {
            val rustBridgeInputs = files(
                repoRoot.resolve("Cargo.toml"),
                repoRoot.resolve("Cargo.lock"),
                repoRoot.resolve("rust-toolchain.toml"),
                repoRoot.resolve("gui/bridge/build_unix.sh"),
                fileTree(repoRoot.resolve("bridge")) {
                    include("Cargo.toml")
                    include("src/**")
                },
                fileTree(repoRoot.resolve("core")) {
                    include("Cargo.toml")
                    include("src/**")
                },
            )

            inputs.files(rustBridgeInputs)
                .withPropertyName("rustBridgeInputs")
                .withPathSensitivity(PathSensitivity.RELATIVE)
            inputs.property("rustProfile", rustProfile)
            inputs.property("rustAndroidTargets", rustAndroidTargets.joinToString(","))
            outputs.dir(rustJniLibsDir)
                .withPropertyName("rustJniLibs")

            workingDir = repoRoot
            commandLine("bash", "gui/bridge/build_unix.sh", "android")
            environment("PARS_ANDROID_PROFILE", rustProfile)
            environment("PARS_ANDROID_TARGETS", rustAndroidTargets.joinToString(","))
            environment(
                "PARS_ANDROID_OUTPUT_DIR",
                rustJniLibsDir.get().asFile.absolutePath,
            )
        }

        listOf(
            "merge${capitalizedVariantName}JniLibFolders",
            "merge${capitalizedVariantName}NativeLibs",
        ).forEach { taskName ->
            tasks.matching { it.name == taskName }.configureEach {
                dependsOn(buildParsBridge)
            }
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
