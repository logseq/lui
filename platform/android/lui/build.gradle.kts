import org.gradle.api.tasks.testing.Test

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.plugin.compose")
    id("app.cash.paparazzi")
}

group = "dev.lui"

android {
    namespace = "dev.lui"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }

    // The lui_jni_bridge.c source compiles inside the host app (which owns
    // the OCaml static libs), so no externalNativeBuild block is set here
    // deliberately.
}

tasks.withType<Test>().configureEach {
    // Paparazzi on Gradle 9 breaks on HTML test reports (cashapp/paparazzi#2111).
    reports.html.required = false
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation("junit:junit:4.13.2")
    testImplementation("app.cash.paparazzi:paparazzi:2.0.0-alpha04")
}
