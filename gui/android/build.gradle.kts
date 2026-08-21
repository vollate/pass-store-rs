allprojects {
    repositories {
        google()
        mavenCentral()
    }
    configurations.configureEach {
        // The Flutter SDK integration_test plugin declares broad/legacy
        // AndroidX Test ranges. Pin one compatible modern family so the app
        // and androidTest APK do not load mismatched ActivityInvoker ABIs.
        resolutionStrategy.force(
            "androidx.test:core:1.6.1",
            "androidx.test:runner:1.6.2",
            "androidx.test:rules:1.6.1",
            "androidx.test.espresso:espresso-core:3.6.1",
            "androidx.test.espresso:espresso-idling-resource:3.6.1",
        )
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
