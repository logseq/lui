plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

val ocamlInclude = providers.gradleProperty("lui.ocaml.include")
    .orElse(providers.environmentVariable("LUI_OCAML_INCLUDE"))
    .orElse(
        providers.environmentVariable("LUI_MOBILE_TOOLCHAIN_ROOT")
            .map { "$it/lib/ocaml" },
    )
    .orElse(
        providers.environmentVariable("LG_ANDROID_OCAML_PREFIX")
            .map { "$it/lib/ocaml" },
    )
    .orNull

android {
    namespace = "dev.lui.components"
    compileSdk = 35

    defaultConfig {
        applicationId = "dev.lui.components"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"

        externalNativeBuild {
            cmake {
                arguments += listOfNotNull(
                    ocamlInclude?.let { "-DLUI_OCAML_INCLUDE=$it" },
                )
                abiFilters += listOf("arm64-v8a", "x86_64")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

}

dependencies {
    implementation(project(":lui"))
    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
}
