allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Fix: inject a namespace into plugins that don't declare one (AGP 8+ requirement)
subprojects {
    val applyNamespaceFix = {
        if (project.hasProperty("android")) {
            val androidExtension = project.extensions.getByName("android")
            if (androidExtension is com.android.build.gradle.BaseExtension) {
                if (androidExtension.namespace == null) {
                    androidExtension.namespace = project.group.toString()
                }
            }
        }
    }
    if (state.executed) {
        applyNamespaceFix()
    } else {
        afterEvaluate { applyNamespaceFix() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}