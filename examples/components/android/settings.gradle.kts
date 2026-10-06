pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "lui-components-android"

include(":app")
include(":lui")
project(":lui").projectDir = file("../../platform/android/lui")
